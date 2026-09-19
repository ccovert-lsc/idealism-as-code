#!/bin/bash
# Rebuild the AuNoo image from source and push to the local registry.
#
# AuNoo is built from source because the upstream image either doesn't exist
# or has bugs requiring local patches. The image is pushed to the local
# in-cluster registry and the k8s deployment is restarted.
#
# Run from mgmt-01: bash ~/lab-work/scripts/rebuild-aunoo.sh
set -euo pipefail

# --- Config: adapt to your environment ---
REGISTRY_IP="<REGISTRY_LOADBALANCER_IP>"   # e.g. 192.168.10.202
SOURCE_DIR="$HOME/aunoo-src"               # local clone of the AuNoo source repo
SOURCE_BRANCH="develop"                    # branch to build from
IMAGE="${REGISTRY_IP}:5000/aunoo:latest"

echo "=== Updating source ==="
cd "$SOURCE_DIR"
git fetch origin
git checkout "$SOURCE_BRANCH"
git pull

echo "=== Building image ==="
sg docker -c "docker build -t $IMAGE ."

echo "=== Pushing to local registry ==="
sg docker -c "docker push $IMAGE"

echo "=== Restarting AuNoo deployment ==="
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"
kubectl rollout restart deployment/aunoo -n aunoo
kubectl rollout status deployment/aunoo -n aunoo --timeout=120s

echo ""
echo "=== Done. AuNoo running image: $IMAGE ==="
