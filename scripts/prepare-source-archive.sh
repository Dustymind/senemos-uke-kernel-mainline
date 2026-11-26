#!/usr/bin/env bash
# Prepare a Uke-modified, non-Git Linux source archive.
#
# Inputs come from this branch and source-cache/releases/linux-7.3.1.tar.xz.
# The resulting tar.xz contains the patched source tree, Uke native source
# additions and the final config, but no .git directory or build output.
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_arg=""
output="$root/build/linux-7.3.1-uke.tar.xz"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) source_arg=${2:?}; shift 2;;
        --output) output=${2:?}; shift 2;;
        --jobs) jobs=${2:?}; shift 2;;
        --help|-h)
            cat <<'HELP'
Usage: scripts/prepare-source-archive.sh [options]
  --source PATH   Linux source directory or .tar.xz. Default: source-cache/releases/linux-7.3.1.tar.xz
  --output FILE   Output archive. Default: build/linux-7.3.1-uke.tar.xz
  --jobs N        Prepare parallel jobs. Default: nproc
HELP
            exit 0;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1;;
    esac
done

[ -n "$source_arg" ] || source_arg="$root/source-cache/releases/linux-7.3.1.tar.xz"
mkdir -p "$(dirname -- "$output")"
output=$(realpath -m "$output")
mkdir -p "$root/build"
work=$(mktemp -d "$root/build/.source-archive.XXXXXX")
cleanup() { find "$work" -depth -delete; }
trap cleanup EXIT

if [ -d "$source_arg" ]; then
    cp -a "$source_arg"/. "$work"/
else
    tar -xf "$source_arg" -C "$work" --strip-components=1
fi
rm -rf "$work/.git" "$work/native-generated"

if [ ! -d "$work/.git" ]; then
    git -C "$work" init -q
    git -C "$work" add -A
    git -C "$work" -c user.name=uke -c user.email=uke@local commit -q -m source
fi
while IFS= read -r patch_name; do
    [ -n "$patch_name" ] || continue
    git -C "$work" apply "$root/patches/7.3.0/$patch_name"
done < "$root/patches/7.3.0/series"

bash "$root/scripts/prepare-source.sh" "$work"

# The final config belongs with the prepared source, but is not a .config so
# consumers can inspect it before copying it into place.
install -Dm644 "$root/configs/arm64-uke.config" "$work/configs/arm64-uke.config"

epoch=$(jq -er .source_date_epoch "$root/manifests/linux-7.3.1.json")
cat > "$work/SOURCE-INFO.txt" <<EOF
source=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz
signature=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.sign
uke_repository=https://github.com/Dustymind/senemos-uke-kernel-mainline.git
uke_branch=simplify-kernel-repo
patches=128
config=configs/arm64-uke.config
EOF
rm -rf "$work/.git" "$work/.uke-7.3.0-series-applied" "$work/.uke-native-prepared"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
    -cJf "$output" -C "$work" .

printf 'Prepared archive: %s\n' "$output"
printf 'SHA-256: %s\n' "$(sha256sum "$output" | cut -d' ' -f1)"
