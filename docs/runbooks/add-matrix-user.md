# Runbook: Add a Matrix User

## When to use

When a new person needs a Matrix account on the homelab Synapse server.

## Prerequisites

- `kubectl` access to the cluster with `KUBECONFIG` set
- MAS and Synapse running (`kubectl get pods -n matrix-auth -n synapse`)

## Steps

### Option A — Via MAS CLI (recommended)

Register the user through MAS. MAS handles the full user lifecycle and is the correct path when MAS is deployed alongside Synapse.

```bash
# Register a regular user
kubectl exec -n matrix-auth deploy/mas -- \
  mas-cli manage register-user -u <username>

# Register an admin user
kubectl exec -n matrix-auth deploy/mas -- \
  mas-cli manage register-user --admin -u <username>
```

The command will prompt for a password interactively, or set one via `--password` (check `mas-cli manage register-user --help`).

### Option B — Via Synapse registration script

Use the Synapse built-in tool directly. Requires the Synapse homeserver config path.

```bash
kubectl exec -n synapse deploy/synapse -- \
  register_new_matrix_user \
  -c /data/homeserver-patched.yaml \
  --no-admin \
  -u <username> \
  -p <password> \
  http://localhost:8008
```

For an admin account, replace `--no-admin` with `--admin`.

## Verify

After registration, the user should be able to log in via Element at `https://matrix.<domain>`. If Authentik SSO is configured, they may be prompted to link their Authentik account on first login.

## Notes

- If Authentik SSO is enabled, new users must complete the MAS ↔ Authentik account-linking flow on first login. Ensure their Authentik account exists first (Admin → Users → Create).
- Usernames are permanent and cannot be changed after registration.
- The MAS admin user (created during `setup-mas.sh`) can also manage users via the MAS web UI at `https://matrix-auth.<domain>/admin`.
