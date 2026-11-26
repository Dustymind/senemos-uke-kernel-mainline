# Source inputs

The simplify-kernel-repo build does not fetch DTS or driver files from a live
remote service during compilation.

## Upstream kernel archive

```text
https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz
https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.sign
```

The local copy is:

```text
source-cache/releases/linux-7.3.1.tar.xz
```

The manifest records the expected source SHA-256:

```text
manifests/linux-7.3.1.json: source_sha256
```

## Uke kernel branch

The Uke patch, source overlay, manifests and final config come from:

```text
https://github.com/Dustymind/senemos-uke-kernel-mainline.git
branch: simplify-kernel-repo
```

The local branch is the working source for this tree; use `git log -1` to
record the exact commit used for a build.

Files used from the branch:

```text
patches/7.3.0/      128-patch Uke series
src/                Uke native source and DTS/DTSO overlays
configs/arm64-uke.config
manifests/linux-7.3.1.json
packaging/native/   USB/LLCC/audio profile selectors
```

## DTS sources

The main board DTS is introduced by:

```text
patches/7.3.0/0007-uke-independent-dts.patch
```

It produces:

```text
arch/arm64/boot/dts/qcom/sm7675-xiaomi-uke.dts
```

The boot-only DTSO/DTSI files are local to this repository:

```text
src/boot/*.dtso
src/display/*.dtso
src/audio/*.dtsi
src/input/*.dtsi
```

MiCode kernel-devicetree and other vendor links in `docs/` are provenance
references; they are not fetched by the build.

## Fetched at build time

Nothing. `scripts/build-kernel.sh` uses the local source archive and the files
in this branch. `scripts/prepare-source.sh` only installs files already present
in `src/`, `patches/`, `manifests/` and `packaging/`.
