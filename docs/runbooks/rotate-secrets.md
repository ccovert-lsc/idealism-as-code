# Runbook: Rotate Secrets

## When to use

- A secret has been exposed (e.g. appeared in a log, was accidentally committed)
- Routine rotation (annually or per policy)

## Authentik secrets

### Rotate the Authentik secret key

The secret key signs Authentik session tokens. Rotating it logs out all active sessions.

```bash
NEW_KEY=$(openssl rand -hex 32)
printf '%s' "$NEW_KEY" > /tmp/ak_secret_key
kubectl create secret generic authentik-secrets -n authentik \
  --from-file=AUTHENTIK_SECRET_KEY=/tmp/ak_secret_key \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/ak_secret_key
kubectl rollout restart deployment -n authentik authentik-server authentik-worker
```

### Rotate an Authentik OIDC client secret

1. In Authentik Admin → Providers → select the provider → Edit → regenerate client secret
2. Copy the new secret
3. Update the k8s secret for the app that uses it (e.g. `grafana-oidc-secret`, `open-webui-oidc-secret`, `argocd-secret`) — see `scripts/setup-sso.sh` for the secret names
4. Rollout restart the affected app

## Matrix / MAS secrets

### Rotate the MAS ↔ Synapse shared secret

This secret is embedded in the MAS config secret and in the Synapse config. Both must be updated atomically and both services restarted.

```bash
NEW_SECRET=$(openssl rand -hex 32)

# Update synapse-secrets
printf '%s' "$NEW_SECRET" > /tmp/syn_mas_secret
kubectl create secret generic synapse-secrets -n synapse \
  --from-file=mas_secret=/tmp/syn_mas_secret \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/syn_mas_secret

# Rebuild MAS config with the new secret, then:
kubectl rollout restart deployment/mas -n matrix-auth
kubectl rollout restart deployment/synapse -n synapse
```

### Rotate MAS signing keys

Regenerate the RSA and EC keys used to sign JWT tokens. All active Matrix sessions will be invalidated.

Re-run the key generation block from `scripts/setup-mas.sh` (the `openssl genpkey` steps), build a new `mas-config.yaml`, recreate the `mas-config` secret, and restart MAS.

## n8n secrets

n8n uses a PostgreSQL password and an encryption key. The encryption key protects stored credentials in n8n. Rotating it requires re-entering all saved credentials in n8n.

```bash
# Rotate only the postgres password (safer — does not affect saved credentials)
NEW_PG=$(openssl rand -base64 24 | tr -d /=+)
printf "%s" "$NEW_PG" > /tmp/n8n_pg.txt
kubectl create secret generic n8n-secrets -n n8n \
  --from-file=postgres_password=/tmp/n8n_pg.txt \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/n8n_pg.txt
# Also update the postgres user password inside the DB:
kubectl exec -n n8n deploy/n8n-postgres -- \
  psql -U n8n -c "ALTER USER n8n PASSWORD '$NEW_PG';"
kubectl rollout restart deployment/n8n -n n8n
```

## General notes

- Always use `--from-file` (never `--from-literal` with shell variables) when creating k8s secrets to avoid trailing newlines and shell expansion issues.
- After rotating any secret, restart the affected deployments and verify pods come up healthy:
  ```bash
  kubectl get pods -A | grep -v Running | grep -v Completed
  ```
- For SOPS-encrypted secrets in the private repo: decrypt, update the value, re-encrypt with `sops -e -i secrets/foo.yaml`.
