# ADR 0004 — Proxmox VM templates are per-node artifacts

## Status
Accepted

## Context
The OpenTofu `proxmox-vm` module clones a named template to create each VM.
Proxmox supports two storage models:

- **Shared storage (Ceph, NFS, iSCSI)** — templates live once on shared storage
  and are visible to all nodes. Cloning across nodes works transparently.
- **Local storage (ZFS per node)** — each node has its own pool
  (`pvemainstorage`, `pvesub1storage`, `pvesub2storage`). Templates stored
  locally are not visible to other nodes.

This lab uses local ZFS per node. Attempting to clone a template cross-node
returns: `can't clone to non-shared storage`.

Additionally, Proxmox VM IDs are **cluster-global** — you cannot create VM 9000
on pvesub1 if VM 9000 already exists on pvemain.

## Decision
- Create the `ubuntu-2404-cloud` template independently on each node using a
  shared provisioning script (`scripts/proxmox-create-ubuntu-template.sh`).
- Assign unique IDs per node: **9000** (pvemain), **9001** (pvesub1), **9002**
  (pvesub2).
- The `proxmox-vm` module's data source filters by both template name **and**
  `node_name` so it resolves the correct template ID on each target node.

## Consequences
- Adding a new Proxmox node requires manually running the template script on that
  node before OpenTofu can provision VMs there.
- Template IDs must be documented and reserved to avoid collisions with regular
  VMs (we use 9000–9099 as the reserved template range).
- Shared storage (Ceph) would eliminate this constraint and is a natural next step
  if the cluster grows, but adds significant operational complexity for a homelab.
