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

#

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
# static content
#

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
# oci
#

.PHONY: deploy_oci_secrets deploy_oci_bootstrap deploy_oci_live ssh_oci destroy_oci

deploy_oci_sql_secret:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip))
	for i in akkoma; do \
	  printf "ALTER USER %s WITH PASSWORD \'%s\';" "$$i" "$$(cat $(SECRET_DIR)/oci/$$i/dbpassword)" | ssh $(SSH_FLAGS) root@$(IP) -- sudo -u postgres psql; \
	done

$(BUILD_DIR)/.oci-secret-deployed: Makefile $(OCI_SECRET_SRC)
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
	touch $@

.PHONY: deploy_oci_secrets
deploy_oci_secrets: $(BUILD_DIR)/.oci-secret-deployed

$(BUILD_DIR)/prod-deployment.tfvars: tf/prod-deployment.tfvars.m4 \
	$(BUILD_DIR)/$(PLATFORM)-bootstrap-$(ARCH)-img \
	$(BUILD_DIR)/$(PLATFORM)-live-$(ARCH)-drv | $(BUILD_DIR)
	m4 \
	  -DMY_IP='$(shell curl -s ifconfig.me)' \
	  -D"SSH_PUBLIC_KEY=$(shell cat $(SSH_KEY_PATH).pub)" \
	  -DSSH_KEY_PATH='$(SSH_KEY_PATH)' \
	  -DOCI_BOOTSTRAP_IMAGE_STORE_PATH='$(realpath $(word 2,$^))' \
	  -DOCI_BOOTSTRAP_IMAGE_FILE_PATH='nixos-image-oci-$(ARCH)-linux.qcow2' \
	  -DOCI_LIVE_CONFIG_STORE_PATH='$(realpath $(word 3,$^))' \
	  $< > $@

$(BUILD_DIR)/prod-deployment.tfplan: main.tf \
	$(BUILD_DIR)/prod-deployment.tfvars \
	$(BUILD_DIR)/.www-club-deployed \
	$(BUILD_DIR)/.oci-secret-deployed | $(STATE_DIR)
	$(TERRAFORM) plan $(TF_FLAGS) \
	  -var-file=$(word 2,$^) \
	  -out=$@ \
	  -target null_resource.$(PLATFORM)_$(ENV)_live

deploy_oci_bootstrap: $(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-img | $(STATE_DIR)
	$(TERRAFORM) apply $(TF_FLAGS) -target null_resource.$(PLATFORM)_$(ENV)_bootstrap

plan_oci_live: $(BUILD_DIR)/prod-deployment.tfplan

deploy_oci_live: $(BUILD_DIR)/prod-deployment.tfplan | $(STATE_DIR)
	@echo "Terraform plan:"
	$(TERRAFORM) show $<
	read -p "Apply? Type 'yes' to confirm: " ans; [ "$ans" != "yes" ] && exit 1
	$(TERRAFORM) apply $(TF_FLAGS) \
	  -var-file=$(BUILD_DIR)/prod-deployment.tfvars \
	  $<

destroy_oci: $(BUILD_DIR)/$(PLATFORM)-$(CONFIG)-$(ARCH)-img | $(STATE_DIR)
	$(TERRAFORM) destroy $(TF_FLAGS) \
	  -var-file=$(BUILD_DIR)/prod-deployment.tfvars \
	  -target null_resource.$(PLATFORM)_$(ENV) \
	  -target oci_core_instance.prod

ssh_oci:
	$(eval IP := $(shell $(TERRAFORM) output $(TF_FLAGS) -raw oci_public_ip 2>/dev/null))
	$(SSH) $(SSH_FLAGS) root@$(IP)

ssh_ts:
	$(SSH) $(SSH_FLAGS) root@littledevil-prod.tail3b43e6.ts.net

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
# libvirt (currently broken)
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

#

clean: ## Remove built images
	rm -rf $(BUILD_DIR)/
