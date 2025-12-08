# k3s Cluster VMs on Proxmox
# Uses VMs (not LXC) for full k3s compatibility

terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 3.0"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

# Variables
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  default     = "https://172.16.1.2:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID"
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

# Node definitions
locals {
  k3s_nodes = {
    "k3s-cp-1" = {
      vmid        = 300
      node        = "pve1"
      ip          = "172.16.1.50"
      cores       = 4
      memory      = 8192
      disk_size   = "50G"
      description = "k3s control plane 1"
    }
    "k3s-cp-2" = {
      vmid        = 301
      node        = "pve2"
      ip          = "172.16.1.51"
      cores       = 4
      memory      = 8192
      disk_size   = "50G"
      description = "k3s control plane 2"
    }
    "k3s-worker-1" = {
      vmid        = 302
      node        = "pve1"
      ip          = "172.16.1.52"
      cores       = 8
      memory      = 16384
      disk_size   = "100G"
      description = "k3s worker 1"
    }
    "k3s-worker-2" = {
      vmid        = 303
      node        = "pve2"
      ip          = "172.16.1.53"
      cores       = 8
      memory      = 16384
      disk_size   = "100G"
      description = "k3s worker 2"
    }
  }
}

# k3s VMs
resource "proxmox_vm_qemu" "k3s_node" {
  for_each = local.k3s_nodes

  name        = each.key
  vmid        = each.value.vmid
  target_node = each.value.node
  desc        = each.value.description

  # Clone from template (adjust template name to match your setup)
  clone      = "ubuntu-2404-template"
  full_clone = true

  # Hardware
  cores   = each.value.cores
  sockets = 1
  memory  = each.value.memory
  cpu     = "host"
  scsihw  = "virtio-scsi-single"
  agent   = 1

  # Boot disk
  disks {
    scsi {
      scsi0 {
        disk {
          size    = each.value.disk_size
          storage = "vm-storage"
        }
      }
    }
  }

  # Network
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init
  os_type    = "cloud-init"
  ciuser     = "root"
  cipassword = null
  sshkeys    = var.ssh_public_key
  ipconfig0  = "ip=${each.value.ip}/24,gw=172.16.1.1"
  nameserver = "172.16.1.11"

  # Boot settings
  onboot   = true
  oncreate = true

  # Tags
  tags = "k3s,kubernetes"

  lifecycle {
    ignore_changes = [
      network,
      clone,
      full_clone,
    ]
  }
}

# Outputs
output "k3s_nodes" {
  value = {
    for name, node in proxmox_vm_qemu.k3s_node : name => {
      vmid = node.vmid
      ip   = local.k3s_nodes[name].ip
      node = local.k3s_nodes[name].node
    }
  }
}

output "control_plane_ips" {
  value = [
    local.k3s_nodes["k3s-cp-1"].ip,
    local.k3s_nodes["k3s-cp-2"].ip,
  ]
}

output "worker_ips" {
  value = [
    local.k3s_nodes["k3s-worker-1"].ip,
    local.k3s_nodes["k3s-worker-2"].ip,
  ]
}
