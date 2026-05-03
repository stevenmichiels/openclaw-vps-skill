# openclaw-vps

Human-facing quick start for the `openclaw-vps` skill used by Codex or another coding agent.

This skill provisions and operates an OpenClaw VPS on Hetzner using Terraform and Ansible. It keeps SSH private by default, deploys OpenClaw in Docker Compose, and includes operational scripts for status checks, backups, release checks, downtime alerts, and Docker cleanup.

For agent instructions, use `SKILL.md`. This README is for humans deciding whether to use, review, or publish the skill.

This repository is a sanitized deployment template, not a copy of a live production VPS configuration.

## Before You Fork or Use This

- Copy the example config files and keep the real files ignored.
- Set `bootstrap_public_ssh_cidr` to your current public IP `/32` for first public bootstrap. The tracked default is empty so Ansible fails before UFW changes if you forget.
- Keep `openclaw_enable_service=false` until `/etc/openclaw/.env` is configured on the VPS.
- Keep Firecrawl disabled unless you need it. Before enabling it, pin Firecrawl image tags/digests or explicitly accept floating images.
- Review `terraform plan` before every apply and stop if the plan replaces the server unexpectedly.
- Decide whether the OpenClaw image pin is still the known-good version you want. This template intentionally uses explicit tags instead of `latest`.

## Design Goals

- Private by default: narrow bootstrap SSH, then Tailscale-only SSH.
- Hardened base setup with firewalling and basic intrusion protection.
- Reviewable infrastructure through Terraform and Ansible.
- Separate runtime SSH key for OpenClaw repository access.
- Operational checks for status, health, backups, releases, and timers.
- Recoverable VPS model with backups and a documented restore path.

## Why This Exists

Running an always-on coding assistant is not just "start a container". The useful part is the operational wrapper around it: safe access, repeatable rebuilds, private secrets, health checks, backups, and a clear recovery path when the VPS disappears or the runtime changes.

This skill turns that into a reusable workflow. It gives an agent enough structure to provision the box, harden it, deploy OpenClaw, wire up approvals, and verify that the result is actually usable.

## Added Value

- Repeatable infrastructure instead of click-by-click server setup.
- SSH guardrails: narrow bootstrap access first, then Tailscale-only SSH.
- Private-by-default gateway ports bound to loopback.
- Secret-safe runtime setup with placeholders, generated gateway token support, and explicit "do not commit" rules.
- Dedicated OpenClaw runtime SSH key for GitHub access, separate from root or admin keys.
- One-command operator checks through `openclaw-vps status`.
- Scheduled backups, Docker cleanup, stable release checks, and downtime/recovery alerts.
- Restore runbook for a fresh VPS rebuild from backup.
- Local config examples so the public skill can stay generic while private machine/account values stay ignored.

## What This Is Not

This is not a hosted service, a turnkey SaaS product, or a substitute for reading Terraform/Ansible plans before applying them. It is an opinionated deployment skill with guardrails, intended for operators who are comfortable reviewing infrastructure changes.

## Threat Model and Assumptions

- Single-operator VPS, not a multi-tenant host.
- Trusted controller machine with Terraform, Ansible, SSH keys, and Hetzner credentials.
- Tailscale network is trusted for admin SSH after bootstrap.
- Public SSH is temporary bootstrap access only and should be restricted to a current `/32`.
- OpenClaw and Firecrawl dashboards/APIs stay private by default through loopback binds and SSH tunnels.
- Secrets live in local secret storage or VPS env files, never in committed templates.

## What It Includes

- Terraform templates for Hetzner server and firewall setup.
- Ansible roles for base hardening, UFW/fail2ban, Docker, Codex CLI, OpenClaw, optional Firecrawl, backups, health checks, and timers.
- A restore runbook in `references/restore.md`.
- Example config files for local deployment values.

## Prerequisites

You need:

- Terraform
- Ansible
- A Hetzner Cloud account and API token
- SSH access from your local machine
- Optional: Tailscale, if you enable private SSH access
- Optional: a GitHub deploy key or SSH key for repository access

## Supply Chain Notes

- Tailscale is installed via the official `tailscale.com/install.sh` script.
- Claude Code installation is optional and uses the official `claude.ai/install.sh` script when enabled.
- Codex CLI installation is optional and uses `npm install -g @openai/codex` when `install_codex_cli=true`.
- OpenClaw uses an explicit known-good GHCR image tag by default and the runtime image is built locally from that base.
- Host systemd mode can install/update `openclaw@latest`; container mode is preferred when you want the pinned image path.
- Firecrawl is disabled by default. Its upstream images should be pinned before enabling, unless you deliberately set `firecrawl_allow_floating_images=true`.
- This template does not auto-upgrade OpenClaw. The release-check helper reports newer stable releases so the operator can review and bump deliberately.

## First-Time Setup

Copy the example files and fill in your local values:

```sh
cp templates/ansible/inventory.ini.example templates/ansible/inventory.ini
cp templates/ansible/vars/local.yml.example templates/ansible/vars/local.yml
cp templates/infra/terraform.tfvars.example templates/infra/terraform.tfvars
```

Example values are intentionally generic. Replace them with your own values locally and keep the resulting files private.

Keep real secrets and private deployment details out of committed files. Provider tokens and bot/API keys belong in secure shell/env storage or on the VPS in `/etc/openclaw/.env`. Do not include `/etc/openclaw/.env` in unencrypted backups, logs, or support bundles.

## Typical Flow

1. Copy the example config files.
2. Add local deployment values.
3. Run `terraform plan` locally and review it.
4. Run `terraform apply` locally only if the plan matches your intent.
5. Update the Ansible inventory with the bootstrap VPS IP first, then the Tailscale hostname after private access is enabled.
6. Run the Ansible playbook locally against the VPS.
7. Verify the deployment on the VPS with `openclaw-vps status`.
8. Verify timers for backups, Docker cleanup, release checks, and health checks.

## Recovery Model

The VPS is treated as replaceable infrastructure. Persistent state should live in backups, Git remotes, or explicitly documented storage paths.

If the VPS is lost, the expected recovery path is:

1. Recreate infrastructure with Terraform.
2. Re-run Ansible.
3. Restore OpenClaw state from backup.
4. Re-check health, timers, gateway access, and repository access.

## Local Files You Must Not Share

Do not commit or share:

- `templates/ansible/inventory.ini`
- `templates/ansible/vars/local.yml`
- `templates/infra/terraform.tfvars`
- `templates/infra/terraform.tfstate*`
- `templates/infra/tfplan*`
- `templates/infra/.terraform/`
- `templates/ansible/ansible-run.log`
- backup archives, OAuth profiles, pairing state, or SSH keys

These should be ignored by `.gitignore` in this repo. Verify before committing.

## Basic Commands

Terraform commands run locally from this repository. Always inspect the Terraform plan before applying it:

```sh
terraform -chdir=templates/infra init
terraform -chdir=templates/infra plan
terraform -chdir=templates/infra apply
```

Ansible commands run locally and target the VPS:

```sh
cd templates/ansible
ansible-playbook -i inventory.ini site.yml
```

The `openclaw-vps ...` operator commands run on the VPS after deployment:

```sh
openclaw-vps status
openclaw-vps timers
openclaw-vps release-check
openclaw-vps healthcheck
openclaw-vps backup
```

## Acknowledgements

This template was partly inspired by public discussions around running coding agents on always-on VPS infrastructure, including [a post by @levelsio](https://x.com/levelsio/status/2019056230866595874). The implementation, hardening choices, and operational wrapper are specific to this project.

## Sharing Checklist

Before sharing this skill:

```sh
git status --short --ignored .
git grep -n -I -E 'BEGIN .*PRIVATE KEY|OPENAI_API_KEY=.+|ANTHROPIC_API_KEY=.+|GITHUB_TOKEN=.+|GH_TOKEN=.+|TELEGRAM_BOT_TOKEN=.+|SLACK_.*TOKEN=.+|OPENCLAW_GATEWAY_TOKEN=.+|HCLOUD_TOKEN=.+' -- . || true
git ls-files . | rg '(^|/)(inventory\.ini|terraform\.tfstate|terraform\.tfvars|tfplan|ansible-run\.log|local\.yml)$|\.terraform/' || true
```

The first command should show private deployment files only as ignored. The last two commands should not print real secrets or local deployment files. Add your own usernames, hostnames, account labels, and local path fragments to the grep before publishing publicly.
