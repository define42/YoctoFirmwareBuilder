# Makefile
#
# Full Yocto + RAUC build wrapper for generic x86-64
#
# Features:
# - clones poky if missing
# - clones meta-rauc if missing
# - creates a custom layer
# - generates image and bundle recipes
# - builds .wic and .raucb
# - boots the generated genericx86-64 .wic directly in QEMU
#
# Usage:
#   make all
#   make qemu
#   make outputs
#
# Optional overrides:
#   make MACHINE=genericx86-64 all

SHELL := /bin/bash

# ---------- Repos ----------
POKY_REPO        ?= https://github.com/yoctoproject/poky.git
POKY_BRANCH      ?= scarthgap
META_RAUC_REPO   ?= https://github.com/rauc/meta-rauc.git
META_RAUC_BRANCH ?= scarthgap

# ---------- Paths ----------
YOCTO_DIR        ?= poky
BUILD_DIR        ?= build
META_RAUC_DIR    ?= meta-rauc

LAYER_NAME       ?= meta-myproduct
LAYER_PATH       ?= $(CURDIR)/$(LAYER_NAME)

# ---------- Build settings ----------
MACHINE          ?= genericx86-64
IMAGE_NAME       ?= core-image-minimal
BUNDLE_NAME      ?= myproduct-bundle
COMPATIBLE_NAME  ?= myproduct-x86

BB_THREADS       ?= 4
PARALLEL_MAKE    ?= -j4

# ---------- RAUC signing ----------
RAUC_CERT_FILE   ?= $(abspath keys/rauc.cert.pem)
RAUC_KEY_FILE    ?= $(abspath keys/rauc.key.pem)

# ---------- QEMU settings ----------
QEMU_BIN         ?= qemu-system-x86_64
QEMU_ACCEL       ?= kvm:tcg
QEMU_CPU         ?= host
QEMU_SMP         ?= 2
QEMU_MEM         ?= 2048
QEMU_NET_MODEL   ?= e1000
QEMU_DRIVE_IF    ?= virtio

# ---------- Internal helpers ----------
YOCTO_ENV        = source $(YOCTO_DIR)/oe-init-build-env $(BUILD_DIR)
DEPLOY_DIR       = $(BUILD_DIR)/tmp/deploy/images/$(MACHINE)

.PHONY: help deps clone-poky clone-meta-rauc init layer add-layer configure \
        recipes keys image bundle all qemu outputs clean distclean clobber \
        superclean showvars

help:
	@echo "Targets:"
	@echo "  make deps        - clone poky/meta-rauc if missing"
	@echo "  make init        - initialize Yocto build directory"
	@echo "  make layer       - create custom layer if missing"
	@echo "  make add-layer   - add custom layer and meta-rauc"
	@echo "  make configure   - configure local.conf"
	@echo "  make recipes     - generate image + bundle recipes"
	@echo "  make keys        - create demo RAUC signing keys"
	@echo "  make image       - build .wic image"
	@echo "  make bundle      - build .raucb bundle"
	@echo "  make all         - build both"
	@echo "  make qemu        - boot the generated genericx86-64 .wic"
	@echo "  make outputs     - show generated output files"
	@echo "  make clean       - clean BitBake outputs"
	@echo "  make distclean   - remove build dir, layer, keys"
	@echo "  make clobber     - remove build dir, layer, keys, poky, meta-rauc"
	@echo "  make superclean  - alias for clobber"
	@echo "  make showvars    - show current settings"

showvars:
	@echo "POKY_REPO        = $(POKY_REPO)"
	@echo "POKY_BRANCH      = $(POKY_BRANCH)"
	@echo "META_RAUC_REPO   = $(META_RAUC_REPO)"
	@echo "META_RAUC_BRANCH = $(META_RAUC_BRANCH)"
	@echo "YOCTO_DIR        = $(YOCTO_DIR)"
	@echo "META_RAUC_DIR    = $(META_RAUC_DIR)"
	@echo "BUILD_DIR        = $(BUILD_DIR)"
	@echo "LAYER_NAME       = $(LAYER_NAME)"
	@echo "LAYER_PATH       = $(LAYER_PATH)"
	@echo "MACHINE          = $(MACHINE)"
	@echo "IMAGE_NAME       = $(IMAGE_NAME)"
	@echo "BUNDLE_NAME      = $(BUNDLE_NAME)"
	@echo "COMPATIBLE_NAME  = $(COMPATIBLE_NAME)"
	@echo "DEPLOY_DIR       = $(DEPLOY_DIR)"
	@echo "RAUC_CERT_FILE   = $(RAUC_CERT_FILE)"
	@echo "RAUC_KEY_FILE    = $(RAUC_KEY_FILE)"
	@echo "QEMU_BIN         = $(QEMU_BIN)"
	@echo "QEMU_ACCEL       = $(QEMU_ACCEL)"
	@echo "QEMU_CPU         = $(QEMU_CPU)"
	@echo "QEMU_SMP         = $(QEMU_SMP)"
	@echo "QEMU_MEM         = $(QEMU_MEM)"
	@echo "QEMU_NET_MODEL   = $(QEMU_NET_MODEL)"
	@echo "QEMU_DRIVE_IF    = $(QEMU_DRIVE_IF)"

deps: clone-poky clone-meta-rauc

clone-poky:
	@if [ ! -d "$(YOCTO_DIR)" ]; then \
		echo "Cloning poky into $(YOCTO_DIR)"; \
		git clone --branch "$(POKY_BRANCH)" "$(POKY_REPO)" "$(YOCTO_DIR)"; \
	else \
		echo "Found $(YOCTO_DIR)"; \
	fi

clone-meta-rauc:
	@if [ ! -d "$(META_RAUC_DIR)" ]; then \
		echo "Cloning meta-rauc into $(META_RAUC_DIR)"; \
		git clone --branch "$(META_RAUC_BRANCH)" "$(META_RAUC_REPO)" "$(META_RAUC_DIR)"; \
	else \
		echo "Found $(META_RAUC_DIR)"; \
	fi

init: deps
	@bash -lc '$(YOCTO_ENV) >/dev/null && echo "Initialized $(BUILD_DIR)"'

layer: init
	@bash -lc '\
		$(YOCTO_ENV) >/dev/null; \
		if [ ! -d "$(LAYER_PATH)" ]; then \
			bitbake-layers create-layer "$(LAYER_PATH)"; \
		else \
			echo "Layer already exists: $(LAYER_PATH)"; \
		fi \
	'

add-layer: layer
	@bash -lc '\
		$(YOCTO_ENV) >/dev/null; \
		bitbake-layers add-layer "$(abspath $(META_RAUC_DIR))" || true; \
		bitbake-layers add-layer "$(abspath $(LAYER_PATH))" || true; \
		bitbake-layers show-layers \
	'

configure: add-layer
	@bash -lc '\
		set -e; \
		$(YOCTO_ENV) >/dev/null; \
		conf="conf/local.conf"; \
		printf "%s\n" \
			"import sys, re, pathlib" \
			"conf = pathlib.Path(sys.argv[1])" \
			"machine = sys.argv[2]" \
			"bb_threads = sys.argv[3]" \
			"parallel_make = sys.argv[4]" \
			"cert_file = sys.argv[5]" \
			"key_file = sys.argv[6]" \
			"lines = conf.read_text().splitlines()" \
			"def remove_assignments(name):" \
			"    global lines" \
			"    pattern = re.compile(rf\"^\\s*{re.escape(name)}\\s*(?:\\?\\?=|\\?=|\\+=|=).*$$\")" \
			"    lines = [line for line in lines if not pattern.match(line)]" \
			"def setvar(name, value):" \
			"    remove_assignments(name)" \
			"    lines.append(f\"{name} = \\\"{value}\\\"\")" \
			"def has_distro_feature(feature):" \
			"    pattern = re.compile(r\"^\\s*DISTRO_FEATURES(?::[^\\s=]+)?\\s*(?:\\?\\?=|\\?=|\\+=|=).*$$\")" \
			"    return any(pattern.match(line) and re.search(rf\"\\b{re.escape(feature)}\\b\", line) for line in lines)" \
			"setvar(\"MACHINE\", machine)" \
			"setvar(\"BB_NUMBER_THREADS\", bb_threads)" \
			"setvar(\"PARALLEL_MAKE\", parallel_make)" \
			"setvar(\"IMAGE_FSTYPES\", \"wic wic.bmap ext4\")" \
			"setvar(\"RAUC_KEY_FILE\", key_file)" \
			"setvar(\"RAUC_CERT_FILE\", cert_file)" \
			"if not has_distro_feature(\"rauc\"):" \
			"    lines.append(\"DISTRO_FEATURES:append = \\\" rauc\\\"\")" \
			"conf.write_text(\"\\n\".join(lines) + \"\\n\")" \
		| python3 - "$$conf" "$(MACHINE)" "$(BB_THREADS)" "$(PARALLEL_MAKE)" "$(RAUC_CERT_FILE)" "$(RAUC_KEY_FILE)"; \
		echo "Configured $$conf"; \
	'

recipes: configure keys
	@mkdir -p $(LAYER_PATH)/recipes-core/images
	@mkdir -p $(LAYER_PATH)/recipes-core/bundles
	@mkdir -p $(LAYER_PATH)/recipes-core/rauc/files
	@rm -f $(LAYER_PATH)/recipes-core/images/$(IMAGE_NAME).bb
	@rm -f $(LAYER_PATH)/recipes-core/images/myproduct-image.bb
	@printf '%s\n' \
		'IMAGE_INSTALL:append = " rauc rauc-conf"' \
		'IMAGE_FEATURES:remove = "ssh-server-openssh"' \
		> $(LAYER_PATH)/recipes-core/images/$(IMAGE_NAME).bbappend

	@printf '%s\n' \
		'FILESEXTRAPATHS:prepend := "$${THISDIR}/files:"' \
		> $(LAYER_PATH)/recipes-core/rauc/rauc-conf.bbappend

	@install -m 0644 "$(RAUC_CERT_FILE)" "$(LAYER_PATH)/recipes-core/rauc/files/ca.cert.pem"

	@printf '%s\n' \
		'DESCRIPTION = "RAUC update bundle for myproduct x86"' \
		'LICENSE = "MIT"' \
		'' \
		'inherit bundle' \
		'' \
		'RAUC_BUNDLE_COMPATIBLE = "$(COMPATIBLE_NAME)"' \
		'RAUC_BUNDLE_FORMAT = "verity"' \
		'RAUC_BUNDLE_SLOTS = "rootfs"' \
		'' \
		'RAUC_SLOT_rootfs = "$(IMAGE_NAME)"' \
		'RAUC_SLOT_rootfs[fstype] = "ext4"' \
		> $(LAYER_PATH)/recipes-core/bundles/$(BUNDLE_NAME).bb

	@printf '%s\n' \
		'[system]' \
		'compatible=$(COMPATIBLE_NAME)' \
		'bootloader=grub' \
		'' \
		'[keyring]' \
		'path=/etc/rauc/ca.cert.pem' \
		'' \
		'[slot.rootfs.0]' \
		'device=/dev/sda2' \
		'type=ext4' \
		'bootname=A' \
		'' \
		'[slot.rootfs.1]' \
		'device=/dev/sda3' \
		'type=ext4' \
		'bootname=B' \
		> $(LAYER_PATH)/recipes-core/rauc/files/system.conf

	@echo "Generated recipes in $(LAYER_PATH)"

keys:
	@mkdir -p keys
	@if [ ! -f "$(RAUC_KEY_FILE)" ] || [ ! -f "$(RAUC_CERT_FILE)" ]; then \
		echo "Creating demo RAUC signing keypair"; \
		openssl req -x509 -newkey rsa:4096 \
			-keyout "$(RAUC_KEY_FILE)" \
			-out "$(RAUC_CERT_FILE)" \
			-sha256 -days 3650 -nodes \
			-subj "/CN=$(COMPATIBLE_NAME) RAUC Demo/" >/dev/null 2>&1; \
	else \
		echo "Found existing RAUC keys"; \
	fi

image: recipes
	@bash -lc '$(YOCTO_ENV) >/dev/null && bitbake $(IMAGE_NAME)'

bundle: image
	@bash -lc '$(YOCTO_ENV) >/dev/null && bitbake $(BUNDLE_NAME)'

all: image bundle outputs

qemu: image
	@bash -lc '\
		WIC_FILE=$$(find "$(DEPLOY_DIR)" -maxdepth 1 -type f -name "*$(IMAGE_NAME)*.rootfs.wic" | sort | tail -n1); \
		if [ -z "$$WIC_FILE" ]; then \
			echo "ERROR: No WIC file found in $(DEPLOY_DIR)"; \
			exit 1; \
		fi; \
		if ! command -v "$(QEMU_BIN)" >/dev/null 2>&1; then \
			echo "ERROR: $(QEMU_BIN) not found"; \
			exit 1; \
		fi; \
		echo "Booting $$WIC_FILE with $(QEMU_BIN)"; \
		"$(QEMU_BIN)" \
			-machine accel=$(QEMU_ACCEL) \
			-cpu $(QEMU_CPU) \
			-smp $(QEMU_SMP) \
			-m $(QEMU_MEM) \
			-drive file="$$WIC_FILE",format=raw,if=$(QEMU_DRIVE_IF) \
			-net nic,model=$(QEMU_NET_MODEL) \
			-net user \
			-serial mon:stdio \
			-boot c \
	'

outputs:
	@echo
	@echo "Output directory: $(DEPLOY_DIR)"
	@find $(DEPLOY_DIR) -maxdepth 1 \( -name "*.wic" -o -name "*.wic.bmap" -o -name "*.raucb" \) 2>/dev/null | sort || true

clean: init
	@bash -lc '\
		$(YOCTO_ENV) >/dev/null; \
		bitbake -c clean $(IMAGE_NAME) || true; \
		bitbake -c clean $(BUNDLE_NAME) || true; \
	'

distclean:
	@rm -rf "$(BUILD_DIR)" "$(LAYER_PATH)" keys
	@echo "Removed build dir, generated layer, and keys"
	@echo "Kept $(YOCTO_DIR) and $(META_RAUC_DIR)"

clobber: distclean
	@rm -rf "$(YOCTO_DIR)" "$(META_RAUC_DIR)"
	@echo "Removed $(YOCTO_DIR) and $(META_RAUC_DIR)"

superclean: clobber
