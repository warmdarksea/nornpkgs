# make references symlink target mtime, not symlink mtime. targets that are
# symlinks to store paths will always be built without this flag
MAKEFLAGS+=-L

DOMAIN=gensokyo.internal
HOST=$(TARGET).$(DOMAIN)

BUILD_DIR=build

#

TARGET=nonexistant
ISO_FLAVOR=nonexistant
REMOTE_STORE_PATH=/nonexistant
REMOTE_NIX_FLAGS=
INSTALL_PATH=/nonexistant

#

SUDO=pkexec
SUDO_FLAGS=

DTACH_FLAGS=-n

#

.PHONY: local_assert
local_assert:
	test $(shell hostname) == $(TARGET)

.PHONY: remote_assert
remote_assert:
	test $(shell hostname) != $(TARGET)

#

%: $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

#

# can't be bothered figuring out all of the dependencies, just build it again
# every time
.PHONY: $(BUILD_DIR)/sys-%.drv
$(BUILD_DIR)/sys-%.drv:
	nix build $(NIX_FLAGS) --dry-run --json .#nixosConfigurations.$*.config.system.build.toplevel | jq -r '.[].drvPath' | tail -n1 | xargs -I{} ln -sfn {} $@

.PHONY: $(BUILD_DIR)/sys-%
$(BUILD_DIR)/sys-%: flake.nix flake.lock
	nix build $(NIX_FLAGS) -o "$@" .#nixosConfigurations.$*.config.system.build.toplevel

$(BUILD_DIR)/img-%: flake.nix 	  	    \
			    flake.lock
	nix build $(NIX_FLAGS) -o "$@" .#images.$*

$(BUILD_DIR)/iso-%: flake.nix 	  	    \
				flake.lock
	nix build $(NIX_FLAGS) -o "$@" .#nixosConfigurations.iso-$*.config.system.build.isoImage

#

.PHONY: build_sys_closure
build_sys_closure: $(BUILD_DIR)/sys-$(TARGET)

.PHONY: build_img
build_img: $(BUILD_DIR)/img-$(TARGET)

.PHONY: build_iso_closure
build_iso: $(BUILD_DIR)/iso-$(ISO_FLAVOR)

# remote building
.PHONY: remote_build_sys_closure remote_build_reset remote_build_log remote_build_status remote_build_check remote_pull_sys_closure

.PHONY: $(BUILD_DIR)/remote-sys-%
$(BUILD_DIR)/remote-sys-%:
	nix build $(NIX_FLAGS) --dry-run --json .#nixosConfigurations.$*.config.system.build.toplevel | jq -r '.[].outputs.out' | tail -n1 | xargs -I{} ln -sfn {} $@

remote_build_sys_closure: $(BUILD_DIR)/sys-$(TARGET).drv
	@echo "Derivation path: $(shell realpath $<)"
	nix copy "$(shell realpath $<)" --to "ssh://root@$(HOST)"
	ssh "root@$(HOST)" -- systemd-run --uid=0 --property=StandardOutput=journal --property=StandardError=journal --service-type=oneshot --no-block --unit=nixbuild-$(TARGET) -- nix-store --realise -k "$(shell realpath $<)"

remote_build_reset:
	ssh "root@$(HOST)" 'systemctl reset-failed nixbuild-$(TARGET)'

remote_build_log:
	ssh "root@$(HOST)" 'journalctl -u nixbuild-$(TARGET) -f'

remote_build_status:
	ssh "root@$(HOST)" 'systemctl status nixbuild-$(TARGET)'

remote_build_check: $(BUILD_DIR)/remote-sys-$(TARGET)
	ssh "root@$(HOST)" -- ls -d "$(shell realpath $<)"

remote_pull_sys_closure: $(BUILD_DIR)/remote-sys-$(TARGET)
	@echo "Pulling $(shell realpath $<) from $(HOST)"
	nix copy --no-check-sigs --from "ssh://root@$(HOST)" "$(shell realpath $<)"
	ln -sfn $(shell realpath $<) $(BUILD_DIR)/sys-$(TARGET)

#

# remote package building (arbitrary flake refs, not system closures)
#
# usage:
#   make remote_build_pkg PKG=nixpkgs#leanPackages.mathlib HOST=magic.gensokyo.internal
#   make remote_build_pkg_log    PKG=... HOST=...
#   make remote_build_pkg_status PKG=... HOST=...
#   make remote_pull_pkg         PKG=... HOST=...

PKG ?=
# PKG_NAME is derived from PKG for use in unit/file names. override if ugly.
PKG_NAME ?= $(shell echo '$(PKG)' | sed 's/[^a-zA-Z0-9]/-/g')

.PHONY: remote_build_pkg remote_build_pkg_log remote_build_pkg_status \
        remote_build_pkg_reset remote_build_pkg_check remote_pull_pkg

# always re-resolve the .drv (flake.lock or source may have changed)
.PHONY: $(BUILD_DIR)/pkg-$(PKG_NAME).drv
$(BUILD_DIR)/pkg-$(PKG_NAME).drv:
	@test -n "$(PKG)" || { echo "PKG must be set, e.g. PKG=nixpkgs#leanPackages.mathlib"; exit 1; }
	nix build $(NIX_FLAGS) --dry-run --json '$(PKG)' | jq -r '.[].drvPath' | tail -n1 | xargs -I{} ln -sfn {} $@

.PHONY: $(BUILD_DIR)/remote-pkg-$(PKG_NAME)
$(BUILD_DIR)/remote-pkg-$(PKG_NAME):
	@test -n "$(PKG)" || { echo "PKG must be set"; exit 1; }
	nix build $(NIX_FLAGS) --dry-run --json '$(PKG)' | jq -r '.[].outputs.out' | tail -n1 | xargs -I{} ln -sfn {} $@

remote_build_pkg: $(BUILD_DIR)/pkg-$(PKG_NAME).drv
	@echo "Building $(PKG)"
	@echo "  drv:  $(shell realpath $<)"
	@echo "  on:   $(HOST)"
	nix copy "$(shell realpath $<)" --to "ssh://root@$(HOST)"
	ssh "root@$(HOST)" -- systemd-run \
	  --uid=0 \
	  --property=StandardOutput=journal \
	  --property=StandardError=journal \
	  --service-type=oneshot \
	  --no-block \
	  --unit=nixbuild-pkg-$(PKG_NAME) \
	  -- nix-store --realise -k "$(shell realpath $<)"
	@echo
	@echo "started. monitor with:"
	@echo "  make remote_build_pkg_log PKG='$(PKG)' HOST=$(HOST)"

remote_build_pkg_log:
	ssh "root@$(HOST)" 'journalctl -u nixbuild-pkg-$(PKG_NAME) -f'

remote_build_pkg_status:
	ssh "root@$(HOST)" 'systemctl status nixbuild-pkg-$(PKG_NAME)'

remote_build_pkg_reset:
	ssh "root@$(HOST)" 'systemctl reset-failed nixbuild-pkg-$(PKG_NAME)'

remote_build_pkg_check: $(BUILD_DIR)/remote-pkg-$(PKG_NAME)
	ssh "root@$(HOST)" -- ls -d "$(shell realpath $<)"

remote_pull_pkg: $(BUILD_DIR)/remote-pkg-$(PKG_NAME)
	@echo "pulling $(shell realpath $<) from $(HOST)"
	nix copy --no-check-sigs --from "ssh://root@$(HOST)" "$(shell realpath $<)"
	ln -sfn $(shell realpath $<) $(BUILD_DIR)/pkg-$(PKG_NAME)

#

.PHONY: push_closure
push_closure: $(BUILD_DIR)/sys-$(TARGET)
	nix copy --to "ssh://root@$(HOST)" "$<"

# ah, memories
#
# REMOTE_STORE_PATH should be missing the final /nix, so e.g. /mnt/nix should be
# /mnt
.PHONY: push_closure_to
push_closure_to: $(BUILD_DIR)/sys-$(TARGET)
	nix copy "$<" --to "ssh://root@$(HOST)?remote-store=$(REMOTE_STORE_PATH)"

#

.PHONY: set_local_active_closure
set_local_active_closure: $(BUILD_DIR)/sys-$(TARGET)
	$(SUDO) $(SUDO_FLAGS) bash -c 'nix-env --profile /nix/var/nix/profiles/system --set $(shell realpath "$<") && /nix/var/nix/profiles/system/bin/switch-to-configuration switch'

.PHONY: set_local_boot_closure
set_local_boot_closure: $(BUILD_DIR)/sys-$(TARGET)
	$(SUDO) $(SUDO_FLAGS) bash -c 'nix-env --profile /nix/var/nix/profiles/system --set $(shell realpath "$<") && /nix/var/nix/profiles/system/bin/switch-to-configuration boot'

.PHONY: set_remote_active_closure
set_remote_active_closure: $(BUILD_DIR)/sys-$(TARGET)
	ssh "root@$(HOST)" -- nix-env --profile /nix/var/nix/profiles/system --set "$(shell realpath $<)"
	ssh "root@$(HOST)" -- /nix/var/nix/profiles/system/bin/switch-to-configuration switch

.PHONY: set_remote_boot_closure
set_remote_boot_closure: $(BUILD_DIR)/sys-$(TARGET)
	ssh "root@$(HOST)" -- nix-env --profile /nix/var/nix/profiles/system --set "$(shell realpath $<)"
	ssh "root@$(HOST)" -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot

#

.PHONY: deploy_local_active_closure
deploy_local_active_closure:	   \
	local_assert		   \
	$(BUILD_DIR)/sys-$(TARGET) \
	set_local_active_closure

.PHONY: deploy_local_boot_closure
deploy_local_boot_closure:	   \
	local_assert		   \
	$(BUILD_DIR)/sys-$(TARGET) \
	set_local_boot_closure

.PHONY: deploy_remote_active_closure
deploy_remote_active_closure:	   \
	remote_assert		   \
	$(BUILD_DIR)/sys-$(TARGET) \
	push_closure		   \
	set_remote_active_closure

.PHONY: deploy_remote_boot_closure
deploy_remote_boot_closure:	   \
	remote_assert		   \
	$(BUILD_DIR)/sys-$(TARGET) \
	push_closure		   \
	set_remote_boot_closure

# gcs all but boot/current closures (that's the 'a') then deploys the next
# closure (the 'b' closure). furnace can hold about 4 generations at once in its
# EFI partition, so it's useful for constrained systems
.PHONY: remote_gc_ab
remote_gc_ab: remote_assert
	ssh "root@$(HOST)" -- bash -s < bin/nix-gc-ab.sh
	ssh "root@$(HOST)" -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot

.PHONY: deploy_remote_ab_closure
deploy_remote_ab_closure:          \
	remote_assert              \
	$(BUILD_DIR)/sys-$TARGET   \
	remote_gc_ab               \
	deploy_remote_boot_closure

.PHONY: install_closure_to_path
install_closure_to_path: $(BUILD_DIR)/sys-$(TARGET)
	$(SUDO) $(SUDO_FLAGS) nixos-install --no-root-password --root "$(INSTALL_PATH)" --system "$<"

# make remote_install_closure_to_path SSH_FLAGS="-i ~/.ssh/id_satori -o StrictHostKeyChecking=false" HOST=furnace REMOTE_STORE_PATH=/mnt INSTALL_PATH=/mnt TARGET=furnace
.PHONY: remote_install_closure_to_path
remote_install_closure_to_path: $(BUILD_DIR)/sys-$(TARGET) \
	remote_assert		   \
	$(BUILD_DIR)/sys-$(TARGET) \
	push_closure_to		   
	ssh $(SSH_FLAGS) "root@$(HOST)" -- nixos-install --no-root-password --root "$(INSTALL_PATH)" --system "$(shell readlink $<)"

#

update_hell:
	incus exec basement -- /bin/bash -c -- 'pacman -Syu --noconfirm'

#

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: gc gc_local gc_remote
gc: gc_local
gc_local:
	$(SUDO) $(SUDO_FLAGS) nix-collect-garbage -d
gc_remote: remote_assert
	ssh "root@$(HOST)" -- nix-collect-garbage -d

# delete references to all generations in between the boot generation and the
# current generation, exclusive (so skip the boot and current, obviously)
# then update the boot menu
.PHONY: cleanup_system_generations
cleanup_system_generations:
	bash bin/nix-cleanup-generations.sh
	$(SUDO) $(SUDO_FLAGS) /nix/var/nix/profiles/system/bin/switch-to-configuration boot

#

.PHONY: run_vm_closure
run_vm_closure: \
	build_vm_closure
	QEMU_NET_OPTS="hostfwd=tcp::2221-:22,hostfwd=tcp::8080-:80" ../build/vm-closure-$(TARGET)/bin/run-nixos-vm

.PHONY: query_config
query_config:
	nix-instantiate --eval sys/$(TARGET).nix -A $(OPTION)

.PHONY: why_depends_sys
why_depends_sys:
	nix why-depends -I nixos-config=sys/$(TARGET).nix $(NIX_FLAGS) --attr system sys/$(TARGET).nix

#

