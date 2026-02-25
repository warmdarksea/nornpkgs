# ---------- Config ----------
ARCH := x86_64-linux
FORMAT        ?= qcow2
VM_NAME       := nixvm
SSH_USER      := admin
TOFU          := tofu
BUILD_DIR     := build
STATE_DIR     := state
POOL_DIR      := $(STATE_DIR)/pool

LIBVIRT_URI   := qemu:///system
LIBVIRT_FLAGS := -c $(LIBVIRT_URI)

LIBVIRT_HOST  := ldtest.hell.gensokyo.internal

# Tofu variables
TOFU_VARS := -var="libvirt_uri=$(LIBVIRT_URI)" \
             -var="pool_path=$(abspath $(POOL_DIR))"
TOFU_FLAGS := $(TOFU_VARS) -state=$(STATE_DIR)/terraform.tfstate

.PHONY: help init plan deploy destroy start stop restart status ssh clean clean-state nuke

# ---------- Default ----------
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------- Build ----------

$(BUILD_DIR):
	mkdir -p $@

$(STATE_DIR):
	mkdir -p $@

$(POOL_DIR):
	mkdir -p $@

# 

$(BUILD_DIR)/bootstrap-drv: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.bootstrap.config.system.build.toplevel -o $@

$(BUILD_DIR)/live-drv: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.live.config.system.build.toplevel -o $@

$(BUILD_DIR)/libvirt-bootstrap-drv: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.libvirt-bootstrap.config.system.build.toplevel -o $@

$(BUILD_DIR)/libvirt-bootstrap-qcow2: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.libvirt-bootstrap.config.system.build.images.qemu -o $@

$(BUILD_DIR)/libvirt-live-drv: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.libvirt-live.config.system.build.toplevel -o $@

$(BUILD_DIR)/oci-bootstrap-drv: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.oci-bootstrap.config.system.build.toplevel -o $@

$(BUILD_DIR)/oci-bootstrap-qcow2: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.oci-bootstrap.config.system.build.images.qemu-efi -o $@

$(BUILD_DIR)/oci-live-drv: flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.oci-live.config.system.build.toplevel -o $@

#

libvirt_plan_bootstrap: $(BUILD_DIR)/libvirt-bootstrap-qcow2 | $(STATE_DIR)
	$(TOFU) plan $(TOFU_FLAGS) -var=bootstrap_img_path=$(realpath $(wildcard $</*.qcow2))

libvirt_deploy_bootstrap: $(BUILD_DIR)/libvirt-bootstrap-qcow2 | $(STATE_DIR)
	$(TOFU) apply $(TOFU_FLAGS) -var=bootstrap_img_path=$(realpath $(wildcard $</*.qcow2))

#libvirt_plan_live: $(BUILD_DIR)/libvirt-live-drv | $(STATE_DIR)
#	$(TOFU) plan $(TOFU_FLAGS) -var=disk_img_path=$(realpath $(wildcard $</*.qcow2))

libvirt_deploy_live: $(BUILD_DIR)/libvirt-live-drv
	nix-copy-closure $(LIBVIRT_HOST) "$(realpath $<)"
	ssh $(LIBVIRT_HOST) "$(realpath $<)/bin/switch-to-configuration switch && nix-collect-garbage -d"

libvirt_destroy:
	$(TOFU) destroy $(TOFU_FLAGS)

# static content

$(BUILD_DIR)/akkoma-fe-drv: flake.nix | $(BUILD_DIR)
	nix build .#packages.$(ARCH).akkoma-fe -o $@

$(BUILD_DIR)/akkoma-fe: $(BUILD_DIR)/akkoma-fe-drv \
			config/akkoma-fe.config.json \
			config/akkoma-fe.local.json | $(BUILD_DIR)
	mkdir -p $@
	cp -Rpv $(BUILD_DIR)/akkoma-fe-drv/. $@
	chmod -R 755 $@
	cp -pv config/akkoma-fe.config.json $@/static/config.json

deploy_akkoma_fe: $(BUILD_DIR)/akkoma-fe
	wrangler pages deploy $< --project-name=akkoma-fe

#

deploy_prod:
	$(TOFU) plan

# dns

# ---------- Tofu / Infra (libvirt) ----------
#init: ## Initialize OpenTofu
#	$(TOFU) init

plan: $(QCOW2_DRV_PATH) | $(STATE_DIR) $(POOL_DIR) ## Plan libvirt deployment
	$(TOFU) plan $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

deploy: $(QCOW2_DRV_PATH) | $(STATE_DIR) $(POOL_DIR) ## Build qcow2 + deploy VM via OpenTofu
	$(TOFU) apply $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

# ---------- VM Lifecycle (libvirt) ----------
start: ## Start the VM
	virsh $(LIBVIRT_FLAGS) start $(VM_NAME)

stop: ## Gracefully stop the VM
	virsh $(LIBVIRT_FLAGS) destroy $(VM_NAME)

restart: stop ## Restart the VM
	@echo "Waiting for shutdown..."
	@sleep 5
	virsh $(LIBVIRT_FLAGS) start $(VM_NAME)

status: ## Show VM status and IP
	@virsh $(LIBVIRT_FLAGS) dominfo $(VM_NAME) 2>/dev/null || echo "VM not found"
	@echo ""
	@echo "Network:"
	@virsh $(LIBVIRT_FLAGS) domifaddr $(VM_NAME) 2>/dev/null || echo "  (no addresses / VM not running)"

ssh: ## SSH into the VM
	@IP=$$(virsh $(LIBVIRT_FLAGS) domifaddr $(VM_NAME) | grep -oP '(\d+\.){3}\d+' | head -1); \
	if [ -z "$$IP" ]; then \
		echo "ERROR: Could not determine VM IP. Is it running?"; \
		exit 1; \
	fi; \
	echo "==> Connecting to $$IP..."; \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP

# ---------- Cleanup ----------
destroy: ## Destroy VM and OpenTofu resources
	$(TOFU) destroy $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

clean: ## Remove built images
	rm -rf $(BUILD_DIR)/
