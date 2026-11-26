#!/usr/bin/env bash
# Build the Uke Linux arm64 kernel on native arm64 or any non-arm64 host.
set -Eeuo pipefail
trap 'printf "build-kernel failed at line %s\n" "$LINENO" >&2; exit 1' ERR

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_arg=""
out="$root/build/kernel"
config="$root/configs/arm64-uke.config"
release="7.3.1-107"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
apply_patches=1

usage() {
    cat <<'EOF'
Usage: scripts/build-kernel.sh [options]

Options:
  --source PATH       Prepared Linux source directory, or a .tar.xz archive.
                      Default: source-cache/releases/linux-7.3.1.tar.xz
  --out DIR           Build output directory. Default: build/kernel
  --config FILE       Full kernel config. Default: configs/arm64-uke.config
  --release VERSION   Release used in the build manifest. Default: 7.3.1-107
  --jobs N            Parallel jobs. Default: $JOBS or nproc
  --no-patches        Do not apply patches/7.3.0/series
  --help              Show this help.

Cross compilation:
  On a non-arm64 host the script uses CROSS_COMPILE=aarch64-linux-gnu- and
  CLANG_TRIPLE=aarch64-linux-gnu unless overridden. The host architecture is
  detected generically; x86_64 is not special-cased.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) source_arg=${2:?}; shift 2;;
        --out) out=${2:?}; shift 2;;
        --config) config=${2:?}; shift 2;;
        --release) release=${2:?}; shift 2;;
        --jobs) jobs=${2:?}; shift 2;;
        --no-patches) apply_patches=0; shift;;
        --help|-h) usage; exit 0;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1;;
    esac
done

mkdir -p "$out"
out=$(realpath "$out")

if [ -z "$source_arg" ]; then
    source_arg="$root/source-cache/releases/linux-7.3.1.tar.xz"
fi

if [ -d "$source_arg" ]; then
    source=$(realpath "$source_arg")
else
    source="$out/source"
    mkdir -p "$source"
    tar -xf "$source_arg" -C "$source" --strip-components=1
fi

# All source preparation uses a local Git tree so that git apply is ordered
# and repeatable on a freshly extracted upstream archive.
if [ ! -d "$source/.git" ]; then
    git -C "$source" init -q
    git -C "$source" add -A
    git -C "$source" -c user.name=uke -c user.email=uke@local commit -q -m source
fi

if (( apply_patches )); then
    marker="$source/.uke-7.3.0-series-applied"
    if [ ! -e "$marker" ]; then
        while IFS= read -r patch_name; do
            [ -n "$patch_name" ] || continue
            git -C "$source" apply "$root/patches/7.3.0/$patch_name"
        done < "$root/patches/7.3.0/series"
        : > "$marker"
    fi
fi
if [ ! -e "$source/.uke-native-prepared" ]; then
    bash "$root/scripts/prepare-source.sh" "$source"
    : > "$source/.uke-native-prepared"
fi

install -m 0644 "$config" "$out/.config"
"$source/scripts/config" --file "$out/.config" --set-str INITRAMFS_SOURCE ''

host_arch=$(uname -m)
case "$host_arch" in
    aarch64|arm64)
        cross="${CROSS_COMPILE:-}"
        triple="${CLANG_TRIPLE:-aarch64-linux-gnu}"
        ;;
    *)
        cross="${CROSS_COMPILE:-aarch64-linux-gnu-}"
        triple="${CLANG_TRIPLE:-aarch64-linux-gnu}"
        ;;
esac

make_args=(ARCH=arm64 LLVM=1)
if [ -n "$cross" ]; then
    make_args+=(CROSS_COMPILE="$cross" CLANG_TRIPLE="$triple")
fi
localversion=${LOCALVERSION:-}
if [ -z "$localversion" ]; then
    localversion="-${release#*-}"
fi
make_args+=(LOCALVERSION="$localversion")

make -C "$source" O="$out" "${make_args[@]}" olddefconfig
make -C "$source" O="$out" "${make_args[@]}" -j"$jobs" Image modules dtbs
make -C "$source" O="$out" "${make_args[@]}" modules_install \
    INSTALL_MOD_PATH="$out/modules" INSTALL_MOD_STRIP=1

cat > "$out/build-manifest" <<EOF
format=1
host_arch=$host_arch
target_arch=arm64
cross_compile=${cross:-native}
clang_triple=$triple
release=$release
config=$(sha256sum "$config" | cut -d' ' -f1)
kernel=$(sha256sum "$out/arch/arm64/boot/Image" | cut -d' ' -f1)
modules_dir=$out/modules
EOF

printf 'Kernel build complete: %s\n' "$out"
