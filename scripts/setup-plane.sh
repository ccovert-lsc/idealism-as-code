#!/bin/bash
# Deploy Plane (project management) to k3s.
# See ADR-0017.
#
# Replace ALL <placeholder> values before running.
# Run from mgmt-01: bash ~/lab-work/scripts/setup-plane.sh
set -euo pipefail
export KUBECONFIG=/home/ubuntu/.kube/lab.yaml

DOMAIN="plane.<your-domain>"

POSTGRES_PASSWORD=$(openssl rand -hex 16)
SECRET_KEY=$(openssl rand -hex 32)

echo "=== Plane Setup ==="
echo ""
echo "  URL: https://$DOMAIN"
echo "  The first registered user becomes the workspace owner."
echo ""
read -p "Press enter to continue..."

echo "=== Creating namespace ==="
kubectl apply -f <path-to-manifests>/plane/namespace.yaml

echo "=== Creating secrets ==="
printf '%s' "$POSTGRES_PASSWORD" > /tmp/plane_pg
printf '%s' "$SECRET_KEY"        > /tmp/plane_sk

kubectl create secret generic plane-secrets -n plane \
  --from-literal=POSTGRES_HOST=plane-postgres \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_DB=plane \
  --from-literal=POSTGRES_USER=plane \
  --from-file=POSTGRES_PASSWORD=/tmp/plane_pg \
  --from-file=SECRET_KEY=/tmp/plane_sk \
  --from-literal=USE_MINIO=0 \
  --from-literal=MEDIA_ROOT=/app/media \
  --from-literal=DEFAULT_FILE_STORAGE=django.core.files.storage.FileSystemStorage \
  --from-literal=CORS_ALLOWED_ORIGINS=https://$DOMAIN \
  --from-literal=WEB_URL=https://$DOMAIN \
  --from-literal=DEBUG=0 \
  --dry-run=client -o yaml | kubectl apply -f -

rm /tmp/plane_pg /tmp/plane_sk

echo "=== Deploying Plane stack ==="
kubectl apply -f <path-to-manifests>/plane/plane.yaml

echo "=== Waiting for postgres ==="
until kubectl exec -n plane \
  "$(kubectl get pods -n plane -l app=plane-postgres -o jsonpath='{.items[0].metadata.name}')" \
  -- pg_isready -U plane 2>/dev/null; do sleep 3; done

echo "=== Waiting for API (runs DB migrations on first start) ==="
kubectl rollout status deployment/plane-api -n plane --timeout=300s

echo "=== Waiting for frontend ==="
kubectl rollout status deployment/plane-frontend -n plane --timeout=180s

echo ""
echo "=== Done ==="
echo "  URL: https://$DOMAIN"
echo ""
echo "Next steps:"
echo "  1. Add Cloudflare Tunnel route: $DOMAIN → http://<ingress-ip>"
echo "     Host header override: $DOMAIN"
echo "  2. Open $DOMAIN and register — first user is workspace owner"
