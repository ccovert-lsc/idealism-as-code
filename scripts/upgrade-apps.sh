#!/bin/bash
# Upgrade all deployed apps in the k3s cluster to their latest versions.
#
# This is a reference implementation — see your private repo for the version
# with cluster-specific values (namespaces, URLs, secret names).
#
# Run from mgmt-01:
#   bash ~/lab-work/scripts/upgrade-apps.sh
#
# Prerequisites:
#   - kubectl configured (KUBECONFIG exported)
#   - helm installed and repos added:
#       helm repo add argo https://argoproj.github.io/argo-helm
#       helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#       helm repo add goauthentik https://charts.goauthentik.io
#
# What this does:
#   1. Reads sensitive values from k8s secrets at runtime (no hardcoded credentials)
#   2. Upgrades Helm-managed apps (ArgoCD, kube-prometheus-stack, Authentik)
#   3. Rollout-restarts manifest-managed apps to force fresh :latest pulls
#   4. Waits, health-checks, and posts a summary to a Matrix room
#
# What this does NOT do:
#   - Rebuild custom images (e.g. apps built from source — do that separately)
#   - Step through Authentik major versions automatically (see warning below)
#
# ---
# AUTHENTIK MAJOR VERSION WARNING:
#   Authentik rejects version upgrades that skip a major release.
#   Upgrade path: 2026.2.x → 2026.4.x → 2026.6.x → 2026.8.x (one step at a time).
#   Before running, check current version:
#     helm list -n authentik
#   If the latest chart would skip a major version, pin the intermediate:
#     helm upgrade authentik goauthentik/authentik --version <intermediate> ...
#   Available versions: https://github.com/goauthentik/helm/releases
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

ARGOCD_VALUES="$HOME/lab-work/kubernetes/apps/argocd/argocd-values.yaml"
AUTHENTIK_VALUES="$HOME/lab-work/kubernetes/apps/authentik/authentik-values.yaml"
MONITORING_VALUES="$HOME/lab-work/kubernetes/apps/observability/kube-prometheus-stack-values.yaml"

MATRIX_BASE_URL="https://matrix.example.com"  # override in private repo
MATRIX_SECRETS_NAME="matrix-alertmanager-secrets"

echo "=== Reading runtime secrets ==="
# Sensitive values come from k8s secrets — never hardcoded
AUTHENTIK_PG_PASS=$(kubectl get secret -n "$AUTHENTIK_NAMESPACE" authentik-secrets \
  -o jsonpath="{.data.AUTHENTIK_POSTGRESQL__PASSWORD}" | base64 -d)

MATRIX_TOKEN=$(kubectl get secret -n "$ALERTMANAGER_NAMESPACE" "$MATRIX_SECRETS_NAME" \
  -o jsonpath="{.data.access_token}" | base64 -d)
MATRIX_ROOM=$(kubectl get secret -n "$ALERTMANAGER_NAMESPACE" "$MATRIX_SECRETS_NAME" \
  -o jsonpath="{.data.room_id}" | base64 -d)

CURRENT_AUTHENTIK=$(helm list -n "$AUTHENTIK_NAMESPACE" -o json | python3 -c \
  "import sys,json; r=json.load(sys.stdin); print(r[0]['app_version'] if r else 'unknown')")
echo "  Authentik currently at: $CURRENT_AUTHENTIK"

echo ""
echo "=== Step 1: Helm repo update ==="
helm repo update

echo ""
echo "=== Step 2: Helm chart upgrades ==="

echo "  -> ArgoCD"
helm upgrade argocd argo/argo-cd -n "$ARGOCD_NAMESPACE" \
  -f "$ARGOCD_VALUES" \
  --wait --timeout 10m

echo "  -> kube-prometheus-stack"
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "$MONITORING_NAMESPACE" \
  -f "$MONITORING_VALUES" \
  --wait --timeout 10m

echo "  -> Authentik (check version gap warning above if this fails)"
helm upgrade authentik goauthentik/authentik -n "$AUTHENTIK_NAMESPACE" \
  -f "$AUTHENTIK_VALUES" \
  --set postgresql.auth.password="$AUTHENTIK_PG_PASS" \
  --wait --timeout 10m

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
NEW_AUTHENTIK=$(helm list -n "$AUTHENTIK_NAMESPACE" -o json | python3 -c \
  "import sys,json; r=json.load(sys.stdin); print(r[0]['app_version'] if r else 'unknown')")
NEW_ARGOCD=$(helm list -n "$ARGOCD_NAMESPACE" -o json | python3 -c \
  "import sys,json; r=json.load(sys.stdin); print(r[0]['app_version'] if r else 'unknown')")
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
