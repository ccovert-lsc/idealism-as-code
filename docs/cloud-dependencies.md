# Cloud Service Dependencies

External services this architecture depends on. Credentials should be stored encrypted (see ADR-0008).

| Service | Purpose | Free tier | Notes |
|---|---|---|---|
| Tailscale | VPN / off-LAN access to mgmt-01 | Yes (up to 3 users, 100 devices) | mgmt-01 registers via `tailscale up`; auth via tailscale.com |
| Cloudflare | DNS + Zero Trust Tunnel for public endpoints | Yes (Tunnel + DNS are free) | Routes `*.example.com` → ingress-nginx; see ADR-0009 |
| LiveKit Cloud | SFU media relay for Matrix video calls | Yes (100 hrs/month) | Video streams transit LiveKit during calls; see ADR-0015 |
| Anthropic API | LLM provider for AI workloads | No (pay-per-token) | Used by apps calling Claude models |

## Optional (enable per-app)

| Service | Purpose | Free tier | Notes |
|---|---|---|---|
| NewsAPI | News ingestion (for AI/research apps) | Yes (developer: 100 req/day) | newsapi.org |
| Firecrawl | Web scraping (for AI/research apps) | Yes (limited) | firecrawl.dev |

## Public endpoints pattern

With Cloudflare Tunnel, each app gets a hostname routed via the tunnel — no public IP, no open inbound ports. Example layout:

| App | Example URL |
|-----|-------------|
| Authentik (SSO) | https://id.example.com |
| ArgoCD | https://argocd.example.com |
| Grafana | https://grafana.example.com |
| Matrix (Synapse) | https://matrix.example.com |
| Matrix Auth (MAS) | https://matrix-auth.example.com |
| LiveKit JWT bridge | https://livekit-jwt.example.com |
| n8n | https://n8n.example.com |
| Open WebUI (Ollama) | https://ai.example.com |
| Nextcloud | https://nextcloud.example.com |
| Plane | https://plane.example.com |

## Planned / not yet adopted

| Service | Purpose | Status |
|---|---|---|
| Let's Encrypt (cert-manager) | Self-managed TLS (replacing Cloudflare-managed) | Planned |
| S3-compatible storage (Minio) | OpenTofu remote state backend | Planned |

## Notes

- Cloudflare Tunnel requires no inbound firewall rules — the `cloudflared` pod dials out
- Tailscale free tier covers a single-operator homelab indefinitely
- All cloud credentials should be encrypted at rest via SOPS + age (see ADR-0008) in the private repo
