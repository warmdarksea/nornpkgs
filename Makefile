# make references symlink target mtime, not symlink mtime. targets that are
# symlinks to store paths will always be built without this flag
MAKEFLAGS+=-L

DOMAIN=gensokyo.internal
HOST=$(TARGET).$(DOMAIN)

BUILD_DIR=build

#

include Makefile.private
include Makefile.littledevil

# point at a checkout of gensokyo-private's private branch to build with the
# real private config instead of the public stub, e.g.
#   make build_sys_closure TARGET=hell \
#     PRIVATE_FLAKE='git+file:///home/clownpiece/src/gensokyo-private?ref=private'
PRIVATE_FLAKE?=
override NIX_FLAGS+=$(if $(PRIVATE_FLAKE),--override-input gensokyo-private '$(PRIVATE_FLAKE)' --no-write-lock-file)

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

# order-only-ish "always run me" marker for pattern targets that `.PHONY` can't
# cover (`.PHONY` does not expand `%`).
.PHONY: FORCE
FORCE:

#

# can't be bothered figuring out all of the dependencies, just build it again
# every time
.PHONY: $(BUILD_DIR)/sys-%.drv
$(BUILD_DIR)/sys-%.drv:
	nix build $(NIX_FLAGS) --dry-run --json .#nixosConfigurations.$*.config.system.build.toplevel | jq -r '.[].drvPath' | tail -n1 | xargs -I{} ln -sfn {} $@

.PHONY: $(BUILD_DIR)/sys-%
$(BUILD_DIR)/sys-%: flake.nix flake.lock
	nix build $(NIX_FLAGS) -o "$@" .#nixosConfigurations.$*.config.system.build.toplevel

$(BUILD_DIR)/img-%:
	nix build $(NIX_FLAGS) -o "$@" .#images.$*

$(BUILD_DIR)/iso-%:
	nix build $(NIX_FLAGS) -o "$@" .#nixosConfigurations.iso-$*.config.system.build.isoImage

#

.PHONY: build_sys_closure
build_sys_closure: $(BUILD_DIR)/sys-$(TARGET)

.PHONY: build_img
build_img: $(BUILD_DIR)/img-$(TARGET)

.PHONY: build_iso_closure
build_iso: $(BUILD_DIR)/iso-$(ISO_FLAVOR)

# CI checks against the public inputs plus gensokyo-private's `ci` stub, from
# a git-free copy of the working tree under $(BUILD_DIR)/ci-tree. The copy
# matters inside the Claude Code action: its sandbox masks .git/config (the
# GitHub token lives there), and nix's libgit2 then cannot open the checkout
# at all ("could not find repository", error class 6), while a `path:` flake
# never looks at git. Uncommitted edits are included, build/ and .git are not.
#   make ci_check TARGET=base     # build the toplevel (base: minutes, cache hits)
#   make ci_eval TARGET=hell      # evaluate only (desktops are tens of GB to build)
CI_NIX_FLAGS=--impure --no-write-lock-file --override-input gensokyo-private github:warmdarksea/gensokyo-private/ci
CI_TREE=$(BUILD_DIR)/ci-tree

.PHONY: ci_tree ci_check ci_eval
ci_tree: | $(BUILD_DIR)
	rm -rf $(CI_TREE) && mkdir -p $(CI_TREE)
	# the tracked tree plus untracked unignored files, copied one by one after
	# a real stat: the Claude Code sandbox masks dotfiles in the checkout root
	# with device nodes, which tar cannot recreate ("Cannot mknod") and which
	# find -type f does not see through (it trusts the directory entry)
	git ls-files -z --cached --others --exclude-standard -- . ':!secret' \
	  | xargs -0 sh -c 'for f; do [ -f "$$f" ] || continue; cp --parents "$$f" "$$0" || exit 1; done' $(CI_TREE)

ci_check: ci_tree
	nix build -L --no-link $(CI_NIX_FLAGS) "path:$(CURDIR)/$(CI_TREE)#nixosConfigurations.$(TARGET).config.system.build.toplevel"

ci_eval: ci_tree
	nix eval $(CI_NIX_FLAGS) "path:$(CURDIR)/$(CI_TREE)#nixosConfigurations.$(TARGET).config.system.build.toplevel.drvPath"

# any other target against the same copy and inputs: make ci_test_nix_check
ci_%: ci_tree
	$(MAKE) $* FLAKE=path:$(CURDIR)/$(CI_TREE) NIX_FLAGS="$(NIX_FLAGS) $(CI_NIX_FLAGS)"

#
# testing
#
# every target goes through $(FLAKE); `make ci_<target>` points it at the ci copy
#
#   make test               everything below
#   make test_nix_lint      parse every .nix file (no evaluation)
#   make test_tf            tofu validate (no credentials)
#   make test_nix_check     every flake output to a .drv, nothing built
#   make test_vm            boot the hosts of NIX_HOSTS_<arch> in VMs (checks.*.boot-*)
#   make test_templates     init, build, run and test NIX_TEMPLATES_<arch>
#   make run_vm TARGET=x    interactive test driver for one system
#
# the authenticated tofu plan against the real state is plan_oci_live
# (Makefile.littledevil), not a test

# what `make test` boots and builds on a host of each arch; a hosted ci runner
# has ~14 GB of disk, so only the small closures until the rest are trimmed
NIX_HOSTS_AMD64=base
NIX_HOSTS_AARCH64=littledevil
NIX_TEMPLATES_AMD64=py-hello rust-hello lean4-hello
NIX_TEMPLATES_AARCH64=

FLAKE?=.
# the same flake as an absolute ref, for recipes that cd elsewhere
FLAKE_ABS=$(if $(filter .,$(FLAKE)),git+file://$(CURDIR),$(FLAKE))
# the ci and public stubs lack the hosts' unfree allowances; only read under --impure
export NIXPKGS_ALLOW_UNFREE?=1

.PHONY: test test_nix_lint test_tf test_nix_check test_vm test_templates run_vm

test: test_nix_lint test_tf test_nix_check test_vm test_templates

NIX_FILES=$(shell git ls-files '*.nix')

test_nix_lint:
	@for f in $(NIX_FILES); do nix-instantiate --parse "$$f" > /dev/null || exit 1; done
	@echo "test_nix_lint: $(words $(NIX_FILES)) files parse"

# tofu validate: no registry (the flake's tofu carries the providers), no
# credentials, no state
TOFU=nix shell $(NIX_FLAGS) $(FLAKE)\#tofu --command tofu

test_tf:
	$(TOFU) -chdir=tf init -backend=false -input=false > /dev/null
	$(TOFU) -chdir=tf validate

# nixosConfigurations, checks (all systems), packages, devShells and
# templates, evaluated and instantiated into the local store; nothing built,
# so nothing lands in a binary cache. the littledevil.* outputs are not
# standard flake outputs and are not covered yet.
test_nix_check:
	nix flake check --no-build --all-systems $(NIX_FLAGS) $(FLAKE)

# the VM boot tests (checks.<system>.boot-*) of the hosts in NIX_HOSTS_<arch>
# for this host's arch, or VM_TARGETS="base hell". they need kvm. `nix flake
# check` without --no-build would build every check of this system at once,
# the desktop closures included; this one picks.
NIX_SYSTEM=$(shell nix eval --impure --raw --expr builtins.currentSystem)
ARCH=$(patsubst x86_64,AMD64,$(patsubst aarch64,AARCH64,$(NIX_SYSTEM:-linux=)))
VM_TARGETS?=$(NIX_HOSTS_$(ARCH))
test_vm:
	for t in $(VM_TARGETS); do \
	  echo "== boot-$$t"; nix build -L --no-link $(NIX_FLAGS) "$(FLAKE)#checks.$(NIX_SYSTEM).boot-$$t" || exit 1; \
	done

# the same VM, interactively: start_all(), machine.shell_interact(), ...
run_vm: $(BUILD_DIR)/vm-$(TARGET)
	$</bin/nixos-test-driver

$(BUILD_DIR)/vm-%: FORCE | $(BUILD_DIR)
	nix build $(NIX_FLAGS) -o "$@" "$(FLAKE)#checks.$(NIX_SYSTEM).boot-$*.driverInteractive"

# the templates, each copied under build/template-<name> as a git repo of its
# own (nix would otherwise see an ignored subdirectory of this checkout) and
# built, run and tested against this tree's nornpkgs: NIX_TEMPLATES_<arch>, or
# TEMPLATES=llm-hello
TEMPLATES?=$(NIX_TEMPLATES_$(ARCH))

test_templates: $(foreach t,$(TEMPLATES),test_template_$(t))

# MAKEOVERRIDES= keeps the ci_% wrapper's FLAKE=/NIX_FLAGS= out of the template's make
test_template_%: MAKEOVERRIDES=
test_template_%: FORCE | $(BUILD_DIR)
	rm -rf $(BUILD_DIR)/template-$* && mkdir -p $(BUILD_DIR)/template-$*
	cp -r template/$*/. $(BUILD_DIR)/template-$*
	cd $(BUILD_DIR)/template-$* && git init -q && git add -A
	$(MAKE) -C $(BUILD_DIR)/template-$* build run test NORNPKGS=$(FLAKE_ABS)

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

.PHONY: remote_pull_valid_inputs

remote_pull_valid_inputs: $(BUILD_DIR)/sys-$(TARGET).drv
	@echo "Pulling valid build-graph outputs of $(shell realpath $<) from $(HOST)"
	nix-store -qR "$(shell realpath $<)" | grep '\.drv$$' | xargs nix-store -q --outputs | sort -u > $(BUILD_DIR)/remote-wanted-$(TARGET)
	ssh "root@$(HOST)" -- xargs -r nix-store --check-validity --print-invalid < $(BUILD_DIR)/remote-wanted-$(TARGET) | sort -u > $(BUILD_DIR)/remote-missing-$(TARGET)
	comm -23 $(BUILD_DIR)/remote-wanted-$(TARGET) $(BUILD_DIR)/remote-missing-$(TARGET) > $(BUILD_DIR)/remote-have-$(TARGET)
	@echo "$$(wc -l < $(BUILD_DIR)/remote-have-$(TARGET)) / $$(wc -l < $(BUILD_DIR)/remote-wanted-$(TARGET)) outputs valid on $(HOST)"
	xargs -r nix copy --no-check-sigs -s --from "ssh://root@$(HOST)" < $(BUILD_DIR)/remote-have-$(TARGET)

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

.PHONY: query_config
query_config:
	nix eval $(NIX_FLAGS) "$(FLAKE)#nixosConfigurations.$(TARGET).config.$(OPTION)"

#

# NanoKVM UEFI trampoline artifacts.
# Build the unsigned trampoline .efi from the pinned uefi_trampoline source (same
# rev as flake.nix's uefiTrampolineSrc), Secure Boot-sign it when keys are given,
# and wrap it in a small hybrid ISO for `nanokvmctl boot`. Keys never live here:
#
#   make trampolines SB_KEY=~/sb/db/db.key SB_CERT=~/sb/db/db.pem
#   make build/uefi-trampoline-0002-nixos.iso SB_KEY=... SB_CERT=...
#   make build/uefi-trampoline-0007-fedora.iso SB_KEY=... SB_CERT=...   # any Boot#### id
#
# Omit SB_KEY/SB_CERT for an unsigned ISO (Secure Boot off / testing).

ESP_MB  ?= 4
SB_KEY  ?=
SB_CERT ?=

# single source of truth for the trampoline pin is flake.nix's uefiTrampolineSrc
TRAMP_URL := $(shell sed -n '/uefiTrampolineSrc = builtins.fetchGit/,/};/{s/.*url = "\(.*\)";/\1/p;}' flake.nix)
TRAMP_REV := $(shell sed -n '/uefiTrampolineSrc = builtins.fetchGit/,/};/{s/.*rev = "\(.*\)";/\1/p;}' flake.nix)

.PHONY: trampolines
trampolines: $(BUILD_DIR)/uefi-trampoline-0002-nixos.iso $(BUILD_DIR)/uefi-trampoline-0004-windows.iso

# build/uefi-trampoline-<hexid>-<slug>.iso
# Always rebuilt (via FORCE): the real inputs are the pinned trampoline rev and
# SB_KEY/SB_CERT, none of which make can see. Without this, a previous *unsigned*
# build already satisfies the target, so re-running with SB_KEY set silently
# leaves the old unsigned ISO in place and Secure Boot rejects it at boot.
# Note: `.PHONY` does NOT accept patterns -- the `%` is taken literally -- so a
# FORCE prerequisite is the only thing that works here.
$(BUILD_DIR)/uefi-trampoline-%.iso: scripts/pack-trampoline-iso.sh FORCE
	@test -n "$(TRAMP_URL)" -a -n "$(TRAMP_REV)" || { echo "could not read uefiTrampolineSrc url/rev from flake.nix"; exit 1; }
	@mkdir -p $(BUILD_DIR)
	spec='$*'; id=$${spec%%-*}; slug=$${spec#*-}; dec=$$((16#$$id)); \
	  echo "trampoline BootNext=0x$$id ($$slug) <- $(TRAMP_URL)@$(TRAMP_REV)"; \
	  efi=$$(nix build --no-link --print-out-paths --impure --expr "let p = import <nixpkgs> {}; s = builtins.fetchGit { url = \"$(TRAMP_URL)\"; rev = \"$(TRAMP_REV)\"; ref = \"master\"; }; in p.callPackage \"\$${s}/default.nix\" { bootId = $$dec; }")/lib/uefi-trampoline/BOOTX64.EFI; \
	  TEFI="$$efi" OUT="$@" TSLUG="$$slug" ESP_MB="$(ESP_MB)" SB_KEY="$(SB_KEY)" SB_CERT="$(SB_CERT)" \
	    nix shell nixpkgs#sbsigntool nixpkgs#mtools nixpkgs#xorriso --command bash scripts/pack-trampoline-iso.sh
	@echo "-> $@"
