# 0007. App Upgrade Process

**Date:** 2026-09-19
**Status:** Accepted

## Context

The cluster runs a mix of Helm-managed and manifest-managed applications. Without a repeatable upgrade procedure, apps accumulate drift: image tags stagnate, chart versions fall behind, and the sequence that matters (especially for Authentik and Synapse+MAS) gets forgotten between upgrade cycles.

We needed an upgrade script that:
- Can be committed publicly (no hardcoded credentials)
- Is runnable without re-reading notes from the last upgrade
- Handles the known ordering constraints and failure modes
- Posts a summary to the Matrix alerts room for audit trail

## Decision

**Superseded 2026-10-11.** The original decision below (direct `helm upgrade` from `scripts/upgrade-apps.sh`) was written before the full migration to ArgoCD (ADR-0011). It is kept here for history; the actual process now splits in two:

**Helm-sourced ArgoCD Applications (ArgoCD, kube-prometheus-stack, Authentik)** go through git, never a direct `helm upgrade` from a workstation — that bypasses GitOps and creates drift between git and the live cluster:

1. Bump `targetRevision` in `kubernetes/bootstrap/argocd-helm-apps.yaml`, commit, push.
2. Apply that file directly to the cluster: `kubectl apply -f kubernetes/bootstrap/argocd-helm-apps.yaml`. **This step is not optional** — Applications under `kubernetes/bootstrap/` are not watched by any app-of-apps, so pushing to git alone changes nothing live.
3. Hard-refresh before syncing: `kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite`. ArgoCD's repo-server caches the Helm chart repo index — a plain sync after a version bump can report `Synced Healthy` instantly without the chart version actually changing.
4. Trigger the sync: `kubectl patch application <name> -n argocd --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'`.
5. Verify against the real running image tag (`kubectl get deploy <name> -o jsonpath='{.spec.template.spec.containers[0].image}'`), not `helm list` — ArgoCD's multi-source Helm rendering applies manifests directly rather than driving a tracked Helm release, so `helm list` can show a stale chart/revision indefinitely even after a real, successful upgrade.

**Manifest-managed apps using `:latest`-style tags** still need an explicit `kubectl rollout restart` — ArgoCD being in sync doesn't force a fresh image pull if the manifest content itself hasn't changed. `scripts/upgrade-apps.sh` still handles this part: reading runtime secrets, restarting low-risk apps first and Synapse+MAS last, health-checking, and posting a summary to the Matrix alerts room.

**Synapse and MAS are always restarted last.** They are tightly coupled — MAS handles all token issuance for Synapse — and new releases have historically shipped breaking config changes. Restarting them at the end limits blast radius.

**Custom-image apps are excluded.** Apps whose images are built from source (e.g. AuNoo) require a separate build-and-push step before any restart. The upgrade script explicitly skips them and prints a reminder.

**Worked example — the Authentik sequential upgrade (2026-10-11):** 2026.2.1 → 2026.2.3 → 2026.5.6 → 2026.8.3, one hop at a time via the git process above, with a verified `pg_dump -U authentik -d authentik -Fc` before every hop. Hop 2 hit a real breaking change: Authentik's internal default for `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` renders through the chart as a bracketed list literal (`"[0.0.0.0/0]"`), which the Rust-based config loader shipped in 2026.5.x rejects outright (`invalid IP address syntax`, crash-looping the worker before Django even starts). Fixed by setting it explicitly as a plain string in `authentik-values.yaml` (`trusted_proxy_cidrs: "10.42.0.0/16"`) — which also happened to satisfy 2026.8's stricter trusted-proxy header enforcement, so it needs to land before hop 2, not just before the final hop. See ADR-0010 and `scripts/upgrade-apps.sh`'s header comment for the full detail.

## Consequences

- Helm-sourced apps upgrade through an auditable git history; no more drift between what's declared and what's running.
- The two ArgoCD-specific gotchas above (bootstrap Applications not auto-reconciled, chart-index caching) are easy to miss and will make an upgrade silently no-op — always verify against the real running image tag, never trust a bare `Synced` status or `helm list` alone.
- The Authentik major-version constraint (no skips allowed) must still be handled manually: inspect the running image tag before starting, pin each intermediate chart version in turn.
- If Synapse or MAS ships a breaking config change, the script will surface it via the health check and well-known probe, but recovery still requires manual diagnosis.

## Alternatives considered

**CronJob in-cluster:** Would run automatically but requires the script to authenticate to itself, adds a service account with broad `kubectl` permissions, and makes it harder to observe output. Skipped in favour of a simple shell script run on demand from mgmt-01.

**Renovate/Dependabot for Helm versions:** Would auto-open PRs for chart updates. Not adopted yet — the cluster is single-operator and the overhead of reviewing PRs for each patch version outweighs the benefit. Revisit if the cluster grows to multiple operators.

**Separate scripts per app:** More surgical but harder to maintain ordering guarantees. A single ordered script is easier to reason about and avoids "I forgot to restart MAS" mistakes.
