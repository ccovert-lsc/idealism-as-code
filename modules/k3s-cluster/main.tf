# k3s cluster provisioning via null_resource + remote-exec
# In practice, use the Ansible role at ansible/roles/k3s/ for idempotent installs.
# This module documents the intent; the Ansible role is the implementation.

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Placeholder — actual provisioning handled by Ansible
# See ansible/roles/k3s/
resource "null_resource" "k3s_cluster" {
  triggers = {
    server_nodes = join(",", var.server_nodes)
    k3s_version  = var.k3s_version
  }
}
