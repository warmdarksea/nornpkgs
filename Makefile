# ---------- Config ----------
FORMAT        ?= qcow2
VM_NAME       := nixvm
SSH_USER      := admin
TOFU          := tofu
BUILD_DIR     := build
STATE_DIR     := state
POOL_DIR      := $(STATE_DIR)/pool

LIBVIRT_URI   := qemu:///system
LIBVIRT_FLAGS := -c $(LIBVIRT_URI)

# Tofu variables
TOFU_VARS := -var="libvirt_uri=$(LIBVIRT_URI)" \
             -var="pool_path=$(abspath $(POOL_DIR))"
TOFU_FLAGS := $(TOFU_VARS) -state=$(STATE_DIR)/terraform.tfstate

# ---------- Build Targets ----------
BASE_DRV_PATH  := $(BUILD_DIR)/base
VM_DRV_PATH    := $(BUILD_DIR)/vm
QCOW2_DRV_PATH := $(BUILD_DIR)/qcow2
AMI_DRV_PATH   := $(BUILD_DIR)/amazon
GCE_DRV_PATH   := $(BUILD_DIR)/gce

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

$(BASE_DRV_PATH): flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.tercha.config.system.build.toplevel -o $@

$(VM_DRV_PATH): flake.nix | $(BUILD_DIR)
	nix build .#nixosConfigurations.oplawn.config.system.build.toplevel -o $@

$(QCOW2_DRV_PATH): flake.nix | $(BUILD_DIR)
	nix build .#qcow2 -o $@

$(AMI_DRV_PATH): flake.nix | $(BUILD_DIR)
	nix build .#amazon -o $@

$(GCE_DRV_PATH): flake.nix | $(BUILD_DIR)
	nix build .#gce -o $@

# $(OPLAWN): flake.nix
# 	@echo "==> Building oplawn..."
# 	@mkdir -p $(BUILD_DIR)
# 	nix build .#nixosConfigurations.oplawn.config.system.build.toplevel -o $@
# 	@echo "==> System: $$(readlink -f $@)/"
# 	@ls -lh $@/

# $(QCOW2): flake.nix
# 	@echo "==> Building qcow2 image..."
# 	@mkdir -p $(BUILD_DIR)
# 	nix build .#qcow2 -o $@
# 	@echo "==> Image: $$(readlink -f $@)/"
# 	@ls -lh $@/

# $(AMAZON): flake.nix
# 	@echo "==> Building Amazon image..."
# 	@mkdir -p $(BUILD_DIR)
# 	nix build .#amazon -o $@
# 	@echo "==> Image: $$(readlink -f $@)/"
# 	@ls -lh $@/

# $(GCE): flake.nix
# 	@echo "==> Building GCE image..."
# 	@mkdir -p $(BUILD_DIR)
# 	nix build .#gce -o $@
# 	@echo "==> Image: $$(readlink -f $@)/"
# 	@ls -lh $@/

# Convenience phony targets
.PHONY: base vm qcow2 amazon gce
base: $(BASE_DRV_PATH)   ## Build tercha (base system derivation)
vm: $(VM_DRV_PATH)   ## Build oplawn (full system with boot/filesystem)
qcow2: $(QCOW2_DRV_PATH)     ## Build qcow2 image (libvirt/KVM)
amazon: $(AMAZON_DRV_PATH)   ## Build Amazon AMI image
gce: $(GCE_DRV_PATH)         ## Build GCE image

# ---------- Tofu / Infra (libvirt) ----------
init: ## Initialize OpenTofu
	$(TOFU) init

plan: $(QCOW2_DRV_PATH) | $(STATE_DIR) $(POOL_DIR) ## Plan libvirt deployment
	$(TOFU) plan $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

deploy: $(QCOW2_DRV_PATH) | $(STATE_DIR) $(POOL_DIR) ## Build qcow2 + deploy VM via OpenTofu
	$(TOFU) apply -auto-approve $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

# ---------- VM Lifecycle (libvirt) ----------
start: ## Start the VM
	virsh $(LIBVIRT_FLAGS) start $(VM_NAME)

stop: ## Gracefully stop the VM
	virsh $(LIBVIRT_FLAGS) shutdown $(VM_NAME)

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
