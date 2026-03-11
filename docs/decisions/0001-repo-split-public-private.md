# 0001. Split reference patterns from lab instantiation

**Date:** 2026-03-11
**Status:** Accepted

## Context

The lab serves dual purposes: a real working environment and a public demo artifact for blog content.
Mixing real infrastructure values (IPs, hostnames, secrets) with public patterns would either expose sensitive data
or require so much redaction that the repo becomes useless as a demo.

## Decision

Two independent repos, convention-referenced:

- **idealism-as-code** (public): canonical patterns, modules, roles, manifests, ADRs. Variables and examples only.
- **lab-work** (private): actual instantiation. Real topology, encrypted secrets, tfvars pointing at live infra.

The private repo references public modules by GitHub source URL with explicit version tags:
```
github.com/ccovert-lsc/idealism-as-code//modules/foo?ref=vX.Y.Z
```

## Consequences

- Blog readers can inspect the public repo and see exactly what's running
- Secrets never touch the public repo
- Rebuilding from scratch (nuke and re-apply) works cleanly — private repo is the full source of truth for the real environment
- No submodule friction; version alignment is explicit in module source URLs

## Alternatives considered

**Git submodule**: Private repo embeds public as a submodule.
Rejected — adds workflow friction, doesn't improve rebuild story, complicates blog reader experience.

**Single repo with .gitignore**: One repo, ignore the secrets.
Rejected — too easy to accidentally commit real values; harder to share selectively.
