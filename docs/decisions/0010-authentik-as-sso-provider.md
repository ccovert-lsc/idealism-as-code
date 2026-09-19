# 0010. Authentik as the SSO Identity Provider

**Date:** 2026-09-19
**Status:** Accepted

## Context

Several cluster apps benefit from single sign-on: Grafana, ArgoCD, Open WebUI, and the Matrix Authentication Service (MAS) all support OIDC. Without SSO, each app maintains its own user database with separate passwords — a fragile pattern for a multi-app homelab.

We needed an identity provider that:
- Runs self-hosted inside the cluster (no cloud IdP dependency)
- Supports OIDC/OAuth2 as a provider (for apps to consume)
- Supports OIDC as an upstream (to delegate to external IdPs if wanted)
- Has a usable admin UI for a non-enterprise environment

## Decision

Deploy [Authentik](https://goauthentik.io/) via the official Helm chart (`goauthentik/authentik`). Authentik acts as the OIDC provider for Grafana, ArgoCD, Open WebUI, and MAS. It stores users in its own PostgreSQL database (also Helm-managed).

Each app gets a confidential OIDC client created in Authentik (Admin → Applications → Providers). The client ID and secret are passed to each app via a k8s secret — scripts in `scripts/setup-authentik.sh` and `scripts/setup-sso.sh` automate the wiring.

Authentik itself is exposed publicly via Cloudflare Tunnel at `https://id.example.com`.

**Upgrade constraint:** Authentik blocks upgrades that skip a major version. The upgrade path is sequential: e.g. 2026.2.x → 2026.4.x → 2026.6.x → 2026.8.x. See `scripts/upgrade-apps.sh` for the procedure.

## Consequences

- One login for Grafana, ArgoCD, Open WebUI (and Matrix via MAS).
- Authentik is a relatively complex app (server + worker + PostgreSQL + Redis). It is the most resource-intensive app in the cluster after Ollama.
- If Authentik is down, SSO-gated apps fall back to local credentials — they are not fully unavailable.
- Worker OOM is a known risk; the worker memory limit should be set to at least 1.5Gi (see `authentik-values.yaml`).
- Sequential upgrade requirement means upgrades need planning — cannot just `helm upgrade` to latest blindly.

## Alternatives considered

**Keycloak:** More mature, more battle-tested in enterprise contexts. Heavier resource footprint and more complex configuration for a homelab. Rejected in favour of Authentik's simpler UI.

**Dex:** Lightweight OIDC bridge. Good for Kubernetes-native auth (kubectl OIDC) but minimal admin UI and no user management. Rejected because we wanted a proper IdP with user/group management.

**No SSO (per-app auth):** Simplest option but creates N separate user databases. Rejected because managing passwords per-app at homelab scale is worse than running one IdP.
