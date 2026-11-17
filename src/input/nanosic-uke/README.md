# Uke pogo keyboard (Nanosic 803)

18 November 2026. Source candidate. It has not been built into a kernel RPM, not
booted, and no key, touchpad or backlight event has been observed. Treat every
claim below as device-tree and driver evidence only.

## Hardware path

The stock uke DTB already carries the controller:

```
/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000/nanosic@4c
  compatible        "nanosic,803"
  reg               0x4c
  vdd-supply, dvdd-supply
  nanosic,vdd-name  "vdd"
  nanosic,dvdd-name "dvdd"
  irq_pin           116 (active low)
  reset_pin         127
  sleep_pin          98
  status_pin        128
```

and the parent bus is `status = "disabled"`, `qcom,clk-freq-out = <1000000>`.
Read on a booted Fedora tablet on 2026-11-18. No i2c adapter existed for
`a8c000`, so no client at `0x4c` was ever created and nothing can bind.

## What this change adds

- `src/boot/uke-identity.c` enables the bus before
  `of_platform_default_populate_init()` runs, replaces `compatible` with
  `qcom,geni-i2c`, adds `clock-frequency = <400000>` (mainline geni i2c does not
  read `qcom,clk-freq-out`) and publishes `irq-gpios`, `reset-gpios`,
  `sleep-gpios` and `vdd-gpios` from the OEM pin cells.
- It also derives `touchpad-resolution-x/y` from the OEM
  `touchpad,edge-area-right-max` and `touchpad,edge-area-bottom-max` cells plus
  one. The driver aborts touchpad registration without them, and the stock node
  carries neither.
- `nanosic-803.c` is the pipa tree driver for 6.15.11 with three changes:
  supplies are fetched as `vdd`/`dvdd`, the threaded IRQ relies on the GPIO
  trigger from the device tree instead of hard-coded flags, and a stale
  `desc_to_gpio()` diagnostic is gone.

## Not implemented

MiAuth (command `0x31`). The Android stack authenticates the accessory through
`midevauthd` and a TrustZone `devauth` trustlet; there is no equivalent channel
in this kernel. Expect the controller to stop reporting after an idle timeout
until that is measured on hardware.

## Open items

- No compile against the 7.3 source, no boot, no input acceptance.
- IRQ cell flags `0x2001` are interpreted as `GPIO_ACTIVE_LOW`; if the wake-up
  poll in `nanosic_803_wakeup()` times out, that interpretation is the first
  thing to revisit.
- `status_pin` is mapped to `vdd-gpios` (the driver's power-enable line). This
  follows the muyu sibling node and the driver's `vdd` usage, not a
  schematic.
- The bus runs at 400 kHz here while stock uses 1 MHz.
