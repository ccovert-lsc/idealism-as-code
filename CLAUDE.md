# CLAUDE.md

Context for AI assistants working with this repository. Read this before making any suggestions or changes.

## What this repository is

Public reference architecture for a self-hosted platform lab. It contains OpenTofu modules, Ansible roles, Kubernetes manifests, operational scripts, and Architecture Decision Records (ADRs) documenting every significant decision made along the way.

This is the **reference repo** — it contains patterns and sanitized examples only. A separate private repo holds real IPs, hostnames, SOPS-encrypted secrets, and environment-specific values. Scripts in `scripts/` use `<placeholder>` markers where you need to substitute your own values.

## Architecture layers

```
Physical:   Proxmox cluster (1 primary node + N secondary nodes)
VMs:        1 management VM  +  1 k3s server  +  N k3s agent nodes
k3s:        MetalLB (LoadBalancer IPs)  +  ingress-nginx  +  local-path storage
Platform:   ArgoCD · Authentik · kube-prometheus-stack
Apps:       Synapse+MAS+Element · n8n · Ollama+Open WebUI · cloudflared · custom apps
```

The management VM is the control plane for everything — it runs OpenTofu, Ansible, kubectl, Helm, SOPS, and Docker for building custom images. All scripts are designed to run from there.

## Deployment sequence

Order matters here. Do not skip steps.

1. **Proxmox templates** — run `scripts/proxmox-create-ubuntu-template.sh` on each Proxmox node
2. **Provision VMs** — OpenTofu from the management VM (`tofu apply`)
3. **Install k3s** — Ansible roles (server first, then agents)
4. **Platform bootstrap** — local registry + ArgoCD (`scripts/setup-registry-argocd.sh`)
5. **Identity** — Authentik (`scripts/setup-authentik.sh`)
6. **Public ingress** — Cloudflare Tunnel deployment
7. **Applications** — deploy coupled apps together (see constraints below)
8. **SSO wiring** — after apps are running (`scripts/setup-sso.sh`)

## Critical coupling constraints

**Synapse + MAS must be deployed together from day one.**
MAS handles all OAuth2/OIDC token issuance for Synapse. Adding MAS to an already-running Synapse causes database state divergence and auth sequencing failures — existing Synapse users are unknown to MAS. Always use `scripts/setup-mas.sh` (deploys both) and `scripts/teardown-matrix.sh` (wipes both cleanly). Never try to bolt MAS onto a running Synapse.

**Synapse must reach MAS via internal cluster DNS, not the public hostname.**
Cloudflare's TLS fingerprinting blocks Synapse's Twisted HTTP client. The `matrix_authentication_service.endpoint` in Synapse config must be the internal service address (e.g. `http://mas.matrix-auth:8080/`), not `https://matrix-auth.example.com`. This applies to any internal service-to-service call that would otherwise traverse Cloudflare.

**Authentik major version upgrades are sequential — no skips allowed.**
Authentik enforces that you upgrade one major release at a time (e.g. 2026.2.x → 2026.4.x → 2026.6.x). Running `helm upgrade` directly to the latest version across multiple majors will fail with an explicit error. Check `helm list -n authentik` before upgrading and pin `--version` to the next intermediate release if needed.

## Secret management rules

- Secrets are generated at runtime by scripts (`openssl rand`) — never hardcoded in manifests or scripts
- Always use `kubectl create secret --from-file` (not `--from-literal`) — `--from-literal` with shell variables can produce 0-byte secrets if the variable contains special characters or is empty
- The idempotent pattern: `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`
- In the private repo, secrets at rest use SOPS + age encryption (see ADR-0008)

## Storage model

The cluster uses `local-path` storage. PVCs are node-affine — they are pinned to the node where they were first provisioned and cannot be moved. If a node running a stateful workload is permanently lost, the PVC data on that node is unrecoverable. Plan accordingly: store only recoverable state on local-path PVCs, or accept that some apps will need reseeding after a node loss.

## Kubernetes manifest patterns

- Secrets injected at runtime via init containers (`patch-config` busybox pattern using `sed`) rather than mounted directly where the app doesn't support env-var substitution
- `imagePullPolicy: Always` on `:latest` tags — rollout restarts pull fresh images
- Ingress via ingress-nginx; all external traffic enters through Cloudflare Tunnel (no NodePort or direct LoadBalancer exposure externally)

## Script conventions

All scripts in `scripts/`:
- Export `KUBECONFIG` explicitly at the top — do not rely on `.bashrc` (non-interactive SSH sessions don't source it)
- Read sensitive values from k8s secrets at runtime via `kubectl get secret ... | base64 -d`
- Accept cluster-specific config as variables at the top of the file, marked with a comment
- Are safe to re-run (idempotent secret creation, `--dry-run=client` pattern)

## Known gotchas — read before suggesting changes

- **Proxmox bpg provider + SSH key changes**: adding keys to an existing VM triggers an `ide2` hotplug error; use `-target` to skip the management VM on re-applies that only touch k3s nodes
- **Authentik worker OOM**: the worker needs at least 1.5Gi memory limit; 512Mi causes OOMKilled under normal load
- **Synapse config schema (v1.13+)**: the `experimental_features.msc3861` block is removed; use `matrix_authentication_service` with only `enabled`, `endpoint`, and `secret` fields — the old `issuer`, `client_id`, `client_auth_method`, `client_secret`, `admin_token` fields no longer exist
- **Authentik 2026.8+ Rust config parser**: rejects CIDR notation in `trusted_proxy_cidrs`; use `listen: {}` instead
- **MAS signing keys**: RSA + EC keys are required for JWT token signing; without them MAS serves web sessions but `/oauth2/token` returns signing errors — always generate and store keys in the `mas-config` secret
- **k3s + ungraceful shutdown**: k3s SQLite handles hard shutdowns cleanly; nodes come back healthy after power loss without manual intervention
- **local-path PVC affinity**: pods with local-path PVCs must reschedule to the same node; if that node is down, the pod will stay Pending until the node recovers

## ADRs

Every major architectural decision has an ADR in `docs/decisions/`. Before suggesting an alternative approach for anything covered there, read the relevant ADR — the decision, trade-offs, and rejected alternatives are documented. New decisions should get an ADR.

## App upgrade process

See `scripts/upgrade-apps.sh` and ADR-0007. The order is fixed: Helm apps first (ArgoCD → kube-prometheus-stack → Authentik), then low-risk manifest apps, then Synapse+MAS last. Synapse and MAS are restarted last because breaking config changes in either are most likely to surface on a new image pull.

## Runbooks

Common operational tasks are documented in `docs/runbooks/`:
- `add-matrix-user.md` — registering new Matrix/Synapse users
- `rotate-secrets.md` — rotating credentials for each app
- `pull-ollama-model.md` — adding AI models to Ollama
- `recover-k3s-node.md` — bringing a node back after hard shutdown or hardware failure
