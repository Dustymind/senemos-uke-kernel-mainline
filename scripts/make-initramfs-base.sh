#!/usr/bin/env bash
# Build the Uke initramfs base on arm64 or a non-arm64 cross host.
set -Eeuo pipefail
trap 'printf "make-initramfs-base failed at line %s\n" "$LINENO" >&2; exit 1' ERR

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=""
release="7.3.1-107"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

usage() {
    cat <<'EOF'
Usage: scripts/make-initramfs-base.sh --out DIR [options]

Options:
  --out DIR           New initramfs base directory. Required.
  --release VERSION   Kernel release. Default: 7.3.1-107
  --jobs N            Parallel jobs passed to the helper builds.
  --help              Show this help.

The generated directory contains the dracut base, the Uke dracut module and
the AArch64 boot-status/userdata-grow helpers required by build-payload.sh.
It intentionally contains no kernel modules or firmware.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out) out=${2:?}; shift 2;;
        --release) release=${2:?}; shift 2;;
        --jobs) jobs=${2:?}; shift 2;;
        --help|-h) usage; exit 0;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1;;
    esac
done

out=$(realpath -m "$out")
mkdir -p "$out"/{dracut/modules.d/92uke-abl,empty-config,base,licenses}

host_arch=$(uname -m)
case "$host_arch" in
    aarch64|arm64)
        if [ -n "${CXX:-}" ]; then cxx=("$CXX"); else cxx=(g++); fi
        ;;
    *)
        if [ -n "${CXX:-}" ]; then
            cxx=("$CXX")
        elif command -v aarch64-linux-gnu-g++ >/dev/null 2>&1; then
            cxx=(aarch64-linux-gnu-g++)
        else
            cxx=(clang++ --target=aarch64-linux-gnu)
        fi
        ;;
esac

cp -a /usr/lib/dracut/. "$out/dracut/"
cp "$root/src/boot/dracut/"* "$out/dracut/modules.d/92uke-abl/"
chmod 755 "$out/dracut/modules.d/92uke-abl/module-setup.sh"

"${cxx[@]}" -std=c++17 -O2 -Wall -Wextra -Werror \
    -ffile-prefix-map="$root"=. \
    "$root/src/boot/boot-status.cpp" -o "$out/dracut/modules.d/92uke-abl/uke-boot-status"
"${cxx[@]}" -std=c++17 -O2 -Wall -Wextra -Werror \
    -ffile-prefix-map="$root"=. \
    "$root/src/boot/userdata-grow.cpp" -o "$out/dracut/modules.d/92uke-abl/uke-userdata-grow"

command_line=$(sed -n 's/^CONFIG_CMDLINE="\(.*\)"$/\1/p' "$root/packaging/native/native.config")
dracut_line=${command_line/root=PARTLABEL=linux /}
dracut_line=${dracut_line/rootfstype=ext4,f2fs,xfs,btrfs /}
dracut_line=${dracut_line/panic=0 /}

dracutbasedir="$out/dracut" dracut --conf /dev/null --confdir "$out/empty-config" \
    --tmpdir "$out" --no-hostonly --no-hostonly-cmdline --no-early-microcode \
    --no-kernel --gzip --add uke-abl --kernel-cmdline "$dracut_line" \
    --force-drivers 'qrtr_smd qcom_pd_mapper ufs_qcom phy_qcom_qmp_ufs qcom_battmgr dwc3_qcom phy_msm_snps_eusb2_uke repeater_qti_pmic_eusb2_uke i2c_qcom_geni gpi ktz8866' \
    --filesystems 'ext4 f2fs' \
    --omit 'network plymouth crypt systemd-cryptsetup syslog lvm mdraid btrfs i18n' \
    "$out/base.cpio.gz" "$release"

(cd "$out/base"; gzip -cd ../base.cpio.gz | cpio -idm --quiet --no-absolute-filenames)
find "$out/base/usr/lib/dracut" -name build-parameter.txt -type f -delete
printf 'dracut\nf2fs-tools\n' > "$out/owners.list"
printf '%s\n' "$release" > "$out/kernel-release"
printf 'Initramfs base complete: %s\n' "$out/base"
