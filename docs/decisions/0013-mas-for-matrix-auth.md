# 0013. Matrix Authentication Service (MAS) for Matrix Token Management

**Date:** 2026-09-19
**Status:** Accepted

## Context

Synapse (the Matrix homeserver) historically handled all authentication internally. Since Synapse v1.13+, the experimental `msc3861` auth delegation mechanism was removed and replaced by a stable integration with [Matrix Authentication Service (MAS)](https://github.com/element-hq/matrix-authentication-service) — a separate Rust service that handles OAuth2/OIDC token issuance for Matrix clients.

MAS is required for:
- QR code device login (MSC4108)
- Modern OAuth2 token management (refresh tokens, token revocation)
- Delegating user authentication to an upstream OIDC provider (Authentik in our case)

Without MAS, Synapse on current `:latest` will fail to start with a config error.

## Decision

Deploy MAS (`ghcr.io/element-hq/matrix-authentication-service`) in a dedicated `matrix-auth` namespace alongside Synapse in the `synapse` namespace. MAS and Synapse share a secret (`mas_secret`) that Synapse uses to delegate authentication decisions to MAS.

**Critical architecture constraint:** MAS, Synapse, Element, and Authentik must be deployed together from the beginning. Adding MAS to an already-running Synapse causes DB state divergence and auth sequencing failures — existing Synapse users are unknown to MAS and the token namespace is incompatible. `scripts/setup-mas.sh` deploys both together; `scripts/teardown-matrix.sh` wipes both namespaces for a clean redeploy.

**Cloudflare TLS fingerprinting:** Synapse's internal Twisted HTTP client is blocked by Cloudflare when fetching MAS's OIDC discovery endpoint from the public URL. The `matrix_authentication_service.endpoint` in Synapse's config must use the internal cluster DNS (`http://mas.matrix-auth:8080/`) rather than the public hostname. The public hostname is used only by external Matrix clients.

The Synapse config block:
```yaml
matrix_authentication_service:
  enabled: true
  endpoint: http://mas.matrix-auth:8080/
  secret: "<shared secret>"

experimental_features:
  msc4108_enabled: true
```

## Consequences

- Modern Matrix features (QR login, token revocation) work out of the box.
- MAS and Synapse are tightly coupled — a breaking config change in either requires coordinated redeploy.
- Redeploy is destructive: `teardown-matrix.sh` + `setup-mas.sh` wipes all Synapse DB data and user accounts. Users must re-register.
- MAS ships fast. The `matrix_authentication_service` config schema changed between Synapse versions (deprecated `msc3861` fields removed). Always check Synapse release notes before upgrading.

## Alternatives considered

**Synapse with built-in auth (no MAS):** Supported on older Synapse versions but not on current `:latest`. The `experimental_features.msc3861` block was removed in v1.13. Not viable without pinning Synapse to an old version.

**Password-only auth (no OIDC upstream):** MAS supports local password authentication without an upstream IdP. Simpler but forfeits SSO — users would have separate credentials for Matrix vs. everything else.
