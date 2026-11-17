#!/usr/bin/env bash
# Explicit host-only staging; no kernel config or DT selection.
set -Eeuo pipefail
[[ $# == 1 && -d $1/drivers/input/touchscreen && -d $1/drivers/input/keyboard && -d $1/include/linux ]] || exit 2
kernel=$(realpath "$1")
here=$(cd -- "$(dirname -- "$0")" && pwd)
destination=$kernel/drivers/input/touchscreen/nt36532-uke
[[ ! -e $destination ]]
if grep -q 'nt36532-uke' "$kernel/drivers/input/touchscreen/Kconfig" "$kernel/drivers/input/touchscreen/Makefile"; then
    printf 'Uke THP staging entry already exists\n' >&2; exit 1
fi
mkdir "$destination"
install -m644 "$here/"nt36532-uke-{protocol.c,protocol.h,matrix.c,matrix.h,spi.c} "$here/Kconfig" "$here/Makefile" "$destination/"
install -m644 "$here/../display/uke-o82-touch.h" "$kernel/include/linux/uke-o82-touch.h"
printf '\nsource "drivers/input/touchscreen/nt36532-uke/Kconfig"\n' >> "$kernel/drivers/input/touchscreen/Kconfig"
printf '\nobj-$(CONFIG_TOUCHSCREEN_NT36532_UKE) += nt36532-uke/\n' >> "$kernel/drivers/input/touchscreen/Makefile"

keyboard=$kernel/drivers/input/keyboard
[[ ! -e $keyboard/nanosic-803.c ]]
if grep -q 'nanosic-803' "$keyboard/Kconfig" "$keyboard/Makefile"; then
    printf 'Uke pogo keyboard staging entry already exists\n' >&2; exit 1
fi
install -m644 "$here/nanosic-uke/nanosic-803.c" "$keyboard/nanosic-803.c"
printf '\n' >> "$keyboard/Kconfig"
cat "$here/nanosic-uke/Kconfig" >> "$keyboard/Kconfig"
printf '\nobj-$(CONFIG_KEYBOARD_XIAOMI_NANOSIC803) += nanosic-803.o\n' >> "$keyboard/Makefile"
printf 'Uke THP and pogo keyboard sources staged; kernel configuration and device tree unchanged\n'
