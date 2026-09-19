# 0017. Plane for Project Management

**Date:** 2026-09-19
**Status:** Accepted

## Context

The sovereign stack needs a self-hosted replacement for Linear / Jira / GitHub Projects for tracking work across projects. Key requirements:
- Issues, cycles (sprints), modules (epics), and roadmap views
- Accessible to non-technical users (non-developer stakeholders, SMB teams)
- Clean UI that doesn't require Atlassian-scale infrastructure
- No per-seat SaaS cost

The main alternatives evaluated:

| Option | Notes |
|--------|-------|
| **Plane** | Modern UI, active development, Linear-like UX, community edition available |
| **GitLab Issues** | Requires full GitLab stack; overkill for issue tracking alone |
| **Taiga** | Open source but slower development velocity, older UI |
| **Redmine** | Mature and stable, but dated UX |
| **OpenProject** | Enterprise-focused, complex setup, heavy resource footprint |

## Decision

Deploy **Plane community edition** in the `plane` namespace using the official `makeplane/plane-backend:stable` and `makeplane/plane-frontend:stable` images.

Stack:
- `makeplane/plane-frontend:stable` — Next.js web UI
- `makeplane/plane-backend:stable` — Django REST API
- `makeplane/plane-backend:stable` — Celery worker (background tasks)
- `makeplane/plane-backend:stable` — Celery beat (scheduled tasks)
- `postgres:15-alpine` — primary database
- `redis:7-alpine` — task queue and cache
- 5Gi PVC for PostgreSQL data
- 5Gi PVC for file attachments (local Django `MEDIA_ROOT`)

File attachments use Django's built-in file storage (`USE_MINIO=0`) rather than MinIO, which avoids an additional dependency. MinIO (planned for OpenTofu state) can be wired in later.

## Routing

Plane has a split ingress: the Next.js frontend handles most routes, while the Django API handles `/api/`, `/auth/`, `/static/`, and `/media/`. Ingress-nginx path rules route these to the correct service.

## Consequences

- Teams get a full issue tracker, kanban boards, cycles/sprints, and roadmap without a SaaS subscription
- Plane community edition is feature-rich but has some enterprise features (SAML, advanced analytics) gated behind the commercial plan
- The first registered user becomes the workspace owner — Plane does not ship with default credentials
- 4 deployments per namespace (api, worker, beat, frontend) is more operational surface area than other apps in the stack
- File attachments on local storage are node-affine (local-path) — upgrading to Longhorn enables shared PVC access

## Alternatives considered

**GitLab CE**: Full DevSecOps platform with issue tracking, CI/CD, and container registry. Significantly heavier (~4GB RAM minimum for all services) and overlaps with tooling already in the stack (ArgoCD for GitOps, local registry for images). Useful if the team needs integrated source control, not just issue tracking.

**Jira Software Cloud**: Zero operational overhead but $7.75+/seat/month and all project data in Atlassian's infrastructure. Contradicts the sovereignty goal.
