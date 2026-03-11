terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node
  tags      = var.tags

  clone {
    vm_id = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    full  = true
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = var.disk_size
  }

  dynamic "disk" {
    for_each = var.data_disk_gb > 0 ? [1] : []
    content {
      datastore_id = var.datastore
      interface    = "scsi1"
      size         = var.data_disk_gb
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  initialization {
    user_account {
      keys = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}

data "proxmox_virtual_environment_vms" "template" {
  node_name = var.node

  filter {
    name   = "name"
    values = [var.template]
  }
}
