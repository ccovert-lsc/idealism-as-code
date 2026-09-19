#!/bin/bash
# Wire Grafana, ArgoCD, and Open WebUI to Authentik SSO.
#
# Before running this script, create three OAuth2/OpenID providers in Authentik:
#
#   1. Grafana
#      Admin → Applications → Providers → Create → OAuth2/OpenID Provider
#      - Name: Grafana
#      - Client type: Confidential
#      - Redirect URIs: https://grafana.<domain>/login/generic_oauth
#      - Scopes: openid, email, profile
#      Then create Application: name=Grafana, provider=Grafana, slug=grafana
#
#   2. ArgoCD
#      - Name: ArgoCD
#      - Client type: Confidential
#      - Redirect URIs: https://argocd.<domain>/auth/callback
#      - Scopes: openid, email, profile
#      Then create Application: name=ArgoCD, provider=ArgoCD, slug=argocd
#
#   3. Open WebUI
#      - Name: Open WebUI
#      - Client type: Confidential
#      - Redirect URIs: https://ai.<domain>/oauth/oidc/callback
#      - Scopes: openid, email, profile
#      Then create Application: name=Open WebUI, provider=Open WebUI, slug=open-webui
#
# Run from mgmt-01:
#   bash ~/lab-work/scripts/setup-sso.sh \
#     <grafana_client_id> <grafana_client_secret> \
#     <argocd_client_id>  <argocd_client_secret> \
#     <webui_client_id>   <webui_client_secret>
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

GRAFANA_CLIENT_ID="${1:?Missing grafana_client_id}"
GRAFANA_CLIENT_SECRET="${2:?Missing grafana_client_secret}"
ARGOCD_CLIENT_ID="${3:?Missing argocd_client_id}"
ARGOCD_CLIENT_SECRET="${4:?Missing argocd_client_secret}"
WEBUI_CLIENT_ID="${5:?Missing webui_client_id}"
WEBUI_CLIENT_SECRET="${6:?Missing webui_client_secret}"

MONITORING_VALUES="$HOME/lab-work/kubernetes/apps/observability/kube-prometheus-stack-values.yaml"
ARGOCD_VALUES="$HOME/lab-work/kubernetes/apps/argocd/argocd-values.yaml"
OLLAMA_MANIFEST="$HOME/lab-work/kubernetes/apps/ollama/ollama.yaml"

echo "=== SSO Setup: Grafana + ArgoCD + Open WebUI ==="

echo "=== Grafana: creating OIDC secret ==="
kubectl create secret generic grafana-oidc-secret -n monitoring \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID="$GRAFANA_CLIENT_ID" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="$GRAFANA_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Grafana: upgrading Helm release ==="
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "$MONITORING_VALUES" \
  --reuse-values=false \
  --wait

echo "=== ArgoCD: patching argocd-secret with OIDC credentials ==="
ARGOCD_SECRET_PATCH=$(kubectl get secret argocd-secret -n argocd -o json | \
  python3 -c "
import sys, json, base64
s = json.load(sys.stdin)
s['data']['oidc.authentik.clientID']     = base64.b64encode(b'$ARGOCD_CLIENT_ID').decode()
s['data']['oidc.authentik.clientSecret'] = base64.b64encode(b'$ARGOCD_CLIENT_SECRET').decode()
print(json.dumps(s))
")
echo "$ARGOCD_SECRET_PATCH" | kubectl apply -f -

echo "=== ArgoCD: upgrading Helm release ==="
helm upgrade argocd argo/argo-cd \
  -n argocd \
  -f "$ARGOCD_VALUES" \
  --reuse-values=false \
  --wait

echo "=== Open WebUI: creating OIDC secret ==="
kubectl create secret generic open-webui-oidc-secret -n ollama \
  --from-literal=client_id="$WEBUI_CLIENT_ID" \
  --from-literal=client_secret="$WEBUI_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Open WebUI: applying updated manifest ==="
kubectl apply -f "$OLLAMA_MANIFEST"
kubectl rollout restart deployment/open-webui -n ollama
kubectl rollout status deployment/open-webui -n ollama --timeout=120s

echo ""
echo "=== Done ==="
echo "Grafana:    https://grafana.<domain>  — click 'Sign in with Authentik'"
echo "ArgoCD:     https://argocd.<domain>   — click 'Log in via Authentik'"
echo "Open WebUI: https://ai.<domain>       — click 'Continue with Authentik'"
