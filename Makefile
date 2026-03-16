# x86_64 or aarch64
ARCH          ?= x86_64
# base (none), libvirt, oci
PLATFORM      ?= none
# test, prod
ENV           ?= test
# bootstrap or live
CONFIG	      ?= bootstrap

BUILD_DIR     := build
STATE_DIR     := state
POOL_DIR      := $(STATE_DIR)/pool
SECRET_DIR    := secret

SSH	      ?= ssh
SSH_KEY_PATH  ?= ~/.ssh/id_clownpiece
SSH_FLAGS     ?= -i $(SSH_KEY_PATH)

TERRAFORM     ?= tofu
TF_FLAGS      := -state=$(STATE_DIR)/terraform.tfstate

LIBVIRT_URI   := qemu:///system
LIBVIRT_FLAGS := -c $(LIBVIRT_URI)

LIBVIRT_HOST  := ldtest.hell.gensokyo.internal

OCI_SECRETS_SRC := $(shell find $(SECRET_DIR) -type f)

WWW_CLUB_SRC := $(shell find www/littledevil.club -type f)
WWW_ORG_SRC := $(shell find www/littledevil.org -type f)

CAPTURE :=
NET_FILTER := not port 22$(if $(CAPTURE), and ($(CAPTURE)),)
TCPDUMP_FLAGS := $(TCPDUMP_FLAGS) -U

#.PHONY: help init plan deploy destroy start stop restart status clean clean-state nuke

# ---------- Default ----------
#help: ## Show this help
#	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
#		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------- Build ----------

$(BUILD_DIR):
	mkdir -p $@

$(STATE_DIR):
	mkdir -p $@

$(POOL_DIR):
	mkdir -p $@

#
# nix
#

$(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-drv: flake.nix | $(BUILD_DIR)
	NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#packages.$(ARCH).nixosConfigurations.$(PLATFORM)-$(CONFIG).config.system.build.toplevel -o $@

$(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-img: flake.nix | $(BUILD_DIR)
	NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#packages.$(ARCH).images.$(PLATFORM)-$(CONFIG) -o $@

#
# cloudflare
#

# fixme: this is hardcoded in the prod.tfvars secret atm
secret/cf-tunnel:
	openssl rand -base64 32 > $@

secret/cf-tunnel-creds.json:
	@echo '{"AccountTag":"${CLOUDFLARE_ACCOUNT_ID}","TunnelID":"$(shell $(TERRAFORM) output $(TF_FLAGS) -raw cf_tunnel_id)","TunnelSecret":"$(shell cat secret/cf-tunnel)"}' > $@

$(BUILD_DIR)/.www-club-deployed: $(WWW_CLUB_SRC)
	wrangler pages deploy www/littledevil.club --project-name=www-littledevil-club
	touch $@
$(BUILD_DIR)/.www-org-deployed: $(WWW_ORG_SRC)
	wrangler pages deploy www/littledevil.org --project-name=www-littledevil-org
	touch $@

deploy_www_club: $(BUILD_DIR)/.www-club-deployed
deploy_www_org: $(BUILD_DIR)/.www-org-deployed

#
# oci
#

.PHONY: deploy_oci_secrets deploy_oci_bootstrap deploy_oci_live ssh_oci destroy_oci

deploy_oci_sql_secret:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip))
	for i in akkoma; do \
	  printf "ALTER USER %s WITH PASSWORD \'%s\';" "$$i" "$$(cat $(SECRET_DIR)/oci/$$i/dbpassword)" | ssh $(SSH_FLAGS) root@$(IP) -- sudo -u postgres psql; \
	done

$(BUILD_DIR)/.oci-secret-deployed: $(OCI_SECRET_SRC)
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip))
	ssh $(SSH_FLAGS) root@$(IP) "mkdir -p /var/secret && chmod 700 /var/secret"
	scp -rp $(SECRET_DIR)/oci/* root@$(IP):/var/secret/
	ssh $(SSH_FLAGS) root@$(IP) "chown -R root:root /var/secret"
	ssh $(SSH_FLAGS) root@$(IP) "chmod -R 700 /var/secret"
	ssh $(SSH_FLAGS) root@$(IP) "mkdir -p /var/secret/akkoma"
	ssh $(SSH_FLAGS) root@$(IP) "chown -R akkoma:akkoma /var/secret/akkoma/"
	ssh $(SSH_FLAGS) root@$(IP) "chmod 700 /var/secret/akkoma"
	ssh $(SSH_FLAGS) root@$(IP) "chmod 700 /var/secret/akkoma/*"
	ssh $(SSH_FLAGS) root@$(IP) "chmod 711 /var/secret" # -p should preserve perms but

deploy_oci_secrets: $(BUILD_DIR)/.oci-secret-deployed

$(BUILD_DIR/deployment-$(PLATFORM)-$(ENV).tfvars):
	true

deploy_oci_bootstrap: $(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-img | $(STATE_DIR)
	$(TERRAFORM) apply $(TF_FLAGS) \
	  -var-file=secret/prod.tfvars \
	  -var oci_bootstrap_image_store_path=$(realpath $<) \
	  -var oci_bootstrap_image_file_path=nixos-image-oci-$(ARCH)-linux.qcow2 \
	  -var oci_live_config_store_path=$(realpath $(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-drv) \
	  -var my_ip=$(shell curl -s ifconfig.me) \
	  -var "ssh_private_key_path=$(SSH_KEY_PATH)" \
	  -target null_resource.$(PLATFORM)_$(ENV)_bootstrap

deploy_oci_live: $(BUILD_DIR)/$(PLATFORM)-bootstrap-$(ARCH)-img \
		 $(BUILD_DIR)/$(PLATFORM)-live-$(ARCH)-drv \
	         $(BUILD_DIR)/.www-club-deployed \
		 $(BUILD_DIR)/.oci-secret-deployed | $(STATE_DIR)
	$(TERRAFORM) apply $(TF_FLAGS) \
	  -var-file=secret/prod.tfvars \
	  -var oci_bootstrap_image_store_path=$(realpath $<) \
	  -var oci_bootstrap_image_file_path=nixos-image-oci-$(ARCH)-linux.qcow2 \
	  -var oci_live_config_store_path=$(realpath $(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-drv) \
	  -var my_ip=$(shell curl -s ifconfig.me) \
	  -var "ssh_private_key_path=$(SSH_KEY_PATH)" \
	  -target null_resource.$(PLATFORM)_$(ENV)_live

destroy_oci: $(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-img | $(STATE_DIR)
	$(TERRAFORM) destroy $(TF_FLAGS) \
	  -var-file=secret/prod.tfvars \
	  -var oci_bootstrap_image_store_path=$(realpath $</nixos-image-oci-x86_64-linux.qcow2) \
	  -target null_resource.$(PLATFORM)_$(ENV) \
	  -target oci_core_instance.prod

ssh_oci:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip 2>/dev/null))
	$(SSH) $(SSH_FLAGS) root@$(IP)

ssh_ts:
	$(SSH) $(SSH_FLAGS) root@0.0.0.0

log_oci:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip 2>/dev/null))
	$(SSH) $(SSH_FLAGS) -t root@$(IP) -- journalctl -xe -f

tcpdump_oci:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip 2>/dev/null))
	$(SSH) $(SSH_FLAGS) root@$(IP) -- "tcpdump $(TCPDUMP_FLAGS) '$(NET_FILTER)'"

wireshark_oci:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip 2>/dev/null))
	$(SSH) $(SSH_FLAGS) root@$(IP) -- "tcpdump $(TCPDUMP_FLAGS) -s0 -w - '$(NET_FILTER)'" | wireshark -k -i -

#



#.PHONY: deploy
#deploy:
#	$(MAKE) deploy_$(PLATFORM) ENV=$(ENV) CONFIG=$(CONFIG) ARCH=$(ARCH) PLATFORM=$(PLATFORM)


#$(BUILD_DIR)/bootstrap-drv: flake.nix | $(BUILD_DIR)
#	nix build .#nixosConfigurations.bootstrap.config.system.build.toplevel -o $@

#$(BUILD_DIR)/bootstrap-aarch64-drv: flake.nix | $(BUILD_DIR)
#	nix build .#nixosConfigurations.bootstrap-aarch64.config.system.build.toplevel -o $@

# $(BUILD_DIR)/bootstrap-$(ARCH)-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#packages.$(ARCH).nixosConfigurations.bootstrap.config.system.build.toplevel -o $@

# $(BUILD_DIR)/oci-bootstrap-$(ARCH)-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#packages.$(ARCH).nixosConfigurations.oci-bootstrap.config.system.build.toplevel -o $@

# $(BUILD_DIR)/oci-bootstrap-$(ARCH)-img: flake.nix | $(BUILD_DIR)
# 	nix build .#packages.$(ARCH).oci-bootstrap-img -o $@

# $(BUILD_DIR)/live-$(ARCH)-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#packages.$(ARCH).nixosConfigurations.live.config.system.build.toplevel -o $@



# $(BUILD_DIR)/libvirt-bootstrap-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.libvirt-bootstrap.config.system.build.toplevel -o $@

# $(BUILD_DIR)/libvirt-bootstrap-qcow2: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.libvirt-bootstrap.config.system.build.images.qemu -o $@

# $(BUILD_DIR)/libvirt-live-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.libvirt-live.config.system.build.toplevel -o $@

# $(BUILD_DIR)/oci-bootstrap-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.oci-bootstrap.config.system.build.toplevel -o $@

# $(BUILD_DIR)/oci-bootstrap-qcow2: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.oci-bootstrap.config.system.build.images.qemu -o $@

# $(BUILD_DIR)/oci-bootstrap-img: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.oci-bootstrap.config.system.build.OCIImage -o $@

# $(BUILD_DIR)/oci-bootstrap-aarch64-img: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.oci-bootstrap-aarch64.config.system.build.OCIImage -o $@

# $(BUILD_DIR)/oci-live-drv: flake.nix | $(BUILD_DIR)
# 	nix build .#nixosConfigurations.oci-live.config.system.build.toplevel -o $@

# $(BUILD_DIR)/ovmf: flake.nix | $(BUILD_DIR)
# 	nix build .#ovmf -o $@

#

libvirt_plan_bootstrap: $(BUILD_DIR)/libvirt-bootstrap-qcow2 $(BUILD_DIR)/ovmf | $(STATE_DIR)
	$(TOFU) plan $(TOFU_FLAGS) -var=libvirt_bootstrap_img_path=$(realpath $(wildcard $(BUILD_DIR)/libvirt-bootstrap-qcow2/*.qcow2))

libvirt_deploy_bootstrap: $(BUILD_DIR)/libvirt-bootstrap-qcow2 $(BUILD_DIR)/ovmf | $(STATE_DIR)
	$(TOFU) apply $(TOFU_FLAGS) -var=libvirt_bootstrap_img_path=$(realpath $(wildcard $(BUILD_DIR)/libvirt-bootstrap-qcow2/*.qcow2))

libvirt_plan_oci: $(BUILD_DIR)/oci-bootstrap-qcow2 $(BUILD_DIR)/ovmf | $(STATE_DIR)
	$(TOFU) plan $(TOFU_FLAGS) -var=libvirt_bootstrap_img_path=$(realpath $(wildcard $(BUILD_DIR)/oci-bootstrap-qcow2/*.qcow2))

libvirt_deploy_oci: $(BUILD_DIR)/oci-bootstrap-qcow2 $(BUILD_DIR)/ovmf | $(STATE_DIR)
	$(TOFU) apply $(TOFU_FLAGS) -target=null_resource.test_libvirt -var=libvirt_bootstrap_img_path=$(realpath $(wildcard $(BUILD_DIR)/oci-bootstrap-qcow2/*.qcow2))

#libvirt_plan_live: $(BUILD_DIR)/libvirt-live-drv | $(STATE_DIR)
#	$(TOFU) plan $(TOFU_FLAGS) -var=disk_img_path=$(realpath $(wildcard $</*.qcow2))

libvirt_deploy_live: $(BUILD_DIR)/libvirt-live-drv
	nix-copy-closure $(LIBVIRT_HOST) "$(realpath $<)"
	ssh $(LIBVIRT_HOST) "$(realpath $<)/bin/switch-to-configuration switch && nix-collect-garbage -d"

libvirt_destroy:
	$(TOFU) destroy $(TOFU_FLAGS)

# oci_deploy_bootstrap: $(BUILD_DIR)/oci-bootstrap-img | $(STATE_DIR)
# 	tofu apply -var-file=secret/prod.tfvars -var oci_bootstrap_image_path=$(realpath $</nixos-image-oci-x86_64-linux.qcow2) -target oci_core_instance.prod

# oci_destroy: $(BUILD_DIR)/oci-bootstrap-img | $(STATE_DIR)
# 	tofu destroy -var-file=secret/prod.tfvars -var oci_bootstrap_image_path=$(realpath $</nixos-image-oci-x86_64-linux.qcow2) -target oci_core_instance.prod

# static content

$(BUILD_DIR)/akkoma-fe-drv: flake.nix | $(BUILD_DIR)
	nix build .#packages.$(ARCH)-linux.akkoma-fe -o $@

$(BUILD_DIR)/akkoma-fe: $(BUILD_DIR)/akkoma-fe-drv | $(BUILD_DIR)
	mkdir -p $@
	cp -Rpv $(BUILD_DIR)/akkoma-fe-drv/. $@
	chmod -R 755 $@

deploy_akkoma_fe: $(BUILD_DIR)/akkoma-fe
	cp -r www/akkoma.littledevil.club/. $</
	wrangler pages deploy $< --project-name=akkoma-littledevil-club

#

#deploy_prod:
#	$(TOFU) plan

# dns

# ---------- Tofu / Infra (libvirt) ----------
#init: ## Initialize OpenTofu
#	$(TOFU) init

#plan: $(QCOW2_DRV_PATH) | $(STATE_DIR) $(POOL_DIR) ## Plan libvirt deployment
#	$(TOFU) plan $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

#deploy: $(QCOW2_DRV_PATH) | $(STATE_DIR) $(POOL_DIR) ## Build qcow2 + deploy VM via OpenTofu
#	$(TOFU) apply $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

# ---------- VM Lifecycle (libvirt) ----------
# start: ## Start the VM
# 	virsh $(LIBVIRT_FLAGS) start $(VM_NAME)

# stop: ## Gracefully stop the VM
# 	virsh $(LIBVIRT_FLAGS) destroy $(VM_NAME)

# restart: stop ## Restart the VM
# 	@echo "Waiting for shutdown..."
# 	@sleep 5
# 	virsh $(LIBVIRT_FLAGS) start $(VM_NAME)

# status: ## Show VM status and IP
# 	@virsh $(LIBVIRT_FLAGS) dominfo $(VM_NAME) 2>/dev/null || echo "VM not found"
# 	@echo ""
# 	@echo "Network:"
# 	@virsh $(LIBVIRT_FLAGS) domifaddr $(VM_NAME) 2>/dev/null || echo "  (no addresses / VM not running)"

# ssh: ## SSH into the VM
# 	@IP=$$(virsh $(LIBVIRT_FLAGS) domifaddr $(VM_NAME) | grep -oP '(\d+\.){3}\d+' | head -1); \
# 	if [ -z "$$IP" ]; then \
# 		echo "ERROR: Could not determine VM IP. Is it running?"; \
# 		exit 1; \
# 	fi; \
# 	echo "==> Connecting to $$IP..."; \
# 	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP

# ---------- Cleanup ----------
#destroy: ## Destroy VM and OpenTofu resources
#	$(TOFU) destroy $(TOFU_FLAGS) -var=disk_image_path=$(abspath $(QCOW2_DRV_PATH)/nixos.qcow2)

clean: ## Remove built images
	rm -rf $(BUILD_DIR)/
