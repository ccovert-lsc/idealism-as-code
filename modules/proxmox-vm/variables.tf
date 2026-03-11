variable "name" {
  description = "VM name"
  type        = string
}

variable "node" {
  description = "Proxmox node to place the VM on"
  type        = string
}

variable "template" {
  description = "VM template to clone from"
  type        = string
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in megabytes"
  type        = number
  default     = 2048
}

variable "datastore" {
  description = "Proxmox datastore for VM disk (e.g. 'local-lvm', 'pvemainstorage')"
  type        = string
}

variable "disk_size" {
  description = "Disk size in gigabytes"
  type        = number
  default     = 20
}

variable "network_bridge" {
  description = "Network bridge (e.g. 'vmbr0')"
  type        = string
  default     = "vmbr0"
}

variable "ip_address" {
  description = "IP address in CIDR notation (e.g. '192.168.1.10/24') or 'dhcp'"
  type        = string
  default     = "dhcp"
}

variable "gateway" {
  description = "Default gateway IP (e.g. '192.168.1.1')"
  type        = string
  default     = null
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "data_disk_gb" {
  description = "Size of optional second data disk in gigabytes (0 = no data disk)"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Proxmox tags to apply"
  type        = list(string)
  default     = []
}
