terraform {
  required_providers {
    # these are managed by nixos
    oci = {
      source = "oracle/oci"
    }
    libvirt = {
      source = "dmacvicar/libvirt"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

# global variables

variable "my_ip" {
  type    = string
  default = "0.0.0.0"
}

variable "ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

#
# cloudflare
#

variable "cf_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cf_account_id" {
  type    = string
  default = ""
}

variable "cf_tunnel_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cf_zone_id_littledevil_club" {
  type    = string
  default = ""
}

variable "cf_zone_id_littledevil_org" {
  type    = string
  default = ""
}

provider "cloudflare" {
  api_token = var.cf_api_token
}

# littledevil.club — www
resource "cloudflare_pages_project" "www_club" {
  account_id        = var.cf_account_id
  name              = "www-littledevil-club"
  production_branch = "master"
}

resource "cloudflare_pages_domain" "www_club" {
  account_id   = var.cf_account_id
  project_name = cloudflare_pages_project.www_club.name
  name         = "littledevil.club"
}

resource "cloudflare_dns_record" "www_club" {
  zone_id = var.cf_zone_id_littledevil_club
  name    = "@"
  content = cloudflare_pages_project.www_club.subdomain
  type    = "CNAME"
  proxied = true
  ttl     = 1  # 1 = automatic when proxied
}

# littledevil.org — www
resource "cloudflare_pages_project" "www_org" {
  account_id        = var.cf_account_id
  name              = "www-littledevil-org"
  production_branch = "master"
}

resource "cloudflare_pages_domain" "www_org" {
  account_id   = var.cf_account_id
  project_name = cloudflare_pages_project.www_org.name
  name         = "littledevil.org"
}

resource "cloudflare_dns_record" "www_org" {
  zone_id = var.cf_zone_id_littledevil_org
  name    = "@"
  content = cloudflare_pages_project.www_org.subdomain
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# akkoma frontend
resource "cloudflare_pages_project" "akkoma" {
  account_id        = var.cf_account_id
  name              = "akkoma-littledevil-club"
  production_branch = "master"
}

resource "cloudflare_pages_domain" "akkoma" {
  account_id   = var.cf_account_id
  project_name = cloudflare_pages_project.akkoma.name
  name         = "akkoma.littledevil.club"
}

resource "cloudflare_dns_record" "akkoma" {
  zone_id = var.cf_zone_id_littledevil_club
  name    = "akkoma"
  content = cloudflare_pages_project.akkoma.subdomain
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# worker that proxies /api, /oauth, /nodeinfo to the akkoma backend
# while letting pages handle everything else (the frontend)
resource "cloudflare_workers_script" "akkoma_proxy" {
  account_id     = var.cf_account_id
  script_name    = "akkoma-api-proxy"
  content_file   = "${path.module}/cf/workers/akkoma-proxy.js"
  content_sha256 = filesha256("${path.module}/cf/workers/akkoma-proxy.js")
  main_module    = "akkoma-proxy.js"

  bindings = [{
    name = "BACKEND_ORIGIN"
    text = "https://ap.littledevil.club"
    type = "plain_text"
  }]
}

resource "cloudflare_workers_route" "akkoma_api" {
  zone_id = var.cf_zone_id_littledevil_club
  pattern = "akkoma.littledevil.club/api/*"
  script  = cloudflare_workers_script.akkoma_proxy.script_name
}

resource "cloudflare_workers_route" "akkoma_oauth" {
  zone_id = var.cf_zone_id_littledevil_club
  pattern = "akkoma.littledevil.club/oauth/*"
  script  = cloudflare_workers_script.akkoma_proxy.script_name
}

resource "cloudflare_workers_route" "akkoma_nodeinfo" {
  zone_id = var.cf_zone_id_littledevil_club
  pattern = "akkoma.littledevil.club/nodeinfo/*"
  script  = cloudflare_workers_script.akkoma_proxy.script_name
}

# backend
resource "cloudflare_dns_record" "backend" {
  zone_id = var.cf_zone_id_littledevil_club
  name    = "ap"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.prod.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "prod" {
  account_id    = var.cf_account_id
  name          = "littledevil-prod"
  config_src    = "cloudflare"
  tunnel_secret = var.cf_tunnel_secret
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "prod" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.prod.id

  config = {
    ingress = [
      {
        hostname = "ap.littledevil.club"
        service  = "http://localhost:4000"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

# r2 bucket for uploads
resource "cloudflare_r2_bucket" "prod_upload" {
  account_id = var.cf_account_id
  name       = "littledevil-prod1"
  location   = "ENAM"  # or whatever's closest to your server
}

resource "cloudflare_r2_custom_domain" "prod_upload" {
  account_id  = var.cf_account_id
  bucket_name = cloudflare_r2_bucket.prod_upload.name
  domain      = "lddn3.littledevil.org"
  zone_id     = var.cf_zone_id_littledevil_org
  enabled     = true
  min_tls     = "1.2"
}

output "cf_tunnel_id" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.prod.id
  sensitive = true
}

# libvirt

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "libvirt_vm_name" {
  type    = string
  default = "nixvm"
}

variable "libvirt_bootstrap_img_path" {
  type    = string
  default = ""
}

variable "libvirt_pool_path" {
  type    = string
  default = ""
}

variable "libvirt_ovmf_code" {
  type    = string
  default = "/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-OVMF-202402-fd/FV/OVMF_CODE.fd"
  description = "Path to OVMF code firmware (should come from nix)"
}

variable "libvirt_ovmf_vars" {
  type    = string
  default = "/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-OVMF-202402-fd/FV/OVMF_VARS.fd"
  description = "Path to OVMF vars template (should come from nix)"
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# =============================================================================
# Libvirt — Storage
# =============================================================================

resource "libvirt_pool" "pool" {
  name = "test-pool"
  type = "dir"
  path = var.libvirt_pool_path
}

resource "libvirt_volume" "base" {
  name   = "${var.libvirt_vm_name}-base.qcow2"
  pool   = libvirt_pool.pool.name
  source = var.libvirt_bootstrap_img_path
  format = "qcow2"
}

resource "libvirt_volume" "overlay" {
  name           = "${var.libvirt_vm_name}.qcow2"
  pool           = libvirt_pool.pool.name
  base_volume_id = libvirt_volume.base.id
  format         = "qcow2"
}

# =============================================================================
# Libvirt — Networking
# =============================================================================

resource "libvirt_network" "net" {
  name      = "nixvm_net"
  mode      = "nat"
  addresses = ["0.0.0.0/24"]
}

# =============================================================================
# Libvirt — Domain
# =============================================================================

resource "libvirt_domain" "vm" {
  name      = var.libvirt_vm_name
  memory    = 2048
  vcpu      = 2
  running   = false
  autostart = false

  # EFI/UEFI firmware for OCI images
  firmware = var.libvirt_ovmf_code

  nvram {
    file     = "${var.libvirt_pool_path}/${var.libvirt_vm_name}_VARS.fd"
    template = var.libvirt_ovmf_vars
  }

  disk {
    volume_id = libvirt_volume.overlay.id
  }

  network_interface {
    network_id     = libvirt_network.net.id
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}

# oci

variable "oci_tenancy_ocid" {
  type    = string
  default = ""
}

variable "oci_user_ocid" {
  type    = string
  default = ""
}

variable "oci_fingerprint" {
  type    = string
  default = ""
}

variable "oci_private_key_path" {
  type    = string
  default = ""
}

variable "oci_home_region" {
  type    = string
  default = "us-ashburn-1"
}

variable "oci_compartment_ocid" {
  type    = string
  default = ""
}

variable "oci_availability_domain" {
  type    = string
  default = "cgkF:US-ASHBURN-AD-2"
}

variable "oci_bootstrap_image_store_path" {
  type    = string
  default = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-oci-image"
}

variable "oci_bootstrap_image_file_path" {
  type    = string
  default = "nixos-image-oci-x86_64-linux.qcow2"
}

variable "oci_live_config_store_path" {
  type    = string
  default = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.oci_home_region
}

# =============================================================================
# OCI — Data Sources
# =============================================================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.oci_tenancy_ocid
}

# =============================================================================
# OCI — Image Upload + Import
# =============================================================================

resource "oci_objectstorage_bucket" "images" {
  compartment_id = var.oci_compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "littledevil-images"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"

  freeform_tags = {
    "tier" = "always-free"
  }
}

resource "oci_objectstorage_object" "bootstrap_img_obj" {
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  bucket       = oci_objectstorage_bucket.images.name
  object       = "${var.oci_bootstrap_image_store_path}/${var.oci_bootstrap_image_file_path}"
  source       = "${var.oci_bootstrap_image_store_path}/${var.oci_bootstrap_image_file_path}"
  content_type = "application/octet-stream"
}

resource "oci_core_image" "bootstrap_img" {
  compartment_id = var.oci_compartment_ocid
  display_name   = "nixos-bootstrap-oci"
  launch_mode = "PARAVIRTUALIZED"
  #launch_mode    = "CUSTOM"
  # launch_options {
  #   boot_volume_type = "PARAVIRTUALIZED"
  #   firmware = "UEFI_64"
  #   #is_consistent_volume_naming_enabled = false
  #   network_type = "PARAVIRTUALIZED"
  #   remote_data_volume_type = "PARAVIRTUALIZED"
  # }

  image_source_details {
    source_type       = "objectStorageTuple"
    namespace_name    = data.oci_objectstorage_namespace.ns.namespace
    bucket_name       = oci_objectstorage_bucket.images.name
    object_name       = oci_objectstorage_object.bootstrap_img_obj.object
    source_image_type = "QCOW2"
  }

  freeform_tags = {
    "tier" = "always-free"
  }

  timeouts {
    create = "45m"
  }

  lifecycle {
    replace_triggered_by = [
      oci_objectstorage_object.bootstrap_img_obj
    ]
  }
}

data "oci_core_compute_global_image_capability_schemas" "global" {}

data "oci_core_compute_global_image_capability_schemas_versions" "versions" {
  compute_global_image_capability_schema_id = data.oci_core_compute_global_image_capability_schemas.global.compute_global_image_capability_schemas[0].id
}

locals {
  global_schema_id      = data.oci_core_compute_global_image_capability_schemas.global.compute_global_image_capability_schemas[0].id
  global_schema_version = data.oci_core_compute_global_image_capability_schemas_versions.versions.compute_global_image_capability_schema_versions[0].name
}

resource "oci_core_compute_image_capability_schema" "bootstrap_uefi" {
  compartment_id                                      = var.oci_compartment_ocid
  image_id                                            = oci_core_image.bootstrap_img.id
  compute_global_image_capability_schema_version_name = local.global_schema_version
  #compute_global_image_capability_schema_id           = local.global_schema_id

  schema_data = {
    "Compute.Firmware" = jsonencode({
      descriptorType = "enumstring"
      defaultValue   = "UEFI_64"
      source         = "IMAGE"
      values         = ["UEFI_64"]
    })
  }
}

# resource "oci_compute_image_capability_schema" "nixos_arm_uefi" {
#   compartment_id                            = var.compartment_id
#   image_id                                  = oci_core_image.nixos_arm.id
#   compute_global_image_capability_schema_version_name = data.oci_compute_global_image_capability_schema.schema.current_version_name
#   global_image_capability_schema_id         = data.oci_compute_global_image_capability_schema.schema.id

#   schema_data {
#     # you'll need to check the exact attribute shape here
#   }
# }

resource "oci_core_shape_management" "bootstrap_shape" {
  compartment_id = var.oci_compartment_ocid
  image_id = oci_core_image.bootstrap_img.id
  shape_name = "VM.Standard.A1.Flex"
}

# =============================================================================
# OCI — Networking
# =============================================================================

resource "oci_core_vcn" "vcn" {
  compartment_id = var.oci_compartment_ocid
  display_name   = "littledevil-prod-vcn"
  cidr_blocks    = ["0.0.0.0/16"]
  dns_label      = "nixvcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "littledevil-prod-igw"
  enabled        = true
}

resource "oci_core_route_table" "public_rt" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "public_sl" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "littledevil-prod-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  # SSH
  ingress_security_rules {
    protocol  = "6"
    source    = "${var.my_ip}/32"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 25565
      max = 25565
    }
  }

  # HTTP
  # ingress_security_rules {
  #   protocol  = "6"
  #   source    = "0.0.0.0/0"
  #   stateless = false
  #   tcp_options {
  #     min = 80
  #     max = 80
  #   }
  # }

  # # HTTPS
  # ingress_security_rules {
  #   protocol  = "6"
  #   source    = "0.0.0.0/0"
  #   stateless = false
  #   tcp_options {
  #     min = 443
  #     max = 443
  #   }
  # }

  # ICMP
  ingress_security_rules {
    protocol  = "1"
    source    = "0.0.0.0/0"
    stateless = false
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.oci_compartment_ocid
  vcn_id                     = oci_core_vcn.vcn.id
  cidr_block                 = "0.0.0.0/24"
  display_name               = "littledevil-prod-public"
  dns_label                  = "ldpub"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids          = [oci_core_security_list.public_sl.id]
  prohibit_public_ip_on_vnic = false
}

# =============================================================================
# OCI — Compute
# =============================================================================

resource "oci_core_instance" "prod" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = var.oci_availability_domain
  display_name        = "littledevil-prod"
  #shape               = "VM.Standard.E2.1.Micro"
  shape = "VM.Standard.A1.Flex"
  #shape               = var.oci_instance_shape

  # --- NEW: required for flex shapes, ignored for fixed shapes ---
  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  source_details {
    source_type             = "image"
    source_id               = oci_core_image.bootstrap_img.id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  freeform_tags = {
    "tier" = "always-free"
  }

  # Automatically recreate instance when bootstrap image changes
  lifecycle {
    replace_triggered_by = [
      oci_core_image.bootstrap_img
    ]
  }

  depends_on = [
    oci_core_shape_management.bootstrap_shape
  ]

  # wait for ssh before declaring the resource created
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      host = self.public_ip
      user = "root"
      private_key = file("${var.ssh_private_key_path}")
    }
    inline = [ "true" ]
  }
}

resource "oci_core_instance" "staging" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = var.oci_availability_domain
  display_name        = "littledevil-staging"
  shape               = "VM.Standard.E2.1.Micro"
  #shape = "VM.Standard.A1.Flex"
  #shape               = var.oci_instance_shape

  # --- NEW: required for flex shapes, ignored for fixed shapes ---
  #shape_config {
  #  ocpus         = 1
  #  memory_in_gbs = 6
  #}

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  source_details {
    source_type             = "image"
    source_id               = oci_core_image.bootstrap_img.id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  freeform_tags = {
    "tier" = "always-free"
  }

  # Automatically recreate instance when bootstrap image changes
  lifecycle {
    replace_triggered_by = [
      oci_core_image.bootstrap_img
    ]
  }

  depends_on = [
    oci_core_shape_management.bootstrap_shape
  ]

  # wait for ssh before declaring the resource created
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      host = self.public_ip
      user = "root"
      private_key = file("${var.ssh_private_key_path}")
    }
    inline = [ "true" ]
  }
}

# volume — never destroy
resource "oci_core_volume" "prod_data" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = var.oci_availability_domain
  display_name        = "littledevil-prod-data"
  size_in_gbs         = 50

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume_attachment" "prod_data_conn" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.prod.id
  volume_id       = oci_core_volume.prod_data.id
}

output "oci_public_ip" {
  value = oci_core_instance.prod.public_ip
}

# build targets
# terraform modules are stupid and don't really encapsulate anything, so we just
# use these null resources to refer to everything in a set and build those

resource "null_resource" "oci_prod_bootstrap" {
  depends_on = [
    oci_core_instance.prod
  ]

  triggers = {
    instance_id = oci_core_instance.prod.id
    shape_id = oci_core_shape_management.bootstrap_shape.id
    image_schema_id = oci_core_compute_image_capability_schema.bootstrap_uefi.id
  }
}

resource "null_resource" "oci_prod_live" {
  depends_on = [
    oci_core_instance.prod,
    oci_core_volume_attachment.prod_data_conn,
    cloudflare_pages_project.www_club,
    cloudflare_pages_domain.www_club,
    cloudflare_dns_record.www_club,
    cloudflare_pages_project.www_org,
    cloudflare_pages_domain.www_org,
    cloudflare_dns_record.www_org,
    cloudflare_zero_trust_tunnel_cloudflared.prod,
    cloudflare_zero_trust_tunnel_cloudflared_config.prod,
    cloudflare_dns_record.backend,
    cloudflare_pages_project.akkoma,
    cloudflare_pages_domain.akkoma,
    cloudflare_dns_record.akkoma,
    cloudflare_workers_script.akkoma_proxy,
    cloudflare_workers_route.akkoma_api,
    cloudflare_workers_route.akkoma_oauth,
    cloudflare_workers_route.akkoma_nodeinfo,
  ]
  triggers = {
    deps = join(",", [
      oci_core_instance.prod.id,
      oci_core_security_list.public_sl.id,
      oci_core_shape_management.bootstrap_shape.id,
      oci_core_compute_image_capability_schema.bootstrap_uefi.id,
      var.oci_live_config_store_path,
      cloudflare_pages_project.www_club.id,
      cloudflare_pages_domain.www_club.id,
      cloudflare_dns_record.www_club.id,
      cloudflare_pages_project.www_org.id,
      cloudflare_pages_domain.www_org.id,
      cloudflare_dns_record.www_org.id,
      cloudflare_zero_trust_tunnel_cloudflared.prod.id,
      cloudflare_zero_trust_tunnel_cloudflared_config.prod.id,
      cloudflare_dns_record.backend.id,
      cloudflare_r2_custom_domain.prod_upload.domain,
      cloudflare_pages_project.akkoma.id,
      cloudflare_pages_domain.akkoma.id,
      cloudflare_dns_record.akkoma.id,
      cloudflare_workers_script.akkoma_proxy.id,
    ])
  }

  provisioner "local-exec" {
    command = "nix-copy-closure --to root@${oci_core_instance.prod.public_ip} ${var.oci_live_config_store_path}"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = oci_core_instance.prod.public_ip
      user        = "root"
      private_key = file("${var.ssh_private_key_path}")
    }
    inline = ["${var.oci_live_config_store_path}/bin/switch-to-configuration switch"]
  }
}

resource "null_resource" "libvirt_test" {
  depends_on = [
    libvirt_domain.vm,
  ]
}
