#!/bin/bash
# Deploy Nextcloud (files, calendar, collaborative docs) to k3s.
# See ADR-0016.
#
# Replace ALL <placeholder> values before running.
# Run from mgmt-01: bash ~/lab-work/scripts/setup-nextcloud.sh
set -euo pipefail
export KUBECONFIG=/home/ubuntu/.kube/lab.yaml

DOMAIN="nextcloud.<your-domain>"

POSTGRES_PASSWORD=$(openssl rand -hex 16)
ADMIN_PASSWORD=$(openssl rand -hex 12)

echo "=== Nextcloud Setup ==="
echo ""
echo "  Admin user:     admin"
echo "  Admin password: $ADMIN_PASSWORD"
echo "  Domain:         https://$DOMAIN"
echo ""
echo "  SAVE THE ADMIN PASSWORD BEFORE CONTINUING"
echo ""
read -p "Press enter to continue..."

echo "=== Creating namespace ==="
kubectl apply -f <path-to-manifests>/nextcloud/namespace.yaml

echo "=== Creating secrets ==="
printf '%s' "$POSTGRES_PASSWORD" > /tmp/nc_pg
printf '%s' "$ADMIN_PASSWORD"    > /tmp/nc_admin

kubectl create secret generic nextcloud-secrets -n nextcloud \
  --from-file=postgres_password=/tmp/nc_pg \
  --from-file=admin_password=/tmp/nc_admin \
  --dry-run=client -o yaml | kubectl apply -f -

rm /tmp/nc_pg /tmp/nc_admin

echo "=== Deploying Nextcloud stack ==="
kubectl apply -f <path-to-manifests>/nextcloud/nextcloud.yaml

echo "=== Waiting for postgres ==="
until kubectl exec -n nextcloud \
  "$(kubectl get pods -n nextcloud -l app=nextcloud-postgres -o jsonpath='{.items[0].metadata.name}')" \
  -- pg_isready -U nextcloud 2>/dev/null; do sleep 3; done

echo "=== Waiting for Nextcloud first-run install (2-3 minutes) ==="
kubectl rollout status deployment/nextcloud -n nextcloud --timeout=300s

echo "=== Configuring proxy settings via occ ==="
OCC="kubectl exec -n nextcloud deploy/nextcloud -- su -s /bin/sh www-data -c"

$OCC "php occ config:system:set trusted_proxies 0 --value='10.42.0.0/16'"
$OCC "php occ config:system:set overwriteprotocol --value='https'"
$OCC "php occ config:system:set overwritecliurl --value='https://$DOMAIN'"
$OCC "php occ config:system:set overwritehost --value='$DOMAIN'"
$OCC "php occ config:system:set default_phone_region --value='<ISO-3166-country-code>'"
$OCC "php occ config:system:set maintenance_window_start --type=integer --value=1"

echo "=== Restarting Nextcloud to apply config ==="
kubectl rollout restart deployment/nextcloud -n nextcloud
kubectl rollout status deployment/nextcloud -n nextcloud --timeout=120s

echo ""
echo "=== Done ==="
echo "  URL: https://$DOMAIN"
echo ""
echo "Next steps:"
echo "  1. Add Cloudflare Tunnel route: $DOMAIN → http://<ingress-ip>"
echo "     Host header override: $DOMAIN"
echo "  2. Log in as admin and install: Calendar, Contacts, Nextcloud Office"
