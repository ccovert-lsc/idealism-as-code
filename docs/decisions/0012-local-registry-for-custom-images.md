# 0012. Local Container Registry for Custom-Built Images

**Date:** 2026-09-19
**Status:** Accepted

## Context

Some apps cannot be deployed from a public image — they require a custom build from source (either because no upstream image exists, or because local bug-fixes have not been merged upstream). Kubernetes needs to pull these images from somewhere.

Options:
- Public registry (Docker Hub, GHCR): requires pushing potentially modified/proprietary code publicly
- Private registry on a cloud service (Docker Hub private, GHCR private): requires credentials in k8s and an external dependency
- Local registry inside the cluster: self-contained, no external dependency

## Decision

Run a plain [Docker Registry v2](https://hub.docker.com/_/registry) inside the cluster at a MetalLB-assigned IP (`192.168.10.202:5000`). The registry is insecure (HTTP, no TLS) — it is LAN-only and never exposed via Cloudflare Tunnel.

All k3s nodes are configured to trust the registry via `/etc/rancher/k3s/registries.yaml` (set up by `scripts/setup-registry-argocd.sh`). Docker is installed on mgmt-01 for building images.

The build-and-push pattern is:
```bash
docker build -t 192.168.10.202:5000/appname:latest .
docker push 192.168.10.202:5000/appname:latest
kubectl rollout restart deployment/appname -n <namespace>
```

## Consequences

- Custom images are built and stored locally — no cloud dependency for the build pipeline.
- The registry PVC is node-bound (local-path storage). If the node hosting the registry is lost, images must be rebuilt. This is acceptable because the build source is always available on mgmt-01.
- HTTP (insecure) is intentional and limited to the LAN. Not appropriate if the registry were exposed externally.
- The registry uses a fixed MetalLB IP (`192.168.10.202`). This IP must not overlap with other LoadBalancer services.

## Alternatives considered

**GHCR (GitHub Container Registry) private:** Would work but requires pushing source code to GitHub. Rejected for apps with upstream contributions pending review — we don't want to publish modified code before the PR is merged.

**Gitea with built-in registry:** Adds a full git hosting layer for one feature we need. Overkill. Explicitly not adopted in this lab (see [0001](0001-repo-split-public-private.md) — we use GitHub intentionally).

**Build on mgmt-01 and `kubectl cp`:** Could copy image tarballs into the node, but there's no clean way to make kubelet use a tarball. Not viable.
