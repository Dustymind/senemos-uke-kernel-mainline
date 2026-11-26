#!/usr/bin/env bash
# Prepare the Uke secure RTC offset source path.
set -Eeuo pipefail
kernel=$(realpath "${1:?kernel source}")
output=$(realpath "${2:?source receipt directory}")
owner=$(cd -- "$(dirname -- "$0")/../.." && pwd)
git -C "$kernel" apply "$owner/patches/rtc/0001-uke-secure-rtc-offset.patch"
install -m644 "$owner/src/rtc/uke-rtc-policy.h" "$kernel/include/linux/uke-rtc-policy.h"
install -m644 "$owner/src/boot/uke-rtc.h" "$kernel/arch/arm64/kernel/uke-rtc.h"
printf 'secure RTC source prepared\n'
