variable "server_nodes" {
  description = "List of server node IP addresses"
  type        = list(string)
}

variable "agent_nodes" {
  description = "List of agent node IP addresses"
  type        = list(string)
  default     = []
}

variable "k3s_version" {
  description = "k3s version to install (e.g. 'v1.31.0+k3s1')"
  type        = string
  default     = "stable"
}

variable "cluster_name" {
  description = "Cluster name used for kubeconfig context"
  type        = string
}

variable "disable_components" {
  description = "k3s components to disable (e.g. ['traefik', 'servicelb'])"
  type        = list(string)
  default     = ["traefik", "servicelb"]
}
