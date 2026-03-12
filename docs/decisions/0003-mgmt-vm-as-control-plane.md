# ADR 0003 — mgmt-01 as the infrastructure control plane

## Status
Accepted

## Context
OpenTofu and Ansible need to run somewhere. Options:

- **Developer workstation / laptop** — simple to start, but ties infra operations
  to a specific machine and OS. Secrets, state, and tool versions drift across
  machines.
- **GitHub Actions cloud runners** — stateless, but cloud runners cannot reach
  private network resources (Proxmox API at 192.168.10.20, k3s nodes) without a
  VPN or tunnel.
- **Dedicated management VM inside the cluster network** — runs on Proxmox
  alongside the workload VMs, has direct network access to all targets, holds the
  age key and tfstate locally, and mirrors how a real production environment
  separates the control plane from developer machines.

## Decision
Provision a small VM (**mgmt-01**, 192.168.10.30, 2 vCPU / 2 GB) on pvemain.
This VM:

- Runs all `tofu` and `ansible-playbook` invocations
- Holds the SOPS age key at `~/.config/sops/age/keys.txt`
- Holds tfstate at `~/lab-work/tofu/proxmox/terraform.tfstate` (pending Minio
  backend migration)
- Runs the **self-hosted GitHub Actions runner**, receiving jobs from GitHub and
  executing them with full access to the private network

The runner makes an outbound-only connection to GitHub — no inbound firewall
rules required. This allows CI/CD to trigger on PR/push events from anywhere
while the actual execution happens inside the home network.

## Consequences
- First-time bootstrap still requires running `tofu apply` from a workstation
  (chicken-and-egg: mgmt-01 doesn't exist yet). After bootstrap, all subsequent
  operations run from mgmt-01 via CI/CD or SSH.
- tfstate is local to mgmt-01 until Minio is deployed. Manual `scp` sync is
  needed for recovery if mgmt-01 is lost. This is a known gap tracked for
  remediation when Minio is stood up.
- mgmt-01's SSH key must be included in `ssh_public_keys` in `terraform.tfvars`
  so Ansible can reach all other VMs it provisions.
