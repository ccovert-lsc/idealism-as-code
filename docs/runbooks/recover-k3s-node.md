# Runbook: Recover a k3s Node

## When to use

- A node is `NotReady` in `kubectl get nodes`
- A node is unreachable via SSH
- A node was hard-shutdown (power loss, physical move)

## 1 — Verify network connectivity

```bash
ping 192.168.10.XX   # replace with node IP
ssh ubuntu@192.168.10.XX
```

If ping fails:
- Check the physical machine is powered on
- Check the NIC cable is seated (applies to desktop/server nodes)
- Check that the LAN subnet matches the node's static IP (especially after a network change)

If SSH host key mismatch (`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`):
```bash
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.10.XX
ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.XX
```

## 2 — Check k3s service on the node

```bash
# On the node via SSH:
sudo systemctl status k3s         # server node
sudo systemctl status k3s-agent   # agent node

# Restart if needed:
sudo systemctl restart k3s
sudo systemctl restart k3s-agent
```

## 3 — Check cluster node status from mgmt-01

```bash
export KUBECONFIG=/home/ubuntu/.kube/lab.yaml
kubectl get nodes -o wide
```

Nodes may take 2–3 minutes to transition from `NotReady` to `Ready` after k3s restarts.

## 4 — Check workload pods after node recovery

```bash
kubectl get pods -A -o wide | grep -v Running | grep -v Completed
```

Pods on the recovered node may be in `Terminating` or `Pending` state while k8s reschedules them. This usually resolves within a few minutes without manual intervention.

If pods are stuck in `Terminating` for more than 5 minutes:
```bash
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
```

## 5 — local-path PVC affinity

**Important:** This cluster uses `local-path` storage. PVCs are pinned to the node where they were first provisioned. If a node is permanently lost, any PVC that lived on that node cannot be recovered — the data is gone.

Apps affected: check which node hosts each PVC:
```bash
kubectl get pvc -A -o wide
kubectl get pv -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],CLAIM:.spec.claimRef.name'
```

If a node with a PVC comes back online, the PVC is automatically re-attached when the pod reschedules to that node.

## 6 — Proxmox node recovery

If the underlying Proxmox host is unreachable (not just the k3s VM):

1. Access the Proxmox web UI for the other nodes to verify cluster quorum
2. Check the physical host is powered on
3. Access the Proxmox host via a direct console (HDMI + keyboard) if SSH is unavailable
4. After the Proxmox host is back, start the VM from the Proxmox UI:
   - `pvemain`: k3s-server-01 (VM 102)
   - `pvesub1`: k3s-agent-01 (VM 104)
   - `pvesub2`: k3s-agent-02 (VM 103)

## 7 — Storage-level failure on the Proxmox host (ZFS / NVMe)

A node can also fail at the storage layer while the VM itself looks fine at first — the VM freezes mid-operation (kubelet `PLEG` stops posting, `qm start`/`qm reset` hang), and the real problem is on the Proxmox host, not in the guest.

**Signatures seen in practice:**
- `zpool status -v` on the host reports the pool `SUSPENDED` (I/O timeout, device unresponsive) — `smartctl` can't even read the controller, but `lspci` still shows the device. This is a wedged-firmware state, not necessarily dead hardware.
- A harder failure: the device disappears from the PCIe bus entirely (absent from `lspci`, never probed in `dmesg`). `zpool import -D` finds nothing at all, which looks catastrophic but is not necessarily unrecoverable.

**The fix that actually works — and the one that doesn't:**
A software/OS-level reboot (`systemctl reboot`, including the Proxmox UI's "Reboot" button) does **not** reliably force full PCIe re-enumeration on consumer-grade hardware. It can leave a wedged NVMe controller exactly as wedged as before. What does work is a true cold power-off — full de-energization, not a warm restart:

```bash
# From the Proxmox host's own shell (console or SSH):
rtcwake -m off -s 300   # powers off, wakes itself after 300s — adjust as needed
```

Confirmed twice on this cluster's hardware (a DRAM-less MAXIO NVMe controller known to wedge under sustained write load): a soft reboot did nothing, `rtcwake`'s true power-off brought the pool back `ONLINE` immediately. Treat "reboot" and "power-cycle" as different operations on this hardware, not synonyms.

**Reaching the Proxmox web UI with no LAN/IPMI access** (e.g. travelling, only Tailscale available): tunnel through any host that's already reachable over Tailscale and has a route to the Proxmox management network —
```bash
ssh -L 8006:<proxmox-host-ip>:8006 ubuntu@<tailscale-ip-of-some-other-reachable-host>
```
then browse `https://localhost:8006`. No inbound port needs to be opened on the home network, and it works entirely over an already-authenticated Tailscale session — safer and simpler than a router-level port-forward to the WAN.

**Longer-term:** a single non-redundant or partially-understood disk is a real risk, not just an inconvenience — if a drive fails outright rather than just wedging, there is no copy. Mirroring and/or off-node backups for anything stored on `local-path` PVCs is the real fix; a power-cycle is a recovery tactic for a flaky drive, not a substitute for redundancy.

## Notes

- k3s VMs use static IPs configured in `/etc/netplan/`. The IP will not change on reboot.
- After a hard shutdown (power loss), the k3s database may have uncommitted transactions. k3s (SQLite-backed in single-server mode) handles this automatically on restart.
- If the k3s server node (control plane) is lost, agent nodes will show `NotReady` until the server is back — they cannot self-heal without the control plane.
