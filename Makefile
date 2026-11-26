SHELL := /bin/bash
.SHELLFLAGS := -Eeuo pipefail -c
.ONESHELL:

version := 7.3.1
patch_series := 7.3.0
patch_count := 128

KERNEL_SOURCE ?= build/kernel/source
KERNEL_OUT ?= build/kernel
BOOT_OUT ?= build/boot
USB_PROFILE ?= typec-v1
PARTITION_NAME ?= userdata
STOCK ?=
AVBTOOL ?=

.PHONY: build-kernel build-boot-img
build-kernel:
	bash scripts/build-kernel.sh --out "$(KERNEL_OUT)"

build-boot-img:
	bash scripts/build-boot-img.sh --kernel "$(KERNEL_SOURCE)" --out "$(BOOT_OUT)" --usb-profile "$(USB_PROFILE)" --partition-name "$(PARTITION_NAME)" --stock "$(STOCK)" --avbtool "$(AVBTOOL)"
