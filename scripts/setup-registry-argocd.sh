#!/bin/bash
# Deploy the local container registry and ArgoCD.
#
# Also configures all k3s nodes to trust the local registry (HTTP/insecure)
# and installs Docker on mgmt-01 for building custom images.
#
# Run from mgmt-01: bash ~/lab-work/scripts/setup-registry-argocd.sh
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

# --- Config: adapt to your environment ---
REGISTRY_IP="<REGISTRY_LOADBALANCER_IP>"   # MetalLB IP assigned to the registry service
K3S_SERVER="<K3S_SERVER_IP>"
K3S_AGENTS="<AGENT_1_IP> <AGENT_2_IP>"     # space-separated
K3S_NODES="$K3S_SERVER $K3S_AGENTS"
DOMAIN="example.com"
ARGOCD_VALUES="$HOME/lab-work/kubernetes/apps/argocd/argocd-values.yaml"

echo "=== Deploying local registry ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/registry/namespace.yaml"
kubectl apply -f "$HOME/lab-work/kubernetes/apps/registry/registry.yaml"
kubectl rollout status deployment/registry -n registry --timeout=60s
echo "Registry up at $REGISTRY_IP:5000"

echo "=== Configuring k3s nodes to trust local registry ==="
REGISTRIES_YAML="mirrors:
  \"$REGISTRY_IP:5000\":
    endpoint:
      - \"http://$REGISTRY_IP:5000\"
"
for NODE in $K3S_NODES; do
  echo "  Configuring $NODE..."
  ssh -o StrictHostKeyChecking=no ubuntu@$NODE "
    sudo mkdir -p /etc/rancher/k3s
    echo '$REGISTRIES_YAML' | sudo tee /etc/rancher/k3s/registries.yaml > /dev/null
    sudo systemctl restart k3s || sudo systemctl restart k3s-agent
    echo '$NODE done'
  "
done
echo "Waiting 15s for k3s to restart on nodes..."
sleep 15

echo "=== Installing Docker on mgmt-01 ==="
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
sudo mkdir -p /etc/docker
echo "{\"insecure-registries\":[\"$REGISTRY_IP:5000\"]}" | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
echo "Docker ready"

echo "=== Installing ArgoCD ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f "$ARGOCD_VALUES" \
  --wait --timeout=5m

echo "=== ArgoCD admin password ==="
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""

echo ""
echo "=== Done ==="
echo "Registry: http://$REGISTRY_IP:5000"
echo "ArgoCD:   https://argocd.${DOMAIN}"
echo ""
echo "Log out and back in to mgmt-01 for the docker group to take effect."
echo "Then build and push a custom image:"
echo "  sg docker -c 'docker build -t $REGISTRY_IP:5000/myapp:latest . && docker push $REGISTRY_IP:5000/myapp:latest'"
