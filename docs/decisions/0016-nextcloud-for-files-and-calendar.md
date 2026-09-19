# 0016. Nextcloud for Files, Calendar, and Collaborative Documents

**Date:** 2026-09-19
**Status:** Accepted

## Context

The sovereign stack needs a self-hosted replacement for Google Drive / Google Docs / Google Calendar. Users should be able to:
- Store and share files without routing them through a commercial cloud provider
- Collaborate on documents in real time
- Manage calendars with CalDAV clients (iOS, Thunderbird)
- Access everything through a web UI and mobile apps

The main alternatives evaluated:

| Option | Notes |
|--------|-------|
| **Nextcloud** | Mature, active community, calendar/contacts/documents/talk, Collabora integration for live editing |
| **Seafile** | Excellent file sync performance, weaker document editing ecosystem |
| **ownCloud** | Forked by Nextcloud; community has largely migrated |
| **Gitea + MinIO** | Good for code + object storage, not a productivity suite |

## Decision

Deploy **Nextcloud** in the `nextcloud` namespace using the official Docker image and PostgreSQL as the backend database. Redis handles file locking and session caching. File storage uses a local-path PVC.

Stack:
- `nextcloud:latest` — main application (PHP + Apache)
- `postgres:16-alpine` — primary database
- `redis:7-alpine` — file locking and session cache (no persistence required)
- 50Gi PVC for Nextcloud data (code + user files)
- 5Gi PVC for PostgreSQL data

For collaborative document editing, the **Nextcloud Office** app (bundled Collabora CODE community edition) provides real-time co-editing of ODFX documents. This is installed post-deployment via the Nextcloud app store.

## Proxy configuration

Nextcloud requires explicit configuration for operation behind a reverse proxy (ingress-nginx + Cloudflare Tunnel). These settings are applied via `occ` post-install:

```bash
occ config:system:set trusted_proxies 0 --value='10.42.0.0/16'
occ config:system:set overwriteprotocol --value='https'
occ config:system:set overwritecliurl --value='https://nextcloud.<domain>'
occ config:system:set overwritehost --value='nextcloud.<domain>'
```

Without these, Nextcloud generates incorrect redirect URLs and rejects requests from the proxy.

## Consequences

- Files, calendar (CalDAV), and contacts (CardDAV) are self-hosted with no dependency on commercial providers
- Large file upload support (10GB limit via ingress-nginx annotation)
- Nextcloud Office enables collaborative document editing without a separate Collabora server
- Storage is capped by the local-path PVC; expanding requires Longhorn or NFS (planned)
- Nextcloud is PHP-based and heavier than purpose-built alternatives; 1Gi memory limit is appropriate

## Alternatives considered

**Collabora Online (standalone)**: Deploying a separate Collabora server gives more control over the document editing stack, but adds operational complexity. Nextcloud Office (embedded Collabora CODE) is sufficient for small community usage.

**Google Workspace / Microsoft 365**: Deferred the sovereignty benefit the rest of the stack delivers. These are the exact services this stack is designed to make unnecessary.
