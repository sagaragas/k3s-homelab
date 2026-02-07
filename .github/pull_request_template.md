## What Changed

<!-- Brief description of the changes -->

## Why

<!-- Motivation: bug fix, new app, upgrade, cleanup, etc. -->

## Checklist

- [ ] YAML lint passes (`task test:yaml`)
- [ ] Kubeconform passes (`task test:schema`)
- [ ] Flux validation passes (`task test:flux`)
- [ ] Secrets are SOPS-encrypted (no plaintext in `*.sops.yaml`)
- [ ] DNS entry added/updated on bind9 (if new/changed hostname)
- [ ] AGENTS.md updated (if service inventory changed)
