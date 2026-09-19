# 0009. Cloudflare Tunnel for Public Ingress

**Date:** 2026-09-19
**Status:** Accepted

## Context

The homelab needs to expose several services publicly (Matrix, Grafana, ArgoCD, Open WebUI, n8n, AuNoo) without relying on a static public IP. The lab is on a residential ISP that changes the external IP periodically, and the networking device (Eero mesh) does not support reliable port forwarding or DDNS with a clean API.

We needed a public ingress path that:
- Works without a static IP or open inbound ports
- Provides TLS termination
- Routes to the existing ingress-nginx LoadBalancer inside the cluster
- Has no ongoing cost for basic usage

## Decision

Use [Cloudflare Zero Trust Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (`cloudflared`). The `cloudflared` pod runs inside the cluster and dials outbound to Cloudflare's edge, establishing a persistent encrypted tunnel. Cloudflare routes inbound traffic for configured hostnames down the tunnel to the cluster's ingress-nginx (MetalLB IP).

DNS is managed in Cloudflare. Each hostname resolves to a Cloudflare anycast IP — the actual cluster IP is never exposed.

Routing is configured in Cloudflare Zero Trust → Networks → Tunnels → Public Hostnames. Each app gets a route like:

```
https://app.example.com → http://<ingress-nginx-ip>  (Host header: app.example.com)
```

The `Host` header override is required because ingress-nginx uses SNI/Host to route to the correct backend.

The `cloudflared` deployment runs in the `cloudflare` namespace and references the tunnel token from a k8s secret.

## Consequences

- No inbound firewall rules needed — all traffic is outbound from the cluster.
- TLS is handled by Cloudflare (valid cert, no cert-manager needed for public endpoints).
- The cluster can move to any network or ISP without any DNS/routing changes (just restart `cloudflared`).
- Cloudflare sits between clients and the cluster — Cloudflare can inspect unencrypted traffic (if using HTTP between Cloudflare and the cluster). Acceptable for a homelab.
- Some HTTP client libraries (Python urllib, Twisted) are blocked by Cloudflare's TLS fingerprinting. Internal cluster-to-cluster communication should use internal service DNS, not public hostnames.

## Alternatives considered

**Dynamic DNS (DDNS):** Would expose the real IP and require open inbound ports. Rejected due to ISP IP instability and Eero limitations.

**Tailscale Funnel:** Exposes nodes via Tailscale. Simpler for personal access but less flexible for public-facing apps and harder to share with others.

**VPS reverse proxy:** A cheap VPS runs nginx that proxies to the homelab via a WireGuard tunnel. Works, but adds a paid dependency and a node to maintain. Cloudflare Tunnel is free and simpler.
