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

#

variable "ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
}

# cloudflare

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_account_id" {
  type    = string
  default = ""
}

variable "cloudflare_zone_id" {
  type    = string
  default = ""
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
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

variable "oci_bootstrap_image_path" {
  type    = string
  default = ""
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

resource "oci_objectstorage_object" "bootstrap_qcow2" {
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  bucket       = oci_objectstorage_bucket.images.name
  object       = "bootstrap-oci.qcow2"
  source       = var.oci_bootstrap_image_path
  content_type = "application/octet-stream"
}

resource "oci_core_image" "bootstrap" {
  compartment_id = var.oci_compartment_ocid
  display_name   = "nixos-bootstrap-oci"
  launch_mode    = "PARAVIRTUALIZED"

  image_source_details {
    source_type       = "objectStorageTuple"
    namespace_name    = data.oci_objectstorage_namespace.ns.namespace
    bucket_name       = oci_objectstorage_bucket.images.name
    object_name       = oci_objectstorage_object.bootstrap_qcow2.object
    source_image_type = "QCOW2"
  }

  freeform_tags = {
    "tier" = "always-free"
  }

  timeouts {
    create = "45m"
  }
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
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }

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
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
  display_name        = "littledevil-prod"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  source_details {
    source_type             = "image"
    source_id               = oci_core_image.bootstrap.id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  freeform_tags = {
    "tier" = "always-free"
  }
}

# build targets
# terraform modules are stupid and don't really encapsulate anything, so we just
# use these null resources to refer to everything in a set and build those

resource "null_resource" "prod" {
  depends_on = [
    oci_core_instance.prod
  ]
}

resource "null_resource" "test" {
  depends_on = [
    libvirt_domain.vm,
  ]
}
