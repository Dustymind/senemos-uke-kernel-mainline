# Senemos Uke Kernel

> modified to provide a simplified build method

Linux 7.3.1 arm64 source branch for Xiaomi Pad 7 / POCO Pad X1 (`uke`, SM7675).

## Contents

```text
patches/7.3.0/                  Uke kernel patch series
src/                            Uke device source additions
configs/arm64-uke.config        Final merged arm64 config
packaging/native/               Native config and profile metadata
manifests/                      Source descriptions
```

## Prepare source archive

Create a non-Git, prepared Linux source archive with the Uke patch series,
native source additions and final config:

```bash
bash scripts/prepare-source-archive.sh \
    --source source-cache/releases/linux-7.3.1.tar.xz \
    --output build/linux-7.3.1-uke.tar.xz
```

The archive contains `configs/arm64-uke.config`, `SOURCE-INFO.txt` and no
`.git` directory or build output.

## Build kernel

Native arm64:

```bash
make build-kernel
```

Non-arm64 host (any architecture):

```bash
CROSS_COMPILE=aarch64-linux-gnu- \
CLANG_TRIPLE=aarch64-linux-gnu \
make build-kernel
```

Explicit source tree or archive:

```bash
bash scripts/build-kernel.sh \
    --source /path/to/linux-7.3.1 \
    --out build/kernel \
    --jobs 8
```

Use an already patched source tree:

```bash
bash scripts/build-kernel.sh --source /path/to/prepared-linux --no-patches
```

Default output:

```text
build/kernel/arch/arm64/boot/Image
build/kernel/modules/
```

## Build boot.img

Build the stock-template boot image from a prepared kernel tree:

```bash
make build-boot-img STOCK=/path/to/stock-uke-boot.img AVBTOOL=/path/to/avbtool
```

The default partition name is `userdata`, producing `boot2userdata.img`. For a
multi-boot setup, set `PARTITION_NAME` to the corresponding partition name,
for example `linux`:

```bash
make build-boot-img \
    STOCK=/path/to/stock-uke-boot.img \
    AVBTOOL=/path/to/avbtool \
    PARTITION_NAME=linux
```

Equivalent explicit invocation:

```bash
bash scripts/build-boot-img.sh \
    --kernel build/kernel/source \
    --out build/boot \
    --release 7.3.1-107 \
    --partition-name userdata \
    --stock /path/to/stock-uke-boot.img \
    --avbtool /path/to/avbtool
```

Select the USB profile written to `native-generated/usb-profile`:

```bash
make build-boot-img STOCK=... AVBTOOL=... USB_PROFILE=typec-v1
make build-boot-img STOCK=... AVBTOOL=... USB_PROFILE=peripheral
```

Build only the initramfs base:

```bash
bash scripts/make-initramfs-base.sh \
    --out build/initramfs-base \
    --release 7.3.1-107
```

Boot output:

```text
build/boot/payload/boot2userdata.img
build/boot/payload/boot2linux.img  # when PARTITION_NAME=linux
```

All build failures print an error and exit with status `1`.
