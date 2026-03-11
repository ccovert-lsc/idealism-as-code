#!/usr/bin/env bash
# Creates the ubuntu-2404-cloud template (VM 9000) on the local Proxmox node.
# Run this on EACH node that will host VMs cloned from the template.
# Requires: root shell on the Proxmox node (web UI → Node → Shell, or SSH as root)
#
# Usage: bash proxmox-create-ubuntu-template.sh [storage] [vm-id]
#   storage  defaults to local-lvm
#   vm-id    defaults to 9000
set -euo pipefail

STORAGE="${1:-local-lvm}"
VMID="${2:-9000}"
IMG=/tmp/ubuntu-2404-cloud.img
IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

echo "==> Creating ubuntu-2404-cloud template (VM $VMID) on storage $STORAGE"

if [ -f "$IMG" ]; then
  echo "==> Reusing cached image at $IMG"
else
  echo "==> Downloading Ubuntu 24.04 cloud image..."
  wget -q --show-progress "$IMG_URL" -O "$IMG"
fi

echo "==> Creating VM $VMID..."
qm create "$VMID" \
  --name ubuntu-2404-cloud \
  --memory 2048 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --ostype l26

echo "==> Importing disk to $STORAGE..."
qm importdisk "$VMID" "$IMG" "$STORAGE"

echo "==> Configuring VM..."
qm set "$VMID" \
  --scsi0 "${STORAGE}:vm-${VMID}-disk-0" \
  --ide2 "${STORAGE}:cloudinit,media=cdrom" \
  --boot c \
  --bootdisk scsi0 \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1

echo "==> Converting to template..."
qm template "$VMID"

echo "==> Done. Template ubuntu-2404-cloud (VM $VMID) is ready on $(hostname)."
