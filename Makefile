# make references symlink target mtime, not symlink mtime, so targets that are
# symlinks to store paths will always be built without this flag
MAKEFLAGS+=-L

DOMAIN=gensokyo.internal
HOST=$(TARGET).$(DOMAIN)

BUILD_DIR=build

#

TARGET=nonexistant
ISO_FLAVOR=nonexistant
REMOTE_STORE_PATH=/nonexistant
INSTALL_PATH=/nonexistant

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
.PHONY: $(BUILD_DIR)/sys-$(TARGET)
$(BUILD_DIR)/sys-$(TARGET): flake.nix 	  	    \
			    flake.lock 		    \
			    sys/$(TARGET)/flake.nix
	nix build $(NIX_FLAGS) -o "$@" .#nixosConfigurations.$(TARGET).config.system.build.toplevel

$(BUILD_DIR)/iso-$(ISO_FLAVOR): flake.nix 	  	    \
				flake.lock 		    \
				iso/$(ISO_FLAVOR)/flake.nix \
				iso/$(ISO_FLAVOR)/flake.lock
	nix build $(NIX_FLAGS) -o "$@" .#nixosConfigurations.iso-$(ISO_FLAVOR).config.system.build.isoImage

#

.PHONY: build_sys_closure
build_sys_closure: $(BUILD_DIR)/sys-$(TARGET)

.PHONY: build_iso_closure
build_iso_closure: $(BUILD_DIR)/iso-$(ISO_FLAVOR)

#

.PHONY: push_closure
push_closure: $(BUILD_DIR)/sys-$(TARGET)
	nix copy --to "ssh://root@$(HOST)" "$<"

# ah, memories
.PHONY: push_closure_to
push_closure_to: $(BUILD_DIR)/sys-$(TARGET)
	nix copy "$<" --to "ssh://root@$(HOST)?remote-store=$(REMOTE_STORE_PATH)"

#

.PHONY: set_local_active_closure
set_local_active_closure: $(BUILD_DIR)/sys-$(TARGET)
	sudo nix-env --profile /nix/var/nix/profiles/system --set $(shell realpath "$<")
	sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch

.PHONY: set_local_boot_closure
set_local_boot_closure: $(BUILD_DIR)/sys-$(TARGET)
	sudo nix-env --profile /nix/var/nix/profiles/system --set $(shell realpath "$<")
	sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot

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

.PHONY: install_closure_to_path
install_closure_to_path: $(BUILD_DIR)/sys-$(TARGET)
	sudo nixos-install --no-root-password --root "$(INSTALL_PATH)" --system "$<"

#

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: collect_garbage
collect_garbage:
	sudo nix-collect-garbage -d

# delete references to all generations in between the boot generation and the
# current generation, exclusive (so skip the boot and current, obviously)
# then update the boot menu
.PHONY: cleanup_system_generations
cleanup_system_generations:
	bash bin/nix-cleanup-generations.sh
	sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot

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

