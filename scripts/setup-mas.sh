#!/bin/bash
# Deploy Synapse + Matrix Authentication Service (MAS) with Authentik SSO.
#
# ARCHITECTURE NOTE: MAS, Synapse, Element, and Authentik must be deployed together.
# MAS provides QR-code device auth and modern token management, but adding it to an
# already-running Synapse causes DB state divergence and auth sequencing failures.
# Start fresh with all four components.
#
# Prerequisites:
#   - Authentik running with an OIDC provider configured for MAS (see setup-authentik.sh)
#   - DNS/Tunnel routes: matrix.<domain> and matrix-auth.<domain> → ingress-nginx
#
# Run from mgmt-01:
#   bash ~/lab-work/scripts/setup-mas.sh <client_id> <client_secret>
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

AUTHENTIK_CLIENT_ID="${1:?Usage: setup-mas.sh <authentik_client_id> <authentik_client_secret>}"
AUTHENTIK_CLIENT_SECRET="${2:?Usage: setup-mas.sh <authentik_client_id> <authentik_client_secret>}"

# --- Config: adapt to your environment ---
SERVER_NAME="example.com"              # Matrix server name (part of @user:server_name)
MATRIX_PUBLIC_URL="https://matrix.${SERVER_NAME}"
MAS_PUBLIC_URL="https://matrix-auth.${SERVER_NAME}"
AUTHENTIK_ISSUER="https://id.${SERVER_NAME}/application/o/matrix-authentication-service/"

echo "=== Synapse + MAS Setup ==="

SYNAPSE_POSTGRES_PASSWORD=$(openssl rand -hex 16)
MAS_POSTGRES_PASSWORD=$(openssl rand -hex 16)
MAS_SYNAPSE_SECRET=$(openssl rand -hex 32)
MAS_ENCRYPTION_KEY=$(openssl rand -hex 32)

echo "=== Deploying Synapse ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/synapse/namespace.yaml"

printf '%s' "$SYNAPSE_POSTGRES_PASSWORD" > /tmp/syn_pg_pass
printf '%s' "$MAS_SYNAPSE_SECRET"        > /tmp/syn_mas_secret
kubectl create secret generic synapse-secrets -n synapse \
  --from-file=postgres_password=/tmp/syn_pg_pass \
  --from-file=mas_secret=/tmp/syn_mas_secret \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/syn_pg_pass /tmp/syn_mas_secret

kubectl apply -f "$HOME/lab-work/kubernetes/apps/synapse/postgres.yaml"
echo "Waiting for Synapse postgres..."
until kubectl exec -n synapse \
  "$(kubectl get pods -n synapse -l app=synapse-postgres -o jsonpath='{.items[0].metadata.name}')" \
  -- pg_isready -U synapse 2>/dev/null; do sleep 3; done

kubectl apply -f "$HOME/lab-work/kubernetes/apps/synapse/synapse.yaml"
kubectl rollout status deployment/synapse -n synapse --timeout=180s

echo "=== Deploying MAS ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/mas/namespace.yaml"

printf '%s' "$MAS_POSTGRES_PASSWORD" > /tmp/mas_pg_pass
kubectl create secret generic mas-secrets -n matrix-auth \
  --from-file=postgres_password=/tmp/mas_pg_pass \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/mas_pg_pass

kubectl apply -f "$HOME/lab-work/kubernetes/apps/mas/mas.yaml"
echo "Waiting for MAS postgres..."
until kubectl exec -n matrix-auth \
  "$(kubectl get pods -n matrix-auth -l app=mas-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" \
  -- pg_isready -U mas_user -d mas_db 2>/dev/null; do sleep 3; done

echo "=== Generating MAS signing keys ==="
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null > /tmp/mas_rsa.pem
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256  2>/dev/null > /tmp/mas_ec256.pem
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384  2>/dev/null > /tmp/mas_ec384.pem
sed 's/^/        /' /tmp/mas_rsa.pem   > /tmp/mas_rsa_indented.txt
sed 's/^/        /' /tmp/mas_ec256.pem > /tmp/mas_ec256_indented.txt
sed 's/^/        /' /tmp/mas_ec384.pem > /tmp/mas_ec384_indented.txt

# Generate a ULID for the Authentik provider ID
AUTHENTIK_PROVIDER_ID=$(python3 -c "
import time, random
ENC = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
t = int(time.time() * 1000)
ts = ''.join(ENC[(t >> (5 * i)) & 0x1F] for i in range(9, -1, -1))
rand = ''.join(random.choice(ENC) for _ in range(16))
print(ts + rand)
")

echo "=== Creating MAS config secret ==="
cat > /tmp/mas-config.yaml << MASEOF
http:
  public_base: "${MAS_PUBLIC_URL}"
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
        - name: assets
      binds:
        - address: "[::]:8080"
    - name: internal
      resources:
        - name: health
      binds:
        - address: "[::]:8081"

database:
  uri: "postgresql://mas_user:${MAS_POSTGRES_PASSWORD}@mas-postgres:5432/mas_db"

matrix:
  homeserver: ${SERVER_NAME}
  secret: "${MAS_SYNAPSE_SECRET}"
  endpoint: "http://synapse.synapse:8008"

secrets:
  encryption: "${MAS_ENCRYPTION_KEY}"
  keys:
    - key: |
$(cat /tmp/mas_rsa_indented.txt)
    - key: |
$(cat /tmp/mas_ec256_indented.txt)
    - key: |
$(cat /tmp/mas_ec384_indented.txt)

clients:
  - client_id: "0000000000000000000SYNAPSE"
    client_auth_method: client_secret_basic
    client_secret: "${MAS_SYNAPSE_SECRET}"

upstream_oauth2:
  providers:
    - id: "${AUTHENTIK_PROVIDER_ID}"
      human_name: "Authentik"
      issuer: "${AUTHENTIK_ISSUER}"
      client_id: "${AUTHENTIK_CLIENT_ID}"
      client_secret: "${AUTHENTIK_CLIENT_SECRET}"
      token_endpoint_auth_method: client_secret_basic
      scope: "openid profile email"
      fetch_userinfo: false
      claims_imports:
        localpart:
          action: require
          template: "{{ user.preferred_username }}"
        displayname:
          action: suggest
          template: "{{ user.name }}"
        email:
          action: suggest
          template: "{{ user.email }}"
          set_email_verification: import

passwords:
  enabled: true
  schemes:
    - version: 1
      algorithm: bcrypt
MASEOF

kubectl create secret generic mas-config -n matrix-auth \
  --from-file=config.yaml=/tmp/mas-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/mas-config.yaml /tmp/mas_rsa.pem /tmp/mas_ec256.pem /tmp/mas_ec384.pem \
   /tmp/mas_rsa_indented.txt /tmp/mas_ec256_indented.txt /tmp/mas_ec384_indented.txt

echo "=== Restarting MAS to pick up config ==="
kubectl rollout restart deployment/mas -n matrix-auth
kubectl rollout status deployment/mas -n matrix-auth --timeout=120s

echo "=== Deploying Element ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/synapse/element.yaml"
kubectl rollout status deployment/element -n synapse --timeout=120s

echo ""
echo "=== Done ==="
echo "  MAS URL:      ${MAS_PUBLIC_URL}"
echo "  Synapse URL:  ${MATRIX_PUBLIC_URL}"
echo ""
echo "To create a Synapse admin user:"
echo "  kubectl exec -n matrix-auth deploy/mas -- mas-cli manage register-user --admin -u <username>"
