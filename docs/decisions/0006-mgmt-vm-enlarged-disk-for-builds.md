# 0006. Enlarged Management VM Disk for Container Builds

**Date:** 2026-03-14
**Status:** Accepted

## Context

The management VM (mgmt-01) serves as both the control plane (running OpenTofu, Ansible, kubectl) and the build host for container images destined for the local registry. Building projects from source — particularly Python-heavy applications with compiled dependencies (numpy, hdbscan, torch) and Node.js frontends — requires substantial temporary disk space for Docker layer cache, intermediate build artifacts, and the final image before it is pushed.

The default OS disk size of 20GB proved insufficient: builds would succeed through all compilation steps but fail at the final image extraction stage with "no space left on device". Swap was added as a workaround for OOM kills during `npm run build`, but disk capacity remained the binding constraint.

## Decision

Expand the mgmt-01 OS disk from 20GB to 60GB and record this as the baseline in the Tofu module invocation (`disk_size = 60`). The partition and filesystem were grown online without downtime using `growpart` and `resize2fs`.

## Consequences

- Container builds from source complete reliably without manual disk management between runs.
- `docker system prune` is still recommended after each build cycle to avoid accumulation of intermediate layers; the enlarged disk provides headroom, not a permanent cache store.
- The Tofu state reflects the actual disk size; future `tofu apply` runs will not attempt to shrink the disk.
- Swap (4GB swapfile) remains enabled on mgmt-01 to handle peak memory pressure during large frontend builds.

## Alternatives considered

- **Build on a k3s agent node (16GB RAM, larger disk):** Would require Docker on agent nodes and complicates the push-to-registry workflow. mgmt-01 is the natural build host given it already has Docker and direct registry access.
- **Use `docker buildx build --push` to avoid local image storage:** Adopted as a technique within the build workflow (streams the finished image directly to the registry, saving ~3GB of local extraction space), but not a substitute for sufficient disk since layer cache still accumulates during the build.
- **Remote build (GitHub Actions, external CI):** Adds latency, requires registry exposure, and defeats the purpose of a self-contained homelab build pipeline.
