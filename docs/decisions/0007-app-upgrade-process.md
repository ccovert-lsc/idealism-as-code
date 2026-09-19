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

All upgrade logic lives in `scripts/upgrade-apps.sh`. Sensitive values (database passwords, Matrix tokens) are read from k8s secrets at runtime via `kubectl get secret ... | base64 -d`, so the script contains no credentials and can be published in the public repository without modification.

**Execution order is fixed:**

1. `helm repo update`
2. Helm upgrades: ArgoCD → kube-prometheus-stack → Authentik (in parallel where safe, Authentik last because it has the strictest version constraints)
3. Rollout-restart of manifest apps: low-risk apps first, then Synapse+MAS last
4. 60-second stabilization wait
5. Health check (`kubectl get pods -A`)
6. Synapse well-known verification (`/.well-known/matrix/client`)
7. Matrix notification to the alerts room

**Synapse and MAS are always restarted last.** They are tightly coupled — MAS handles all token issuance for Synapse — and new releases have historically shipped breaking config changes. Restarting them at the end limits blast radius.

**Custom-image apps are excluded.** Apps whose images are built from source (e.g. AuNoo) require a separate build-and-push step before any restart. The upgrade script explicitly skips them and prints a reminder.

## Consequences

- A single script handles the full upgrade cycle: run it from mgmt-01, watch the output, check the Matrix room.
- No credentials in git history — the public repo script is identical to the private one except for placeholder URLs.
- The Authentik major-version constraint (no skips allowed) must still be handled manually: inspect `helm list -n authentik` before running, pin an intermediate `--version` if needed.
- If Synapse or MAS ships a breaking config change, the script will surface it via the health check and well-known probe, but recovery still requires manual diagnosis.

## Alternatives considered

**CronJob in-cluster:** Would run automatically but requires the script to authenticate to itself, adds a service account with broad `kubectl` permissions, and makes it harder to observe output. Skipped in favour of a simple shell script run on demand from mgmt-01.

**Renovate/Dependabot for Helm versions:** Would auto-open PRs for chart updates. Not adopted yet — the cluster is single-operator and the overhead of reviewing PRs for each patch version outweighs the benefit. Revisit if the cluster grows to multiple operators.

**Separate scripts per app:** More surgical but harder to maintain ordering guarantees. A single ordered script is easier to reason about and avoids "I forgot to restart MAS" mistakes.
