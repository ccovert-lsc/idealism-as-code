# 0011. ArgoCD as the GitOps Continuous Delivery Controller

**Date:** 2026-09-19
**Status:** Accepted

## Context

Once the cluster is provisioned and initial apps are deployed, subsequent changes to app config should go through git — not `kubectl apply` from a workstation. We wanted a GitOps controller that watches the repository and reconciles the cluster state to match.

Requirements:
- Watches a git repo and applies changes automatically on merge
- Has a UI for visualising what is deployed and its sync status
- Supports both Helm releases and raw manifests
- Can be bootstrapped via Helm (no chicken-and-egg problem)

## Decision

Deploy [ArgoCD](https://argoproj.github.io/cd/) via the official Helm chart (`argo/argo-cd`). ArgoCD watches the public `idealism-as-code` repository (reference manifests) and the private `lab-work` repository (overlays and values), reconciling each Application to the cluster.

ArgoCD is bootstrapped manually on first deploy (via `scripts/setup-registry-argocd.sh`) then manages itself via an ArgoCD Application pointing at its own Helm values.

ArgoCD is exposed publicly via Cloudflare Tunnel at `https://argocd.example.com` and gated behind Authentik SSO (OIDC).

**Note:** In the current deployment, several apps are still applied via `kubectl apply` scripts rather than ArgoCD Applications. Migrating all apps to ArgoCD-managed is a planned improvement.

## Consequences

- All config changes go through git and are auditable via git history.
- ArgoCD UI provides a live view of cluster state, sync status, and resource health.
- Self-hosted ArgoCD means the GitOps controller is inside the blast radius of a cluster failure — bootstrapping from scratch requires a manual `helm upgrade --install` step.
- SSO via Authentik means ArgoCD admin access requires Authentik to be healthy.

## Alternatives considered

**Flux:** Similar capabilities, more Kubernetes-native (CRD-first), but less polished UI. No strong technical reason to prefer one over the other; ArgoCD was chosen for familiarity and the richer web interface.

**GitHub Actions only:** CI/CD via GitHub Actions (self-hosted runner on mgmt-01) handles `tofu plan/apply`. Using Actions for `kubectl apply` too would work but creates a tighter coupling between the CI/CD system and the cluster — ArgoCD provides a cleaner separation of concerns.

**No GitOps:** Manual `kubectl apply` scripts. Simpler initially but loses the audit trail and drift detection. Rejected for anything beyond initial bootstrap.
