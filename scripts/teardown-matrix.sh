#!/bin/bash
# Tear down MAS and Synapse completely.
# Deletes both namespaces, all PVCs, and all database data.
#
# WARNING: This is destructive and irreversible.
#          All Matrix users and room history stored locally will be lost.
#          Remote servers retain their copy of shared room history.
#
# Run from mgmt-01: bash ~/lab-work/scripts/teardown-matrix.sh
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

echo "=== Deleting matrix-auth namespace (MAS + MAS postgres PVC) ==="
kubectl delete namespace matrix-auth --ignore-not-found

echo "=== Deleting synapse namespace (Synapse + Synapse postgres PVC) ==="
kubectl delete namespace synapse --ignore-not-found

echo "Waiting for namespaces to terminate..."
kubectl wait --for=delete namespace/matrix-auth --timeout=120s 2>/dev/null || true
kubectl wait --for=delete namespace/synapse --timeout=120s 2>/dev/null || true

echo ""
echo "=== Done. All namespaces, secrets, and PVCs deleted. ==="
echo "Databases are gone. Run setup-mas.sh when ready to redeploy."
