# ADR 0002 — k3s as the cluster runtime

## Status
Accepted

## Context
We need a Kubernetes distribution to run workloads on bare-metal VMs provisioned
by OpenTofu on Proxmox. Options considered:

- **Full upstream Kubernetes (kubeadm)** — maximum control, but high operational
  overhead for a homelab; requires separate etcd, load balancer, and CNI setup.
- **k0s** — lightweight, single-binary, similar to k3s.
- **MicroK8s** — Canonical-managed snap package; opinionated snap packaging is
  harder to automate cleanly with Ansible.
- **k3s** — CNCF-certified, single-binary, ships with containerd, flannel (CNI),
  CoreDNS, and a local-path provisioner. Designed for exactly this use case.

## Decision
Use **k3s** installed via the official install script, managed by a custom Ansible
role. Deploy with:

- `--disable traefik` — we will use ingress-nginx instead
- `--disable servicelb` — we will use MetalLB for LoadBalancer IPs
- `--write-kubeconfig-mode 644` — allows the ubuntu user on the server node to
  read the kubeconfig without sudo

The Ansible role runs the server play first, captures the node token via
`set_fact`, then passes it to agent nodes through `hostvars` in a second play.

## Consequences
- Single-binary install is fast (~12s per node in practice) and idempotent via
  the `creates:` guard on the shell task.
- k3s manages its own systemd units; no manual service files needed.
- Upgrading k3s means re-running the install script with a new channel/version —
  the Ansible role supports this by removing the `creates:` guard.
- Flannel (VXLAN) is the CNI. If we need NetworkPolicy enforcement later we can
  swap to Calico or Cilium, but flannel is sufficient for the current workloads.
