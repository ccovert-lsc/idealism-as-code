#!/bin/bash
# Upgrade all deployed apps in the k3s cluster to their latest versions.
#
# This is a reference implementation — see your private repo for the version
# with cluster-specific values (namespaces, URLs, secret names).
#
# Run from mgmt-01:
#   bash ~/lab-work/scripts/upgrade-apps.sh
#
# IMPORTANT — Helm-managed apps are NOT upgraded by this script directly.
# Once ArgoCD manages an app (see ADR-0011), `helm upgrade` from a workstation
# bypasses GitOps and creates drift between git and the live cluster — avoid it.
# The real upgrade path for a Helm-sourced ArgoCD Application is:
#
#   1. Bump `targetRevision` in kubernetes/bootstrap/argocd-helm-apps.yaml, commit, push.
#   2. Apply that file directly to the cluster — bootstrap Applications are NOT
#      watched by an app-of-apps, so pushing to git alone changes nothing live:
#        kubectl apply -f kubernetes/bootstrap/argocd-helm-apps.yaml
#   3. Hard-refresh before syncing. ArgoCD's repo-server caches the Helm chart
#      index — a plain sync after a version bump can report "Synced Healthy"
#      instantly without actually changing the chart version at all:
#        kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite
#   4. Trigger the sync:
#        kubectl patch application <name> -n argocd --type merge \
#          -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'
#   5. Verify against the real running image tag, not `helm list` — ArgoCD's
#      multi-source Helm rendering applies manifests directly rather than
#      driving a tracked Helm release, so `helm list` can show a stale
#      version/revision indefinitely even after a real, successful upgrade:
#        kubectl get deploy <name> -o jsonpath='{.spec.template.spec.containers[0].image}'
#
# This script's remaining job is the part ArgoCD doesn't do for you: reading
# runtime secrets, restarting manifest-managed apps that pull `:latest` (ArgoCD
# won't force a fresh pull if the manifest content itself hasn't changed),
# health-checking, and posting a summary.
#
# What this does NOT do:
#   - Rebuild custom images (e.g. apps built from source — do that separately)
#   - Step through Authentik major versions automatically (see warning below)
#
# ---
# AUTHENTIK SEQUENTIAL UPGRADE WARNING:
#   Authentik rejects version upgrades that skip a major release. Confirmed
#   real path on this cluster: 2026.2.1 -> 2026.2.3 -> 2026.5.6 -> 2026.8.3
#   (one hop at a time, via the git+ArgoCD process above, not `helm upgrade`).
#   Before starting, check the current version from the running image, and
#   take a verified `pg_dump` before EVERY hop:
#     kubectl get deploy -n authentik authentik-server \
#       -o jsonpath='{.spec.template.spec.containers[0].image}'
#     kubectl exec -n authentik authentik-postgresql-0 -- \
#       sh -c "PGPASSWORD='<pw>' pg_dump -U authentik -d authentik -Fc" > backup.dump
#   Available versions: https://github.com/goauthentik/helm/releases
#
#   KNOWN BREAKING CHANGE (hit upgrading through 2026.5.x): Authentik's own
#   internal default for `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` gets rendered
#   by the chart as a bracketed list literal, e.g. "[0.0.0.0/0]". The Rust-based
#   config loader shipped in 2026.5.x rejects that outright ("invalid IP address
#   syntax"), crash-looping the worker before Django even starts. Fix: set it
#   explicitly as a plain string (not a YAML list) in authentik-values.yaml:
#     authentik:
#       listen:
#         trusted_proxy_cidrs: "<cluster-pod-cidr>"   # e.g. "10.42.0.0/16"
#   This also satisfies 2026.8's stricter trusted-proxy enforcement of
#   X-Forwarded-* headers, so set it before hop 2, not just before hop 3.
# ---
#
set -euo pipefail

# --- Configuration (adapt to your environment) ---
KUBECONFIG_PATH="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"
export KUBECONFIG="$KUBECONFIG_PATH"

ARGOCD_NAMESPACE="argocd"
AUTHENTIK_NAMESPACE="authentik"
MONITORING_NAMESPACE="monitoring"
SYNAPSE_NAMESPACE="synapse"
MATRIX_AUTH_NAMESPACE="matrix-auth"
N8N_NAMESPACE="n8n"
OLLAMA_NAMESPACE="ollama"
CLOUDFLARE_NAMESPACE="cloudflare"
ALERTMANAGER_NAMESPACE="matrix-alertmanager"
REGISTRY_NAMESPACE="registry"

MATRIX_BASE_URL="https://matrix.example.com"  # override in private repo
MATRIX_SECRETS_NAME="matrix-alertmanager-secrets"

echo "=== Reading runtime secrets ==="
# Sensitive values come from k8s secrets — never hardcoded
MATRIX_TOKEN=$(kubectl get secret -n "$ALERTMANAGER_NAMESPACE" "$MATRIX_SECRETS_NAME" \
  -o jsonpath="{.data.access_token}" | base64 -d)
MATRIX_ROOM=$(kubectl get secret -n "$ALERTMANAGER_NAMESPACE" "$MATRIX_SECRETS_NAME" \
  -o jsonpath="{.data.room_id}" | base64 -d)

# Read the real running image tag, not `helm list` -- for an ArgoCD-managed
# multi-source Helm app, `helm list` can show a stale chart/revision
# indefinitely even after a real successful upgrade (see the header warning).
CURRENT_AUTHENTIK=$(kubectl get deploy -n "$AUTHENTIK_NAMESPACE" authentik-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
echo "  Authentik currently at: $CURRENT_AUTHENTIK"

echo ""
echo "=== Step 1/2: Helm-managed apps (ArgoCD, kube-prometheus-stack, Authentik) ==="
echo "  These are ArgoCD Applications now -- this script does not call 'helm upgrade'"
echo "  directly (see the header warning: that bypasses GitOps and creates drift)."
echo "  Bump 'targetRevision' in kubernetes/bootstrap/argocd-helm-apps.yaml, commit,"
echo "  push, then follow the 5-step process in the header comment for each app."
echo ""
echo "  Current sync status (any drift here means a manual sync is needed):"
for app in argocd-self observability authentik; do
  STATUS=$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
    -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null || echo "not found")
  echo "    $app: $STATUS"
done

echo ""
echo "=== Step 3: Manifest app rollout restarts ==="

echo "  -> Low-risk apps"
kubectl rollout restart deployment -n "$CLOUDFLARE_NAMESPACE" cloudflared
kubectl rollout restart deployment -n "$N8N_NAMESPACE" n8n
kubectl rollout restart deployment -n "$OLLAMA_NAMESPACE" ollama open-webui
kubectl rollout restart deployment -n "$ALERTMANAGER_NAMESPACE" matrix-alertmanager
kubectl rollout restart deployment -n "$REGISTRY_NAMESPACE" registry

echo "  -> Synapse + MAS (restart last — tightly coupled, most likely to break on new releases)"
kubectl rollout restart deployment -n "$MATRIX_AUTH_NAMESPACE" mas
kubectl rollout restart deployment -n "$SYNAPSE_NAMESPACE" synapse element

echo ""
echo "=== Step 4: Waiting 60s for pods to stabilize ==="
sleep 60

echo ""
echo "=== Step 5: Health check ==="
UNHEALTHY=$(kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAME || true)
if [ -z "$UNHEALTHY" ]; then
  echo "  All pods Running or Completed."
  HEALTH_STATUS="✅ All pods healthy"
else
  echo "  UNHEALTHY PODS:"
  echo "$UNHEALTHY"
  HEALTH_STATUS="⚠️ Some pods unhealthy — check kubectl get pods -A"
fi

echo ""
echo "=== Step 6: Verify Matrix well-known ==="
WELLKNOWN=$(curl -sf --max-time 5 "${MATRIX_BASE_URL}/.well-known/matrix/client" || echo "FAILED")
if echo "$WELLKNOWN" | grep -q "m.homeserver"; then
  echo "  Matrix well-known: OK"
  MATRIX_STATUS="✅ Synapse well-known healthy"
else
  echo "  WARNING: well-known returned: $WELLKNOWN"
  MATRIX_STATUS="⚠️ Synapse well-known check failed"
fi

echo ""
echo "=== Step 7: Post summary to Matrix alerts room ==="
NEW_AUTHENTIK=$(kubectl get deploy -n "$AUTHENTIK_NAMESPACE" authentik-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
NEW_ARGOCD=$(kubectl get deploy -n "$ARGOCD_NAMESPACE" argocd-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
DATE=$(date -u +"%Y-%m-%d")

cat > /tmp/upgrade-summary.json << MSGEOF
{
  "msgtype": "m.text",
  "format": "org.matrix.custom.html",
  "body": "App upgrade complete — ${DATE}\n\nHelm: ArgoCD ${NEW_ARGOCD}, Authentik ${NEW_AUTHENTIK}\nImages refreshed: Synapse, MAS, Element, n8n, Ollama, Open WebUI, cloudflared, alertmanager, registry\n\n${HEALTH_STATUS}\n${MATRIX_STATUS}",
  "formatted_body": "<h3>🔧 App upgrade complete — ${DATE}</h3><h4>Helm charts</h4><ul><li>ArgoCD → ${NEW_ARGOCD}</li><li>Authentik → ${NEW_AUTHENTIK}</li><li>kube-prometheus-stack (latest chart)</li></ul><h4>Container images refreshed</h4><p>Synapse · MAS · Element · n8n · Ollama · Open WebUI · cloudflared · alertmanager · registry</p><h4>Status</h4><p>${HEALTH_STATUS}<br>${MATRIX_STATUS}</p>"
}
MSGEOF

TXN="upgrade-$(date +%s)"
ENCODED_ROOM=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote('$MATRIX_ROOM'))")
curl -sf -X PUT \
  "${MATRIX_BASE_URL}/_matrix/client/v3/rooms/${ENCODED_ROOM}/send/m.room.message/${TXN}" \
  -H "Authorization: Bearer ${MATRIX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @/tmp/upgrade-summary.json > /dev/null \
  && echo "  Matrix notification sent." \
  || echo "  Matrix notification failed (non-fatal)."

echo ""
echo "=== Done ==="
echo "  Custom-image apps excluded — rebuild manually (e.g. rebuild-aunoo.sh)."
echo "  If Authentik failed with 'major version skip', see the warning at the top of this script."
