# Runbook: Pull an Ollama Model

## When to use

- Adding a new model for use in Open WebUI or n8n
- The model list in Open WebUI is empty after a pod restart (models persist in the PVC — this is rare but can happen if the PVC is lost)

## Steps

### Pull via kubectl exec

```bash
export KUBECONFIG=/home/ubuntu/.kube/lab.yaml

# List currently available models
kubectl exec -n ollama deployment/ollama -- ollama list

# Pull a model (runs in the foreground — can take several minutes)
kubectl exec -n ollama deployment/ollama -- ollama pull llama3.2:3b

# Pull in the background and tail logs
kubectl exec -n ollama deployment/ollama -- ollama pull mistral &
kubectl logs -n ollama deployment/ollama -f
```

### Verify in Open WebUI

1. Go to `https://ai.<domain>`
2. Click the model selector in the top bar
3. The new model should appear — if not, reload the page

## Common models

| Model | Size | Use case |
|-------|------|----------|
| `llama3.2:3b` | ~2 GB | Fast, low resource, good for general chat |
| `llama3.1:8b` | ~5 GB | Better quality, needs more VRAM/RAM |
| `mistral:7b` | ~4 GB | Good for structured output |
| `nomic-embed-text` | ~300 MB | Text embeddings (for RAG pipelines in n8n) |
| `qwen2.5-coder:7b` | ~4 GB | Code generation |

Check https://ollama.com/library for the full model list and tags.

## Resource notes

- The Ollama pod runs on a k3s agent node. Each model is loaded into RAM when first used (not kept loaded permanently). Ensure the agent has enough free memory before pulling large models.
- Model files are stored in the Ollama PVC (`ollama-models` in the `ollama` namespace). If the PVC is deleted, all pulled models are lost and must be re-pulled.
- Pull time depends on the model size and your internet connection. A 4 GB model on a 50 Mbps connection takes ~10 minutes.
