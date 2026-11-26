#!/usr/bin/env bash
# Prepare a Linux 7.3.1 source tree with the Uke native source additions.
# This script is owned by simplify-kernel-repo; it does not call any external
# kernel build script.
set -Eeuo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
kernel=$(realpath "${1:?Pass the prepared Linux source tree}")
output="$kernel/native-generated"
mkdir -p "$output"

# Source-lock metadata consumed by the boot/display preparation helpers.
install -d "$kernel/senemos-adaptation"
jq '{version, patch_series, patches: [.patches[] | {path, sha256}]}' \
    "$repo/manifests/linux-7.3.1.json" > "$kernel/senemos-adaptation/source-lock.json"
awk '{print}' "$repo/patches/7.3.0/series" > "$kernel/senemos-applied-patches.txt"

# AOSC native profile defaults used by the Uke source prep helpers.
export UKE_USB_PROFILE
UKE_USB_PROFILE=$(cat "$repo/packaging/native/usb-profile")
export UKE_LLCC_PROFILE
UKE_LLCC_PROFILE=$(cat "$repo/packaging/native/llcc-profile")
export UKE_AUDIO_PROFILE
UKE_AUDIO_PROFILE=$(cat "$repo/packaging/native/audio-profile")

# Audio source additions are not part of the generic kernel patch series.
install -m644 "$repo/src/audio/uke-audio-card.c" "$kernel/sound/soc/qcom/uke-audio-card.c"
install -m644 "$repo/src/audio/uke-microphone-gain.h" "$kernel/sound/soc/qcom/uke-microphone-gain.h"
install -m644 "$repo/src/audio/uke-dp-eld.h" "$kernel/sound/soc/qcom/uke-dp-eld.h"

# Display providers must be staged before the framebuffer pin-state patch.
bash "$repo/src/display/prepare-source.sh" "$kernel"
git -C "$kernel" apply "$repo/patches/display/0065-msm-framebuffer-pin-state.patch"

# Audio-specific additions from the old native preparation sequence.
if [ "$UKE_AUDIO_PROFILE" = microphones ]; then
    for patch in 0053-q6apm-uke-mono-capture.patch         0054-audioreach-read-completion-v2-layout.patch         0055-lpass-tx-macro-multichannel-state.patch         0056-q6apm-uke-raw-microphone-channel-map.patch; do
        git -C "$kernel" apply "$repo/patches/boot/$patch"
    done
fi

# Boot, power, sensor, performance and input source preparation.
bash "$repo/src/boot/prepare-abl-source.sh" "$kernel" "$output"
bash "$repo/src/power/prepare-memlat.sh" "$kernel"
bash "$repo/src/sensors/prepare-source.sh" "$kernel"
bash "$repo/src/performance/prepare-source.sh" "$kernel"
bash "$repo/src/nfc/prepare-source.sh" "$kernel"
git -C "$kernel" apply "$repo/patches/input/0001-smp2p-lid-open-wake.patch"
bash "$repo/src/input/prepare-source.sh" "$kernel"
git -C "$kernel" apply "$repo/patches/boot/0010-qcom-flash-bounded-cleanup.patch"
git -C "$kernel" apply "$repo/patches/boot/0011-qcom-flash-torch-steps.patch"
bash "$repo/src/leds/prepare-source.sh" "$kernel"

# Remaining display and video source preparation.
for patch in \
    0066-msm-dpu-reservation-ownership.patch \
    0067-msm-kms-lifecycle-unwind.patch \
    0068-msm-scanout-retirement.patch \
    0069-o82-requested-vrr-floor.patch \
    0070-o82-adaptive-backlight.patch \
    0071-o82-panel-variants.patch; do
    git -C "$kernel" apply "$repo/patches/display/$patch"
done
bash "$repo/src/video/prepare-source.sh" "$kernel"
bash "$repo/src/display/prepare-native-abl-source.sh" "$kernel" "$output" auto

# Remaining old-kernel source patches.
for patch in 0025-cliffs-nsp-crypto-suppliers.patch     0026-cliffs-proxy-and-pas-stop-ownership.patch     0027-remoteproc-early-stop.patch     0028-cliffs-proxy-per-rail-ownership.patch     0033-uke-nfc-regulator-resource.patch     0044-uke-microphone-bob-supply.patch; do
    git -C "$kernel" apply "$repo/patches/boot/$patch"
done
if [ "$UKE_AUDIO_PROFILE" = hdmi-only ] || [ "$UKE_AUDIO_PROFILE" = speakers ] || [ "$UKE_AUDIO_PROFILE" = microphones ]; then
    git -C "$kernel" apply "$repo/patches/boot/0009-uke-displayport-dma-scope.patch"
    git -C "$kernel" apply "$repo/patches/display/0057-uke-displayport-eld-notification.patch"
fi

# Final native display resource preparation for the 7.3.1 source lock.
bash "$repo/src/display/prepare-o82-regdma.sh" "$kernel"

printf 'Uke native source preparation complete: %s\n' "$kernel"
