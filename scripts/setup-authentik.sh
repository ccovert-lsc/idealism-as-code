#!/bin/bash
# Deploy Authentik (identity provider) to k3s.
# Run from mgmt-01: bash ~/lab-work/scripts/setup-authentik.sh
#
# Prerequisites:
#   - kubectl configured (KUBECONFIG exported or at default path)
#   - Helm installed, goauthentik repo added:
#       helm repo add goauthentik https://charts.goauthentik.io
#   - kubernetes/apps/authentik/ manifests present (namespace.yaml, authentik-values.yaml)
#
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

# --- Config: adapt to your environment ---
DOMAIN="example.com"           # Your public domain
ADMIN_EMAIL="admin@${DOMAIN}"
AUTHENTIK_VALUES="$HOME/lab-work/kubernetes/apps/authentik/authentik-values.yaml"

echo "=== Generating secrets ==="
POSTGRES_PASSWORD=$(openssl rand -hex 16)
SECRET_KEY=$(openssl rand -hex 32)
BOOTSTRAP_PASSWORD=$(openssl rand -hex 12)

echo ""
echo "  Bootstrap email:    $ADMIN_EMAIL"
echo "  Bootstrap password: $BOOTSTRAP_PASSWORD"
echo ""
echo "  SAVE THESE BEFORE CONTINUING"
echo ""
read -p "Press enter to continue..."

echo "=== Creating namespace ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/authentik/namespace.yaml"

echo "=== Creating secrets ==="
printf '%s' "$SECRET_KEY"         > /tmp/ak_secret_key
printf '%s' "$POSTGRES_PASSWORD"  > /tmp/ak_pg_pass
printf '%s' "$BOOTSTRAP_PASSWORD" > /tmp/ak_bootstrap_pw
printf '%s' "$ADMIN_EMAIL"        > /tmp/ak_bootstrap_email

kubectl create secret generic authentik-secrets -n authentik \
  --from-file=AUTHENTIK_SECRET_KEY=/tmp/ak_secret_key \
  --from-file=AUTHENTIK_POSTGRESQL__PASSWORD=/tmp/ak_pg_pass \
  --from-file=AUTHENTIK_BOOTSTRAP_PASSWORD=/tmp/ak_bootstrap_pw \
  --from-file=AUTHENTIK_BOOTSTRAP_EMAIL=/tmp/ak_bootstrap_email \
  --dry-run=client -o yaml | kubectl apply -f -

rm /tmp/ak_secret_key /tmp/ak_pg_pass /tmp/ak_bootstrap_pw /tmp/ak_bootstrap_email

echo "=== Adding Helm repo ==="
helm repo add goauthentik https://charts.goauthentik.io 2>/dev/null || true
helm repo update

echo "=== Installing Authentik ==="
helm upgrade --install authentik goauthentik/authentik \
  -n authentik \
  -f "$AUTHENTIK_VALUES" \
  --set postgresql.auth.password="$POSTGRES_PASSWORD" \
  --wait --timeout 10m

echo ""
echo "=== Done ==="
echo "  URL:      https://id.${DOMAIN}"
echo "  Email:    $ADMIN_EMAIL"
echo "  Password: $BOOTSTRAP_PASSWORD"
echo ""
echo "Next steps:"
echo "  1. Add DNS/Tunnel route for id.${DOMAIN} → ingress-nginx"
echo "  2. Log into https://id.${DOMAIN}"
echo "  3. Create an OIDC Provider for Matrix Authentication Service:"
echo "       Admin → Providers → Create → OAuth2/OpenID Provider"
echo "       Name: matrix-authentication-service"
echo "       Client type: Confidential"
echo "       Redirect URIs: https://matrix-auth.${DOMAIN}/upstream/callback/authentik-01"
echo "       Scopes: openid, profile, email"
echo "       Copy the client_id and client_secret"
echo "  4. Create an Application in Authentik:"
echo "       Admin → Applications → Create"
echo "       Name: Matrix Authentication Service"
echo "       Slug: matrix-authentication-service"
echo "       Provider: matrix-authentication-service"
echo "  5. Run: bash ~/lab-work/scripts/setup-mas.sh <client_id> <client_secret>"
