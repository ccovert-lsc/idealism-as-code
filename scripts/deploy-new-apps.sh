#!/bin/bash
# Deploy the workload-layer apps: Ollama, Open WebUI, n8n, matrix-alertmanager.
#
# Run from mgmt-01: bash ~/lab-work/scripts/deploy-new-apps.sh
#
# Prerequisites:
#   - Cluster up, ingress-nginx running, MetalLB configured
#   - For n8n: creates a postgres database with a random generated password
#   - For AuNoo: image must already be built and pushed to the local registry
#     (see rebuild-aunoo.sh)
#
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

echo "=== Deploying Ollama + Open WebUI ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/ollama/namespace.yaml"
kubectl apply -f "$HOME/lab-work/kubernetes/apps/ollama/ollama.yaml"

echo "=== Deploying n8n ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/n8n/namespace.yaml"

PG_PASS=$(openssl rand -base64 24 | tr -d /=+)
ENC_KEY=$(openssl rand -base64 32 | tr -d /=+)
printf "%s" "$PG_PASS" > /tmp/n8n_pg.txt
printf "%s" "$ENC_KEY" > /tmp/n8n_enc.txt
kubectl create secret generic n8n-secrets -n n8n \
  --from-file=postgres_password=/tmp/n8n_pg.txt \
  --from-file=encryption_key=/tmp/n8n_enc.txt \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/n8n_pg.txt /tmp/n8n_enc.txt

kubectl apply -f "$HOME/lab-work/kubernetes/apps/n8n/postgres.yaml"
kubectl apply -f "$HOME/lab-work/kubernetes/apps/n8n/n8n.yaml"

echo "=== Creating matrix-alertmanager namespace ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/matrix-alertmanager/namespace.yaml"
# The alertbot secret and bridge deployment are done separately by setup-alertbot.sh

echo "=== Deploying AuNoo (requires image in local registry) ==="
kubectl apply -f "$HOME/lab-work/kubernetes/apps/aunoo/app.yaml"

echo "=== Done — pulling first Ollama model (background) ==="
kubectl rollout status deployment/ollama -n ollama --timeout=120s
kubectl exec -n ollama deployment/ollama -- ollama pull llama3.2:3b &
echo "Model pull started in background. Run: kubectl logs -n ollama deployment/ollama -f"
