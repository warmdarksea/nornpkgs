terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}

# ---------- Variables ----------

variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
}

variable "vm_name" {
  description = "Name of the VM"
  type        = string
  default     = "nixvm"
}

variable "disk_image_path" {
  description = "Absolute path to the qcow2 disk image (will be used as backing file)"
  type        = string
}

variable "pool_path" {
  description = "Path to libvirt storage pool"
  type        = string
}

# Configure the Libvirt Provider
provider "libvirt" {
  uri = var.libvirt_uri
}

# ---------- Storage ----------

resource "libvirt_pool" "nixvm_pool" {
  name = "test-pool"
  type = "dir"
  path = var.pool_path
}

# Base volume from Nix store
resource "libvirt_volume" "base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = libvirt_pool.nixvm_pool.name
  source = var.disk_image_path
  format = "qcow2"
}

# CoW overlay volume
resource "libvirt_volume" "overlay" {
  name           = "${var.vm_name}.qcow2"
  pool           = libvirt_pool.nixvm_pool.name
  base_volume_id = libvirt_volume.base.id
  format         = "qcow2"
}

# ---------- Domain ----------

resource "libvirt_domain" "nixvm" {
  name      = var.vm_name
  memory    = 2048
  vcpu      = 2
  running   = false
  autostart = false

  disk {
    volume_id = libvirt_volume.overlay.id
  }

  network_interface {
    network_name   = "default"
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

# ---------- Outputs ----------

output "vm_name" {
  value = libvirt_domain.nixvm.name
}

output "vm_id" {
  value = libvirt_domain.nixvm.id
}
