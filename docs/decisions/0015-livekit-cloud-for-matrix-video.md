# 0015. LiveKit Cloud for Matrix Video Calls

**Date:** 2026-09-19
**Status:** Accepted

## Context

Element iOS (and modern Element clients generally) use **MatrixRTC** (MSC4143) for voice and video calls instead of the legacy peer-to-peer WebRTC stack. MatrixRTC requires a **LiveKit** SFU (Selective Forwarding Unit) — a server that routes media between call participants. Without it, calls fail immediately with `missing_matrix_rtc_transport`.

Self-hosting LiveKit on the homelab cluster has a fundamental problem: the SFU's media ports (UDP 50000-60000 and TCP 7881) must be publicly reachable, because the TURN relay needs to reach LiveKit to relay client media to it. The cluster sits behind a residential router with a changing external IP and no stable port forwarding. Cloudflare Tunnel handles HTTP/WebSocket but cannot proxy raw UDP — so a purely self-hosted solution would require either:

- A VPS with a stable public IP running LiveKit ($4-6/month), or
- Router port forwarding to the cluster combined with DDNS (fragile; breaks on ISP IP changes)

## Decision

Use [LiveKit Cloud](https://livekit.io/cloud) (free tier: 100 hours/month of SFU time) for the video media infrastructure. A self-hosted `lk-jwt-service` pod runs in the cluster, handling the Matrix ↔ LiveKit authentication bridge. Synapse advertises the lk-jwt-service URL in `/.well-known/matrix/client` via `extra_well_known_client_content`.

The data flow:
- **Signaling and room state**: Synapse (self-hosted) — no change
- **Identity and auth**: Authentik + MAS (self-hosted) — no change
- **Video/audio media streams**: Transit through LiveKit Cloud infrastructure during calls
- **JWT token issuance**: lk-jwt-service in the cluster, called by Element before each call

## Sovereignty trade-off

This is a deliberate, bounded exception to the self-hosted-everything principle. Video streams transit LiveKit's infrastructure (US-based, livekit.io) during active calls. Messages, room membership, user identity, and all persistent data remain on self-hosted infrastructure.

This is analogous to using Cloudflare Tunnel for ingress: a relay, not a content host. The trade-off is accepted because:
1. The technical alternative (VPS for LiveKit) adds ongoing cost and operational overhead
2. Video stream data is transient — it is not stored by LiveKit
3. The free tier is sufficient for homelab and small community usage

To restore full sovereignty: replace LiveKit Cloud with a self-hosted LiveKit instance on a $5/month VPS. The only config change required is the `LIVEKIT_URL`, `LIVEKIT_API_KEY`, and `LIVEKIT_API_SECRET` in the `livekit-credentials` k8s secret.

## Consequences

- iOS Element video calls work without any router configuration changes
- Free up to 100 hours/month of SFU time (sufficient for homelab/small community)
- Video streams transit an external service during active calls
- Adding a Cloudflare Tunnel route for `livekit-jwt.<domain>` is required

## Alternatives considered

**Self-hosted LiveKit on a VPS**: Full sovereignty, ~$5/month additional cost. The recommended path if data sovereignty for video streams is required. Swap requires only a secret update.

**Cloudflare TURN + self-hosted LiveKit**: Rejected — Cloudflare TURN can relay between a client and LiveKit, but only if it can reach LiveKit's UDP media ports. LiveKit behind NAT with no stable public IP is unreachable by the TURN relay.

**Eero port forwarding + DDNS**: Fragile — breaks whenever the ISP assigns a new external IP. Not suitable for a reliable platform.

**Legacy WebRTC (no LiveKit)**: Not viable — current Element clients use MatrixRTC by default and do not fall back gracefully to the legacy stack.
