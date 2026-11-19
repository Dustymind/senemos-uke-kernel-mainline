# Xiaomi `devauth` TrustZone TA — recovered wire protocol

Recovered statically from the stock ROM. Nothing here was executed; every field
below is a decoded observation, and the parts that remain inference are marked.

## Components, and where each one lives in the stock ROM

| Component | Partition (extracted) | Role |
| --- | --- | --- |
| `devauth.mdt`, `.b00`-`.b08` | **`modem.img`**, FAT16 `::/image/` | the TrustZone applet (ELF64 shared, ~143 KB) |
| `libQSEEComAPI.so` | `vendor/lib64/` | QSEECOM client; `QSEECom_start_app`, `QSEECom_send_cmd` |
| `libminkdescriptor.so` | `vendor/lib64/` | MinkIPC; opens `/dev/smcinvoke` |
| `libqcbor.so` | `vendor/lib64/` | CBOR for the Mink descriptor path |
| `libdmabufheap.so` | `system/lib64/` | dma-buf heap for the Mink path |
| `libmidevauth.so` | `odm/lib64/` | wraps the TA in the `run_cmd` protocol |
| `midevauthd` | `odm/bin/` | AIDL HAL service, `disabled` until `vendor.devauth.keyboard_connected=true` |

Every one of these is present in the shipped partitions. Nothing is missing from
the ROM itself.

## The `run_cmd` protocol (from `libmidevauth.so` `run_cmd` at `0x1042f0`)

`run_cmd(cmd_id, inbuf, insize, outbuf, *outlen)` uses one QSEECom buffer of
`0x2080` bytes, split into a send half at `+0x0000` and a receive half at
`+0x1040`. Both halves are passed to `QSEECom_send_cmd` with a length of
`0x1040`, once:

```
send half (0x1040 bytes)
  0x0000  u32  1                 constant
  0x0004  u32  cmd_id
  0x0008  u32  insize            clamped to <= 0x1000
  0x000c  ...  input payload

recv half (0x1040 bytes)
  0x1040  u32  result code
  0x1044  u32  response length   caller presets 0x1000
  0x1048  ...  response payload
```

The call is retried once (`iVar6` starts at 1, loop runs while `!= -1`, so two
attempts) with `usleep(rand() % 0x79e + 0x32)` between them.

The applet is opened per call with `load_tzapp(&h, "devauth", 0x2080)` and shut
down afterwards. Command ids in `[0x2001, 0x200d]` whose bit is set in `0x190b`
(that is `0x2001`, `0x2002`, `0x2004`, `0x2009`, `0x200c`, `0x200d`) additionally
open `load_tzapp(&h2, "cardapp", 0x800)`.

`0x2010` and `0x2020` are outside that set, so token retrieval needs only
`devauth`.

## Command ids observed

| id | meaning (from the log strings that bracket each call) |
| --- | --- |
| `0x2010` | `devauth get token with online key` |
| `0x2020` | `devauth get token with offline key` |

`devauth_token_get` picks between them on bit 30 of the decimal value derived
from the challenge vector: clear selects `0x2020` (offline), set selects
`0x2010` (online). Our keyboard's challenge tail `4949 0001 0411 1213 2776 0132`
is the same on every device, so the same branch is taken every time; which one
it is has not been confirmed on hardware.

The `keyMeta` argument is CRC-checked before the call: it must be
`<48 hex chars><crc32 of those 24 bytes in decimal>`, otherwise the call is
refused with `uid crc32 verify failed!` before any TA traffic happens.

## Input payload layout for `token_get`

```
hexString(uid) || hexString(challenge) || raw token bytes
```

with the two hex lengths captured in locals `local_98` and `local_9c` and the
tail length from the output vector's size.

## What the Linux kernel is missing

`libQSEEComAPI.so` exposes `QSEECom_start_app`, which loads a TA that is not yet
resident. The mainline kernel implements only two of the three SCM app commands:

```
drivers/firmware/qcom/qcom_scm.c
  enum qcom_scm_qseecom_tz_cmd_app {
          QSEECOM_TZ_CMD_APP_SEND   = 1,   /* present */
          QSEECOM_TZ_CMD_APP_LOOKUP = 3,   /* present */
  };                                        /* load, presumed 2, absent */
```

So `qcom_scm_qseecom_app_get_id("devauth", ...)` can only find an applet that is
already resident, and `qcom_qseecom_apps[]` in
`drivers/firmware/qcom/qcom_qseecom.c` lists only `qcom.tz.uefisecapp`.

Two gaps, then:

1. `QSEECOM_TZ_CMD_APP_LOAD` (the id is inferred from the gap, not observed).
2. A `send_cmd` that accepts the caller-supplied `0x1040`-byte request and reply
   the way `run_cmd` above expects. `qcom_scm_qseecom_app_send()` already does
   exactly this shape — it takes `req`/`rsp` with separate sizes and returns the
   TA's result — so only the load step is genuinely new.

No Binder, no `smcinvoke`, no Android userspace is required for this path. The
`/dev/smcinvoke` route that `libQSEEComAPI.so` also supports is a dead end on
Linux because `smcinvoke_dlkm.ko` is an Android 6.1 vendor module with
`vermagic 6.1.68-android14` and pulls `mem_buf_dev` and `qseecom_proxy`.

## Remaining unknowns

- Whether TZ accepts a TA load for `devauth` from a non-Android Linux kernel, or
  gates it on a signed/attested boot state. Not determinable statically.
- The exact `QSEECOM_TZ_CMD_APP_LOAD` command id.
- Whether the applet's persistent state under `/mnt/vendor/persist/data/devauth`
  (root key, online derived key, black UID list, UID list) has already been
  provisioned on this tablet, and what happens if it is absent.
- Which of `0x2010`/`0x2020` the keyboard token actually needs.

## Status: probe landed

`patches/7.3.0/0128-qseecom-load-applets.patch` (kernel `407f8d6`) adds
`QSEECOM_TZ_CMD_APP_LOAD` and `qcom_scm_qseecom_app_load()`, wires `devauth`
into `qcom_qseecom_apps[]` with `load=true` and `sb_size=0x2080`, and adds
`xiaomi,uke` to the machine allowlist.  It exposes no userspace interface: the
point is to find out whether TZ accepts the load at all.

Read the boot log for one of:

```
qcom_qseecom: setting up client for devauth
qcom_scm: failed to load devauth: ...
qcom_scm: qseecom load devauth: TZ refused (result=... resp_type=... data=...)
qcom_scm: qseecom: untested machine, skipping          <- allowlist missed
```

The `result`/`resp_type`/`data` triple on refusal is the diagnostic that decides
whether the remaining work (misc device plus a token client) is worth doing.
