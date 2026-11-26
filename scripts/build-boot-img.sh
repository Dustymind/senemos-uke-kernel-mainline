#!/usr/bin/env bash
# Build Uke boot images from a prepared kernel source tree.
set -Eeuo pipefail
trap 'printf "build-boot-img failed at line %s\n" "$LINENO" >&2; exit 1' ERR

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
kernel=""
out="$root/build/boot"
base=""
release="7.3.1-107"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
usb_profile="${USB_PROFILE:-}"
partition_name="${PARTITION_NAME:-userdata}"
stock=""
avbtool=""

usage() {
    cat <<'EOF'
Usage: scripts/build-boot-img.sh --kernel DIR [options]

Options:
  --kernel DIR        Prepared kernel source tree. Required.
  --out DIR           Output directory. Default: build/boot
  --base DIR          Existing initramfs base. If omitted, one is generated.
  --release VERSION   Kernel release. Default: 7.3.1-107
  --jobs N            Parallel jobs. Default: $JOBS or nproc
  --usb-profile NAME   native-generated/usb-profile value: typec-v1 or peripheral.
                      Default: $USB_PROFILE or packaging/native/usb-profile.
  --partition-name NAME
                      Root partition profile. Default: $PARTITION_NAME or userdata.
                      Use linux for a normal Linux root or another boot target.
  --stock FILE        96 MiB stock Android boot v4 image. Required.
  --avbtool FILE      avbtool executable. Required.
  --help              Show this help.

The script detects native arm64 or any non-arm64 cross host. On a non-arm64
host it builds the AArch64 helper binaries used by the payload.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --kernel) kernel=${2:?}; shift 2;;
        --out) out=${2:?}; shift 2;;
        --base) base=${2:?}; shift 2;;
        --release) release=${2:?}; shift 2;;
        --jobs) jobs=${2:?}; shift 2;;
        --usb-profile) usb_profile=${2:?}; shift 2;;
        --partition-name) partition_name=${2:?}; shift 2;;
        --stock) stock=${2:?}; shift 2;;
        --avbtool) avbtool=${2:?}; shift 2;;
        --help|-h) usage; exit 0;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1;;
    esac
done

kernel=$(realpath "$kernel")
mkdir -p "$out"
out=$(realpath "$out")

if [ -z "$base" ]; then
    base="$out/base"
    bash "$root/scripts/make-initramfs-base.sh" --out "$base" --release "$release" --jobs "$jobs"
else
    base=$(realpath "$base")
fi

usb_receipt="$kernel/native-generated/usb-profile"
mkdir -p "$(dirname "$usb_receipt")"
if [ -n "$usb_profile" ]; then
    printf '%s
' "$usb_profile" > "$usb_receipt"
elif [ ! -f "$usb_receipt" ]; then
    cp "$root/packaging/native/usb-profile" "$usb_receipt"
fi

host_arch=$(uname -m)
cross_env=()
case "$host_arch" in
    aarch64|arm64)
        cross_env=(UKE_CROSS_KERNEL=0)
        ;;
    *)
        if [ -n "${CROSS_COMPILE:-}" ]; then
            cross_prefix=$CROSS_COMPILE
        elif command -v aarch64-linux-gnu-g++ >/dev/null 2>&1; then
            cross_prefix=aarch64-linux-gnu-
        else
            cross_prefix=aarch64-linux-gnu-
        fi
        if [ -n "${CXX:-}" ]; then
            cxx=("$CXX")
        elif command -v "${cross_prefix}g++" >/dev/null 2>&1; then
            cxx=("${cross_prefix}g++")
        else
            cxx=(clang++ --target=aarch64-linux-gnu)
        fi
        cross_env=(UKE_CROSS_KERNEL=1 "UKE_PREBUILT_SWITCH_ROOT=$out/uke-offline-switch-root"
            "CROSS_COMPILE=$cross_prefix" "CLANG_TRIPLE=${CLANG_TRIPLE:-aarch64-linux-gnu}")
        "${cxx[@]}" -std=c++17 -O2 -Wall -Wextra -Werror \
            -ffile-prefix-map="$root"=. \
            "$root/src/boot/offline-switch-root.cpp" -o "$out/uke-offline-switch-root"
        "${cxx[@]}" -std=c++20 -O2 -Wall -Wextra -Werror \
            "$root/src/boot/boot-image.cpp" -o "$out/boot-image-aarch64"
        cp "$out/boot-image-aarch64" "$(dirname "$base")/boot-image-aarch64"
        ;;
esac

env "${cross_env[@]}" bash "$root/src/boot/build-payload.sh" \
    "$kernel" "$out/payload" "$base" "$release" "$jobs"

"$out/payload/boot-image" pack "$stock" "$out/payload/arch/arm64/boot/Image" \
    "$out/payload/boot2${partition_name}.img" 100663296 "$partition_name"
payload_end=$("$out/payload/boot-image" inspect "$out/payload/boot2${partition_name}.img" | jq -er .payload_end)
truncate -s "$payload_end" "$out/payload/boot2${partition_name}.img"
stock_hash=$(sha256sum "$stock" | cut -d' ' -f1)
rollback=$(python3 "$avbtool" info_image --image "$stock" 2>/dev/null |
    sed -n 's/^Rollback Index:[[:space:]]*//p')
props=()
while IFS= read -r prop; do
    props+=(--prop "$prop")
done < <(python3 "$avbtool" info_image --image "$stock" 2>/dev/null |
    sed -nE "s/^[[:space:]]*Prop: ([A-Za-z0-9_.-]+) -> '(.*)'$/\1:\2/p")
python3 "$avbtool" add_hash_footer --image "$out/payload/boot2${partition_name}.img" \
    --partition_name boot --partition_size 100663296 --algorithm NONE \
    --salt "$stock_hash" --rollback_index "$rollback" "${props[@]}"
python3 "$avbtool" verify_image --image "$out/payload/boot2${partition_name}.img"

printf 'Boot image build complete: %s\n' "$out/payload"
