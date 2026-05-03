# OpenClaw VPS Restore Runbook

Use this when rebuilding a deleted or broken OpenClaw VPS from an `openclaw-vps-*.tar.gz` backup.

## Inputs
- Latest root-only backup archive from a secure local backup location or `/var/backups/openclaw-vps/latest.tar.gz`.
- Hetzner token loaded through a secure shell helper or secret store.
- Tailscale login access for the rebuilt server.
- Local config files copied from examples:
  - `templates/ansible/inventory.ini`
  - `templates/ansible/vars/local.yml`
  - `templates/infra/terraform.tfvars`

## Restore Flow
1. Rebuild the VPS through Terraform and the first Ansible bootstrap.
   - Keep `openclaw_enable_service=false` for the first run.
   - Keep bootstrap SSH restricted to the current public `/32`.
2. Copy the backup archive to the new VPS:
   - `scp openclaw-vps-<STAMP>.tar.gz <admin_user>@<NEW_PUBLIC_IP>:/tmp/openclaw-vps-restore.tar.gz`
3. Stop OpenClaw before restoring:
   - `ssh <admin_user>@<HOST> 'sudo docker compose -f /etc/openclaw/docker-compose.yml --profile cli down --remove-orphans || true'`
4. Restore files from the archive:
   - `ssh <admin_user>@<HOST> 'sudo tar -xzf /tmp/openclaw-vps-restore.tar.gz -C /'`
   - This restores `/etc/openclaw`, `/var/lib/openclaw/.openclaw`, `/var/lib/openclaw/workspace`, and `/var/lib/openclaw/.ssh`.
5. Normalize ownership and permissions:
   - `ssh <admin_user>@<HOST> 'sudo chown -R 1000:1000 /var/lib/openclaw/.openclaw /var/lib/openclaw/workspace /var/lib/openclaw/.ssh && sudo chmod 700 /var/lib/openclaw/.ssh && sudo chmod 600 /var/lib/openclaw/.ssh/id_ed25519_github_openclaw 2>/dev/null || true && sudo chown -R root:assistant /etc/openclaw && sudo chmod 750 /etc/openclaw && sudo chmod 640 /etc/openclaw/.env'`
6. Re-run Ansible with OpenClaw enabled:
   - `ansible-playbook -i skills/openclaw-vps/templates/ansible/inventory.ini skills/openclaw-vps/templates/ansible/site.yml`
7. Complete Tailscale-only closure:
   - `sudo tailscale up --hostname=openclaw-vps`
   - verify SSH through Tailscale
   - remove public bootstrap SSH from UFW and Terraform firewall
8. Validate:
   - `ssh <admin_user>@<tailscale-hostname> 'sudo openclaw-vps-status'`
   - If OAuth profiles are missing or expired, rerun OpenAI Codex OAuth and then reapply model routing.
   - If Telegram pairing is missing, send `/start`, list pending pairing, and approve the code.

## Notes
- The backup contains secrets. Keep archive permissions at `0600` and never commit it.
- Do not restore over an actively running OpenClaw container.
- Do not expose gateway ports publicly during restore.
