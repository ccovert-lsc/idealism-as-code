# 0008. SOPS + age for Secret Management

**Date:** 2026-09-19
**Status:** Accepted

## Context

The lab has two repositories: a public reference repo and a private instantiation repo. Kubernetes secrets (database passwords, API keys, Authentik bootstrap credentials, Matrix tokens) must live somewhere on disk and in git. Plaintext is never acceptable. We needed an encryption scheme that:

- Works without a secret manager service (no Vault, no AWS KMS)
- Allows encrypted files to be committed directly to git
- Supports decryption on mgmt-01 and the developer workstation
- Does not require a running Kubernetes cluster to decrypt (unlike Sealed Secrets)

## Decision

Use [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) as the encryption backend. Secrets are stored as SOPS-encrypted YAML files in `secrets/` in the private repo. The `.sops.yaml` configuration file specifies which age public keys can decrypt each file.

Age keys are stored at `~/.config/sops/age/keys.txt` on mgmt-01 and the developer workstation (WSL2). Key material is never committed.

Kubernetes secrets are created from the decrypted output via a pattern like:

```bash
sops -d secrets/foo.enc.yaml | kubectl apply -f -
```

Or, for individual values:
```bash
MY_VAL=$(sops -d secrets/foo.enc.yaml | yq '.key')
kubectl create secret generic my-secret --from-literal=key="$MY_VAL"
```

## Consequences

- Encrypted secrets can be committed to the private git repo — `git log` is safe to share with collaborators with the private repo access.
- Decryption requires the age private key. Loss of the key = loss of access to secrets. Keep a backup.
- No service dependency: decryption works offline on any machine with the key.
- SOPS + age do not support rotation automation — secret rotation is a manual process.

## Alternatives considered

**Sealed Secrets:** Requires a running cluster to decrypt (the SealedSecrets controller holds the private key). Recovery after a cluster wipe requires keeping a backup of the controller key. Rejected because it ties secrets to cluster lifecycle.

**HashiCorp Vault:** More powerful (dynamic secrets, leasing, audit log) but significant operational overhead for a single-operator homelab. Revisit if this grows to a team.

**Plain environment variables / .env files:** Gitignored. Simple but breaks the "everything in git" goal and creates key management problems (where does the .env live?).
