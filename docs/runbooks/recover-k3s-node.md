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
   - `pvesub1`: k3s-agent-01 (VM 103)
   - `pvesub2`: k3s-agent-02 (VM 104)

## Notes

- k3s VMs use static IPs configured in `/etc/netplan/`. The IP will not change on reboot.
- After a hard shutdown (power loss), the k3s database may have uncommitted transactions. k3s (SQLite-backed in single-server mode) handles this automatically on restart.
- If the k3s server node (control plane) is lost, agent nodes will show `NotReady` until the server is back — they cannot self-heal without the control plane.
