# Security Policy

This repository is a sanitized deployment template. It does not provide a production-hardening guarantee, and operators are responsible for reviewing Terraform plans, Ansible changes, firewall exposure, and secret handling before use.

## Supported Versions

Security fixes are expected to land on the default branch. Tagged releases are snapshots and may lag until a new release is cut.

## Reporting a Vulnerability

Report suspected security issues through the private contact method published on the maintainer GitHub profile when available. If only public GitHub issues are available, report the minimal reproduction without live infrastructure details and ask for a private follow-up path.

Best-effort initial response target: 7 days.

Do not include secrets, tokens, private IPs, account IDs, hostnames, OAuth callback data, pairing codes, backup archives, or live infrastructure details in public reports.

## Operator Responsibilities

- Review `terraform plan` before apply.
- Keep SSH source ranges narrow and remove temporary public bootstrap access.
- Keep runtime env files, OAuth profiles, pairing state, backups, and SSH keys private.
- Pin or consciously accept floating external artifacts before enabling optional stacks.
