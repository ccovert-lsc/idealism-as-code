# idealism-as-code

Canonical reference architecture patterns for a self-hosted platform lab.
Backing material for [blog content](https://yourblog.example) — every config here is real and inspectable.

## What's here

| Path | Purpose |
|------|---------|
| `docs/decisions/` | Architecture Decision Records — each one is a potential blog post |
| `modules/` | Reusable OpenTofu modules (no env-specific values) |
| `ansible/` | Roles and playbooks |
| `kubernetes/` | Platform manifests and app templates |
| `examples/` | Variable examples and inventory templates |

## What's not here

Real IPs, hostnames, secrets, or environment-specific values live in the private instantiation repo.
This repo contains variables and examples only.

## Using these modules

```hcl
module "vm" {
  source = "github.com/ccovert-lsc/idealism-as-code//modules/proxmox-vm?ref=v0.1.0"
  # ...
}
```

## Architecture Decisions

See [docs/decisions/](docs/decisions/) for ADRs.
