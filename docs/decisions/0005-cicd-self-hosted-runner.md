# ADR 0005 — Self-hosted GitHub Actions runner for IaC CI/CD

## Status
Accepted

## Context
We want PRs against the private `lab-work` repo to automatically run
`tofu plan` and post the output as a PR comment, with `tofu apply` running on
merge to main. The challenge: OpenTofu must reach the Proxmox API
(`https://192.168.10.20:8006`) which is on a private LAN — inaccessible to
GitHub-hosted runners without a VPN or tunnel.

Options:

- **GitHub-hosted runners + Tailscale/Cloudflare Tunnel** — cloud runner dials
  into the home network via VPN. Adds an always-on tunneling dependency.
- **Gitea + Woodpecker CI** — fully self-hosted CI, but requires k3s to already
  be running (circular dependency at bootstrap time).
- **Self-hosted GitHub Actions runner on mgmt-01** — the runner process on
  mgmt-01 makes an outbound HTTPS connection to GitHub's job queue. No inbound
  ports, no VPN. GitHub queues jobs; mgmt-01 polls and executes them from inside
  the network.

## Decision
Register a **self-hosted GitHub Actions runner** on mgmt-01, scoped to the
`ccovert-lsc/lab-work` repository.

Workflow design:
- `tofu-plan.yml` — triggers on `pull_request` for paths `tofu/**`; posts plan
  output as a PR comment via `actions/github-script`.
- `tofu-apply.yml` — triggers on `push` to `main` for paths `tofu/**`; runs
  `tofu apply -auto-approve`. Gated by a `production` environment for optional
  manual approval.

Authentication: `actions/checkout` uses a fine-grained PAT (`RUNNER_GH_TOKEN`
secret) with read-only `Contents` access to `lab-work`. The SOPS age key on
mgmt-01 decrypts the Proxmox password at runtime — no secrets are stored in
GitHub beyond the PAT and the encrypted SOPS file.

## Consequences
- The runner is a single point of failure: if mgmt-01 is down, CI/CD is
  unavailable. Acceptable for a homelab; mitigated by the fact that `tofu apply`
  can also be run manually from mgmt-01.
- The `idealism-as-code` (public) repo uses GitHub-hosted runners for module
  validation only — no private network access required there.
- When Gitea is deployed, the runner registration can be migrated to the
  self-hosted Gitea instance to fully close the GitOps loop.
