# idealism-as-code

Canonical reference architecture patterns for a self-hosted platform lab.
Backing material for blog content — every config here is real and inspectable.

## What's here

| Path | Purpose |
|------|---------|
| `docs/decisions/` | Architecture Decision Records (ADRs 0001–0014) — each one is a potential blog post |
| `docs/runbooks/` | Operational runbooks for common tasks |
| `docs/cloud-dependencies.md` | External service inventory |
| `modules/` | Reusable OpenTofu modules (no env-specific values) |
| `ansible/` | Roles and playbooks |
| `kubernetes/` | Platform manifests and app templates |
| `scripts/` | Setup and operational scripts (sanitized — replace `<placeholders>` with your values) |
| `examples/` | Variable examples and inventory templates |

## What's not here

Real IPs, hostnames, secrets, or environment-specific values live in the private instantiation repo.
This repo contains reference patterns only.

## Using these modules

```hcl
module "vm" {
  source = "github.com/ccovert-lsc/idealism-as-code//modules/proxmox-vm?ref=v0.1.0"
  # ...
}
```

## Architecture Decisions

See [docs/decisions/](docs/decisions/) for the full ADR log.

| ADR | Topic |
|-----|-------|
| [0001](docs/decisions/0001-repo-split-public-private.md) | Repo split: public reference + private instantiation |
| [0002](docs/decisions/0002-k3s-as-cluster-runtime.md) | k3s as cluster runtime |
| [0003](docs/decisions/0003-mgmt-vm-as-control-plane.md) | Dedicated mgmt VM as control plane |
| [0004](docs/decisions/0004-proxmox-template-per-node.md) | Proxmox VM template per physical node |
| [0005](docs/decisions/0005-cicd-self-hosted-runner.md) | Self-hosted GitHub Actions runner |
| [0006](docs/decisions/0006-mgmt-vm-enlarged-disk-for-builds.md) | Enlarged mgmt VM disk for container builds |
| [0007](docs/decisions/0007-app-upgrade-process.md) | App upgrade process |
| [0008](docs/decisions/0008-sops-age-for-secrets.md) | SOPS + age for secret management |
| [0009](docs/decisions/0009-cloudflare-tunnel-for-ingress.md) | Cloudflare Tunnel for public ingress |
| [0010](docs/decisions/0010-authentik-as-sso-provider.md) | Authentik as SSO identity provider |
| [0011](docs/decisions/0011-argocd-as-gitops-controller.md) | ArgoCD as GitOps controller |
| [0012](docs/decisions/0012-local-registry-for-custom-images.md) | Local container registry for custom images |
| [0013](docs/decisions/0013-mas-for-matrix-auth.md) | Matrix Authentication Service (MAS) |
| [0014](docs/decisions/0014-kube-prometheus-stack-for-observability.md) | kube-prometheus-stack for observability |
