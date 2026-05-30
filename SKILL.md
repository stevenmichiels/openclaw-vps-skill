---
name: openclaw-vps
description: Provision and harden a Hetzner VPS with Terraform and Ansible, then deploy OpenClaw as an always-on assistant (Docker compose by default, optional host systemd mode). Use when setting up or operating OpenClaw on a cloud VPS with strict SSH/firewall guardrails, secret-safe env management, and repeatable service lifecycle steps.
---

# SKILL: openclaw-vps (Hetzner + Terraform + Ansible + OpenClaw)

## Purpose
Provision and harden a Hetzner Cloud VPS in a repeatable, safe-by-default workflow:
- Terraform: server + Hetzner firewall
- Ansible: base config + security (UFW + fail2ban + unattended-upgrades)
- Baseline tools: Docker, Docker Compose v2 (`docker-compose-v2` package), jq, screen, Python 3/pipx, GitHub CLI (`gh`)
- Optional: install Claude Code on the VPS
- Optional: install Codex CLI on the VPS
- Deploy OpenClaw as a non-root service account
  - default runtime: Docker Compose (`openclaw-gateway` + `openclaw-cli`)
  - optional runtime: host systemd (`openclaw gateway ...`)

## Source-of-truth rule
- Treat OpenClaw official docs and upstream repo as source of truth for runtime behavior.
- If this skill/template drifts from upstream OpenClaw semantics, update templates before deploy.

## OpenClaw image release policy
- Use a known-good stable GitHub Release and keep deployments pinned to an explicit GHCR tag.
- The tracked default may intentionally lag upstream latest until runtime behavior is reviewed.
- Do not use floating `latest` for the VPS service; repeatability matters more than surprise upgrades.
- Before bumping `openclaw_container_image`:
  - check `https://github.com/openclaw/openclaw/releases` for the latest non-draft, non-prerelease release
  - translate release tag `vYYYY.M.DD` to GHCR tag `YYYY.M.DD`
  - verify the container tag exists, e.g. `docker manifest inspect ghcr.io/openclaw/openclaw:<TAG>`
  - update `SKILL.md`, `templates/ansible/site.yml`, role defaults, and compose/env templates together
  - deploy with `openclaw_compose_pull=true`, then validate health, ports, service list, and model routing
- If the latest stable release changes runtime semantics, patch the template first and capture the learning before declaring the bump done.

## Core operating workflow
1) Identify request type first: access, infra change, config change, runtime/service change, or assistant capability change.
2) Load and compare current local artifacts before changing anything:
   - `openclaw-vps/SKILL.md`
   - `openclaw-vps/LEARNINGS.md`
   - `openclaw-vps/templates/infra/*`
   - `openclaw-vps/templates/ansible/site.yml`
   - `openclaw-vps/templates/ansible/roles/openclaw/*`
3) Confirm whether change is Terraform, Ansible, or both.
4) If requirements are missing, ask targeted questions and capture outcomes in `LEARNINGS.md`.
5) Execute smallest safe change first, then validate with concrete health checks.

## Local config and sharing rule
- The tracked skill must stay generic and shareable. Keep machine/account-specific values in ignored local files.
- Copy examples before first use:
  - `templates/ansible/inventory.ini.example` -> `templates/ansible/inventory.ini`
  - `templates/ansible/vars/local.yml.example` -> `templates/ansible/vars/local.yml`
  - `templates/infra/terraform.tfvars.example` -> `templates/infra/terraform.tfvars`
- `templates/ansible/site.yml` automatically loads `templates/ansible/vars/local.yml` when present.
- Do not commit local inventory, local Ansible vars, Terraform tfvars/state/plans, Ansible logs, backup archives, OAuth profiles, pairing state, or SSH keys.
- Put only non-secret identity values in local config, such as `admin_user`, Tailscale hostname, SSH key path, GitHub SSH key title/alias, and host repo directory.

## Core principle
- Never expose SSH to the whole internet.
- Bootstrap with a narrow allow-list (your current public IP `/32`) or via Hetzner Console.
- After Tailscale is up, tighten rules to Tailscale-only.

## Access discipline
- Prefer Tailscale-only SSH.
- Avoid root login unless explicitly requested and still enabled.
- Do not change SSH/80/443 public exposure without explicit approval.
- A fresh rebuild is not complete until Tailscale SSH is proven and public bootstrap SSH is removed from both UFW and the Hetzner firewall.

## Hard safety rules (never violate)
1) Never leave SSH open to the whole internet. SSH must be restricted to bootstrap CIDR `/32` and later to Tailscale-only.
2) Never enable UFW without first adding allow rules that preserve access (bootstrap + tailscale).
3) Root login disable is a two-step gate:
   - first run uses `disable_root_login=false`
   - only set `disable_root_login=true` after validating non-root SSH (`ssh <admin_user>@<ip> "echo OK"`)
4) Never enable password login. Keep `PasswordAuthentication no`.
5) Never print secrets. Never commit tokens/keys (`OPENCLAW_GATEWAY_TOKEN`, provider keys, channel tokens).
6) Never enable OpenClaw service while env placeholders remain (`__SET_ME__`).
7) Keep gateway private by default: bind ports to loopback (`127.0.0.1`) and access via SSH tunnel.
8) First bootstrap run must set `bootstrap_public_ssh_cidr` to your current public IP `/32`.
9) For existing servers, never apply Terraform if plan shows `hcloud_server` destroy/replace unless rebuild is explicitly intended.
10) Keep deterministic artifacts as source of truth: Terraform + Ansible templates in this skill.
11) Do not expose `/root/.ssh` to OpenClaw runtime. Use dedicated runtime SSH key in `/var/lib/openclaw/.ssh`.

## Credential loading (Hetzner token)
- Preferred/default path for local controller work: use the protected `hctf` wrapper when available.
- `hctf` loads the Hetzner token from macOS Keychain service `hcloud-token` and injects `HCLOUD_TOKEN` plus `TF_VAR_hcloud_token` only into one Terraform child process.
- Safe plan example: `hctf -chdir=templates/infra plan -input=false`.
- Allowed helper subcommands should be limited to `fmt`, `init`, `validate`, `plan`, `show`, `state`, `import`, `providers`, `output`, and `version`.
- The helper must refuse `apply` and `destroy`; Steven applies manually after reviewing an approved saved plan.
- If `hctf` is unavailable, export `TF_VAR_hcloud_token` from a secure source for one command only. Never print the token, use command substitution around token helpers, or commit tfvars/state/plans.
- Optional macOS Keychain storage, outside the repo: `security add-generic-password -a "$USER" -s hcloud-token -w '<paste-token-here>'`.

## GitHub CLI on VPS (optional, recommended for repo operations)
- Install:
  - `sudo apt-get update -y && sudo apt-get install -y gh`
- Authenticate (device flow, stable on remote shells):
  - `gh auth login -h github.com -p https -w --insecure-storage`
- If adding SSH keys via `gh ssh-key add`, ensure scope includes `admin:public_key`:
  - `gh auth refresh -h github.com -s admin:public_key --insecure-storage`
- Generate a VPS admin-user GitHub SSH key for host-side repo operations when needed:
  - set `github_admin_ssh_key_path`, `github_admin_ssh_key_title`, and `github_admin_host_alias` in local config
  - `ssh-keygen -t ed25519 -f <github_admin_ssh_key_path> -C "<github_admin_ssh_key_title>" -N ""`
  - add a dedicated host alias in `~/.ssh/config`, e.g. `Host <github_admin_host_alias>` -> `HostName github.com`, `User git`, `IdentityFile <github_admin_ssh_key_path>`, `IdentitiesOnly yes`
  - add the public key to the matching GitHub account or as a repo deploy key before expecting `ssh -T <github_admin_host_alias>` to succeed.
- Generate a dedicated OpenClaw runtime GitHub SSH key (if missing):
  - set `github_runtime_ssh_key_title` in local config
  - `sudo ssh-keygen -t ed25519 -f /var/lib/openclaw/.ssh/id_ed25519_github_openclaw -C "<github_runtime_ssh_key_title>" -N ""`
  - `sudo chown -R 1000:1000 /var/lib/openclaw/.ssh && sudo chmod 700 /var/lib/openclaw/.ssh`
- Add the runtime key to GitHub with explicit title:
  - `gh ssh-key add /var/lib/openclaw/.ssh/id_ed25519_github_openclaw.pub -t "<KEY_TITLE>"`
- Ensure runtime SSH always uses that key:
  - create/update `/var/lib/openclaw/.ssh/config` with:
    - `Host github.com`
    - `HostName github.com`
    - `User git`
    - `IdentityFile /home/node/.ssh/id_ed25519_github_openclaw`
    - `IdentitiesOnly yes`
- Optional switch after key setup:
  - `gh config set -h github.com git_protocol ssh`
- Validate:
  - `gh auth status -h github.com`
  - host-side alias: `ssh -T <github_admin_host_alias>`
  - runtime key only: `sudo docker exec openclaw-openclaw-gateway-1 sh -lc 'command -v ssh && ssh -T -o StrictHostKeyChecking=accept-new git@github.com'`
  - if the OpenClaw image lacks `ssh`, do not claim runtime GitHub SSH is ready; use host-side Git operations or install/provide an image with `openssh-client`.

## Inputs / knobs (Ansible)
- `admin_user` (default: `admin`; set your real admin user in `templates/ansible/vars/local.yml`)
- `admin_authorized_keys` (default: `[]`; required before `disable_root_login=true`)
- `admin_user_passwordless_sudo` (default: `true`)
- `disable_root_login` (default: `false`)
- `tailscale_ssh_source_cidr` (default: `100.64.0.0/10`)
- `bootstrap_public_ssh_cidr` (repo default: `""`; first public bootstrap must set your current public IP `/32`)
- `bootstrap_public_ssh_cidr_cleanup` (default: `""`; optional)
- `allow_http`, `allow_https` (defaults: `false`)
- `enable_fail2ban_sshd` (default: `true`)
- `swap_enabled` (repo default: `true`)
- `swap_file_path` (repo default: `/swapfile`)
- `swap_size_mb` (repo default: `4096`)
- `swap_swappiness` (repo default: `10`)
- `install_claude_code` (default: `false`)
- `refresh_claude_code` (default: `false`)
- `install_codex_cli` (default: `false`; opt-in external npm install)
- `install_openclaw` (default: `true`)
- `install_firecrawl` (repo default: `false`; optional private Firecrawl stack)
- `openclaw_enable_service` (repo default: `false`; set `true` after `/etc/openclaw/.env` secrets are ready)
- `openclaw_runtime_mode` (default: `container`; one of `container`, `systemd`)
- `openclaw_update_cli` (default: `false`; systemd mode CLI refresh toggle)
- `openclaw_cli_path` (default: `/usr/bin/openclaw`)
- `openclaw_user`, `openclaw_group` (default: `assistant`)
- `openclaw_dir` (default: `/opt/openclaw`)
- `openclaw_data_dir` (default: `/var/lib/openclaw`)
- `openclaw_config_dir` (default: `/var/lib/openclaw/.openclaw`)
- `openclaw_workspace_dir` (default: `/var/lib/openclaw/workspace`)
- `openclaw_ssh_dir` (default: `/var/lib/openclaw/.ssh`; mounted to runtime `/home/node/.ssh`)
- `openclaw_env_dir`, `openclaw_env_file` (defaults: `/etc/openclaw`, `/etc/openclaw/.env`)
- `openclaw_service_name` (default: `openclaw`)
- `openclaw_compose_file` (default: `/etc/openclaw/docker-compose.yml`)
- `openclaw_gateway_bind` (default: `lan` for container mode)
- `openclaw_gateway_bind_address` (default: `127.0.0.1`)
- `openclaw_gateway_port` (default: `18789`)
- `openclaw_bridge_port` (default: `18790`)
- `openclaw_gateway_allow_unconfigured` (default: `false`)
- `openclaw_auto_generate_gateway_token` (default: `false`; opt-in auto-generate `OPENCLAW_GATEWAY_TOKEN` when missing/placeholder)
- `openclaw_container_base_image` (repo default: `ghcr.io/openclaw/openclaw:2026.5.2`; pinned upstream image)
- `openclaw_container_image` (repo default: `openclaw-runtime:2026.5.2-tools`; local derived image with `openssh-client`, Python, matplotlib, NumPy, and fonts)
- `openclaw_build_runtime_image` (repo default: `true`; container mode)
- `openclaw_runtime_image_rebuild` (repo default: `false`; force rebuild toggle)
- `openclaw_chart_media_enabled` (repo default: `true`; installs channel-safe chart/media helper and workspace skill)
- `openclaw_tz` (default: `UTC`)
- `openclaw_compose_pull` (default: `false`)
- `openclaw_backup_dir` (repo default: `/var/backups/openclaw-vps`)
- `openclaw_backup_retention_days` (repo default: `14`)
- `openclaw_backup_timer_enabled` (repo default: `true`)
- `openclaw_docker_cleanup_timer_enabled` (repo default: `true`)
- `openclaw_release_check_timer_enabled` (repo default: `true`; checks for newer stable releases, no auto-upgrade)
- `openclaw_release_check_on_calendar` (repo default: `daily`)
- `openclaw_healthcheck_timer_enabled` (repo default: `true`; Telegram transition alerts)
- `openclaw_healthcheck_on_calendar` (repo default: `*:0/5`)
- `openclaw_monitor_state_dir` (repo default: `/var/lib/openclaw-vps-monitor`)
- `openclaw_cost_profile_enabled` (default: `true`; container mode)
- `openclaw_cost_profile_cache_retention` (default: `short`; `none|short|long`)
- `openclaw_cost_profile_context_pruning_ttl` (default: `55m`)
- `openclaw_cost_profile_heartbeat_every` (default: `55m`; use `0m` to disable)
- `openclaw_cost_profile_heartbeat_light_context` (default: `true`)
- `openclaw_cost_profile_heartbeat_isolated_session` (default: `true`)
- `openclaw_cost_profile_heartbeat_target` (default: `slack`)
- `openclaw_cost_profile_heartbeat_model` (default: `""`; optional override)
- `openclaw_codex_plugin_enabled` (repo default: `true`; keeps the bundled Codex plugin available)
- `openclaw_agent_runtime_id` (repo default: `""`; verified ChatGPT/Codex subscription route on pinned 2026.5.2)
- `openclaw_cost_profile_model_primary` (repo default: `openai-codex/gpt-5.5`; verified ChatGPT/Codex subscription route on pinned 2026.5.2)
- `openclaw_cost_profile_model_fallbacks` (repo default: `[]`)
- Firecrawl knobs:
  - `firecrawl_enable_service` (repo default: `false`)
  - `firecrawl_allow_floating_images` (repo default: `false`; set `true` only when deliberately accepting `latest`)
  - `firecrawl_env_dir`, `firecrawl_env_file` (defaults: `/etc/firecrawl`, `/etc/firecrawl/firecrawl.env`)
  - `firecrawl_dir`, `firecrawl_compose_file` (defaults: `/opt/firecrawl`, `/opt/firecrawl/docker-compose.yml`)
  - `firecrawl_api_bind_address` (repo default: `127.0.0.1`)
  - `firecrawl_api_port`, `firecrawl_internal_port` (repo defaults: `3002`)
  - `firecrawl_image`, `firecrawl_playwright_image`, `firecrawl_postgres_image`
  - `firecrawl_postgres_user` (repo default: `firecrawl`)
  - `firecrawl_postgres_db` (must be `postgres` with upstream `nuq-postgres`)
  - `firecrawl_openclaw_network` (repo default: `openclaw_default`; exposes only the Firecrawl API service to OpenClaw)
  - `firecrawl_auto_generate_secrets` (repo default: `true`)
  - `firecrawl_compose_pull` (repo default: `false`)
  - low-concurrency knobs: `firecrawl_num_workers_per_queue`, `firecrawl_crawl_concurrent_requests`, `firecrawl_max_concurrent_jobs`, `firecrawl_browser_pool_size`, CPU/memory limits, `firecrawl_block_media`, `firecrawl_logging_level`

## Inputs / knobs (Terraform)
- `server_name`, `image`, `server_type`, `location`
- `ssh_key_names` (list)
- `ssh_source_ips` (list)
  - safe bootstrap default: only your public IP `/32`
  - after Tailscale: `100.64.0.0/10`
- `allow_http`, `allow_https` (bool)
- Existing-server caution: changing `server_name` or `ssh_key_names` may force replacement.

## Terraform change discipline
- Treat `templates/infra/terraform.tfvars` as current server definition.
- Always run `terraform plan` before apply.
- If plan shows `hcloud_server` replacement (destroy/create), stop and ask before apply.
- Treat `server_name` and `ssh_key_names` as immutable unless rebuild is explicitly intended.

## Deployment workflow
1) Configure Terraform variables and bootstrap SSH CIDR.
2) Run `terraform -chdir=templates/infra init`, `plan`, then `apply`.
3) Set generated VPS IP in `templates/ansible/inventory.ini`.
4) First Ansible run (fresh bootstrap) with:
   - `disable_root_login=false`
   - `openclaw_enable_service=false`
   - `bootstrap_public_ssh_cidr=<your public IP /32>`
5) Edit `/etc/openclaw/.env` on VPS and replace `__SET_ME__` plus provider/channel keys.
   - Set `OPENCLAW_GATEWAY_TOKEN` to a strong random value (must not stay `placeholder`).
   - Token generation example (safe output handling): `openssl rand -hex 32`
   - Optional automation: set `openclaw_auto_generate_gateway_token=true` and rerun playbook; role auto-generates token if value is `__SET_ME__`, `placeholder`, empty, or missing.
   - Verified ChatGPT/Codex subscription route on pinned 2026.5.2: use `openai-codex/gpt-5.5`, leave `agents.defaults.agentRuntime` unset, and run `openai-codex` OAuth login (no `OPENAI_API_KEY` needed).
   - Legacy pinned 2026.4.29 fallback: use `openai-codex/gpt-5.4`, leave `agents.defaults.agentRuntime` unset, and run `openai-codex` OAuth login.
   - API-key mode: use `openai/*` models with `OPENAI_API_KEY` and do not force the Codex runtime.
6) Enable runtime:
   - set `openclaw_enable_service=true`
   - rerun `ansible-playbook -i inventory.ini site.yml`
7) For OpenAI Codex OAuth (ChatGPT subscription path), complete provider login:
   - container mode:
     - browser callback flow: `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli models auth login --provider openai-codex`
     - headless/device-code flow: `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli models auth login --provider openai-codex --device-code`
   - systemd mode:
     - browser callback flow: `sudo -u assistant -H /usr/bin/openclaw models auth login --provider openai-codex`
     - headless/device-code flow: `sudo -u assistant -H /usr/bin/openclaw models auth login --provider openai-codex --device-code`
   - when launching from laptop over SSH, force TTY end-to-end:
     - `ssh -tt <host-alias> 'sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli models auth login --provider openai-codex --device-code'`
   - if browser lands on `http://localhost:1455/auth/callback?...` with `ERR_CONNECTION_REFUSED`:
     - this is expected when CLI runs on VPS but browser runs on your laptop
     - only continue when callback `state` matches the state from the currently running login attempt
     - preferred input when the wrapper prompt is flaky: paste only the `code` value
     - fallback input: paste the full query string (`code=...&scope=...&state=...`)
     - if driving the prompt through Codex/a PTY and normal paste submits as `Required`, submit the code with bracketed paste: `<ESC>[200~<CODE><ESC>[201~<Enter>`
     - if callback shows `error=invalid_state` or empty/mismatched `state`: cancel login (`Ctrl+C`), rerun login, and use the new callback URL/state pair
     - treat callback query data/code as sensitive and single-use
   - after successful login, reapply the desired subscription runtime/profile and restart the gateway:
     - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config set plugins.entries.codex '{"enabled":true}' --strict-json --merge`
     - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config set agents.defaults.model.primary openai-codex/gpt-5.5`
     - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config unset agents.defaults.agentRuntime`
     - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config set agents.defaults.model.fallbacks '[]' --strict-json`
     - `sudo docker compose -f /etc/openclaw/docker-compose.yml restart openclaw-gateway`
8) Validate non-root SSH, then set `disable_root_login=true` and rerun playbook.
9) Close bootstrap SSH to Tailscale-only:
   - run `sudo tailscale up --hostname=openclaw-vps` if `tailscale status` says logged out
   - verify `tailscale ip -4` returns a `100.x` address
   - verify SSH via the Tailscale IP or DNS name succeeds
   - remove the public bootstrap `/32` from UFW
   - set Terraform `ssh_source_ips=["100.64.0.0/10"]` and apply only if the plan is firewall-only with no server replacement
   - verify public IPv4 SSH times out, UFW only allows `22/tcp` from `100.64.0.0/10`, and Terraform plan is no-op

### Local VPS profile
- The tracked repository does not contain a real inventory host or personal SSH key path.
- Keep the active inventory in ignored `templates/ansible/inventory.ini`.
- Keep environment-specific Ansible overrides in ignored `templates/ansible/vars/local.yml`.
- Keep Terraform deployment values in ignored `templates/infra/terraform.tfvars`.
- For an existing Tailscale-only VPS, persist `bootstrap_public_ssh_cidr: "100.64.0.0/10"` in local vars only after Tailscale SSH is proven and root login is disabled.
- In Terraform tfvars, persist `ssh_source_ips = ["100.64.0.0/10"]` after Tailscale SSH is proven; public bootstrap `/32` SSH must only be reintroduced temporarily for break-glass access.
- `openclaw_enable_service=false` in tracked defaults means plain `ansible-playbook -i inventory.ini site.yml` prepares the host but does not start the OpenClaw stack until local vars opt in.
- Runtime image is a local derivative of the pinned upstream OpenClaw image:
  - base: `ghcr.io/openclaw/openclaw:2026.5.2`
  - runtime: `openclaw-runtime:2026.5.2-tools`
  - purpose: add `openssh-client` for the dedicated runtime GitHub SSH key, plus Python/matplotlib/NumPy/fonts for channel-safe chart rendering.
- Cost routing defaults are persisted to:
  - primary: `openai-codex/gpt-5.5`
  - agent runtime: unset
  - fallback(s): `[]`

## Ansible change discipline
- Treat `templates/ansible/site.yml` as desired state.
- Keep runtime secrets only in `/etc/openclaw/.env` (never commit secrets).
- Before assuming service changes deploy, verify role presence in site:
  - ensure `role: openclaw` exists in `templates/ansible/site.yml`
  - if role is missing/disabled, call it out explicitly.
- For runtime mode changes (`container` <-> `systemd`), rerun full playbook and verify service state after switch.

## Runtime model details
### Container mode (default)
- Uses Docker Compose file at `/etc/openclaw/docker-compose.yml`.
- Runs upstream-style services:
  - `openclaw-gateway`
  - `openclaw-cli`
- Uses `openclaw_gateway_bind=lan` so Docker-published host loopback health/dashboard access works.
- Keeps host exposure private via `openclaw_gateway_bind_address=127.0.0.1`.
- Role ensures Docker-required gateway config before start:
  - `gateway.mode=local`
  - `gateway.bind=<openclaw_gateway_bind>`
  - `gateway.controlUi.allowedOrigins` includes localhost + 127.0.0.1 on gateway port.
- Role can also enforce an optional cost profile in `openclaw.json` (container mode):
  - `agents.defaults.params.cacheRetention`
  - `agents.defaults.contextPruning.mode=cache-ttl` + `ttl`
  - `agents.defaults.heartbeat.*` (every/lightContext/isolatedSession/target/model)
  - optional `agents.defaults.model.primary` + `fallbacks`
- Repo runtime image is a local derivative (`openclaw-runtime:2026.5.2-tools`) that keeps the upstream release pinned (`ghcr.io/openclaw/openclaw:2026.5.2`) but adds `openssh-client`, Python, matplotlib, NumPy, and fonts.

## Operational must-haves
- `openclaw-vps status` is the friendly wrapper around `openclaw-vps-status`; use it as the default operator command.
- `openclaw-vps-status` is the one-command healthcheck. It validates Tailscale, gateway health, loopback ports, model routing, Telegram API reachability, runtime GitHub SSH readiness, chart/media readiness, latest backup age, disk threshold, Docker log limits, and timers.
- `openclaw-vps-backup` writes root-only archives to `/var/backups/openclaw-vps` and keeps `latest.tar.gz` updated.
- `openclaw-docker-cleanup` prunes stopped containers, unused images, and build cache on a timer. It intentionally does not prune volumes.
- `openclaw-vps release-check` checks GitHub Releases for the newest stable OpenClaw release and verifies the matching GHCR tag exists; it alerts through Telegram when a newer stable tag appears but never auto-upgrades.
- `openclaw-vps healthcheck` runs the full status check and sends Telegram alerts only on health transitions (`healthy` -> `unhealthy`, then recovery).
- Restore runbook: read `references/restore.md` before rebuilding from backup.

## OpenAI auth/runtime mapping
- Verified ChatGPT/Codex subscription route on pinned OpenClaw 2026.5.2:
  - auth profile: `openai-codex` OAuth (`openclaw models auth login --provider openai-codex`, add `--device-code` on headless VPS flows)
  - model ref: `openai-codex/gpt-5.5`
  - runtime: leave `agents.defaults.agentRuntime` unset
  - plugin: `plugins.entries.codex={"enabled":true}` is allowed but not the routing mechanism
  - no `OPENAI_API_KEY` required for this mode
- Direct OpenAI API-key route:
  - model ref: `openai/gpt-5.5`
  - auth mode: API key
  - required env: `OPENAI_API_KEY`
  - set `openclaw_agent_runtime_id: ""` and usually `openclaw_codex_plugin_enabled: false`
- Native Codex runtime route documented upstream but not validated in this deployment:
  - model ref: `openai/gpt-5.5`
  - runtime: `agents.defaults.agentRuntime.id=codex`
  - observed failure on this VPS: `No API key found for provider "openai"; use openai-codex/gpt-5.5`
  - do not use until a real `openclaw agent ... --json` run proves it uses auth-profile mode
- Legacy OpenClaw 2026.4.29 subscription fallback:
  - model ref: `openai-codex/gpt-5.4`
  - runtime: leave `agents.defaults.agentRuntime` unset
  - only use if the 2026.5.2 `openai-codex/gpt-5.5` route fails validation or if the deployment is intentionally pinned to 2026.4.29

## Channel-safe chart/media output
- Use this path when Telegram/Slack requests need a chart, plot, graph, image, figure, or generated media.
- Do not rely on Canvas as the primary delivery mechanism for chat channels; Canvas can fail even when the agent response succeeds.
- The role installs:
  - workspace skill: `/var/lib/openclaw/workspace/skills/chart-media/SKILL.md`
  - container path: `/home/node/.openclaw/workspace/skills/chart-media/SKILL.md`
  - helper: `/var/lib/openclaw/workspace/scripts/render_chart.py`
  - container helper: `/home/node/.openclaw/workspace/scripts/render_chart.py`
  - output directory: `/var/lib/openclaw/workspace/out`
- For simple charts, write a JSON chart spec under `/home/node/.openclaw/workspace/out` and run:
  - `python3 /home/node/.openclaw/workspace/scripts/render_chart.py --input out/chart-spec.json --output out/chart.png`
- For custom plots, write a short Python script using `matplotlib.use("Agg")` and save PNG output under `/home/node/.openclaw/workspace/out`.
- Final chat response must include a media attachment line on its own line:
  - `MEDIA:/home/node/.openclaw/workspace/out/<file>.png`
- Validate after deployment:
  - `sudo openclaw-vps status`
  - direct runtime smoke test: `sudo docker exec openclaw-openclaw-gateway-1 python3 /home/node/.openclaw/workspace/scripts/render_chart.py --self-test --output out/chart-media-self-test.png`

### Systemd mode (optional)
- Installs/updates OpenClaw CLI via npm (`openclaw@latest`) when needed.
- Runs gateway with systemd unit `/etc/systemd/system/<openclaw_service_name>.service`.
- Uses environment file `/etc/openclaw/.env`.

## OpenClaw channel bootstrap (Telegram and Slack)
- Required before channel setup:
  - `OPENCLAW_GATEWAY_TOKEN` must be set in `/etc/openclaw/.env` and not be `placeholder`.
  - quick check (no secret printed):
    - `sudo bash -lc 'v=$(grep -E "^OPENCLAW_GATEWAY_TOKEN=" /etc/openclaw/.env | cut -d= -f2- || true); [ -n "$v" ] && [ "$v" != "placeholder" ] && echo "OPENCLAW_GATEWAY_TOKEN=set" || echo "OPENCLAW_GATEWAY_TOKEN=missing_or_placeholder"'`
- Container mode env rule:
  - editing `/etc/openclaw/.env` is not enough for an already-created container
  - `docker compose restart` keeps the old container environment
  - after token/env changes, recreate the gateway:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml up -d --force-recreate openclaw-gateway`
  - verify from inside the running container without printing secrets:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml exec -T openclaw-gateway sh -lc 'test -n "${TELEGRAM_BOT_TOKEN:-}" && echo TELEGRAM_BOT_TOKEN=set || echo TELEGRAM_BOT_TOKEN=missing'`
### Telegram
- Set `TELEGRAM_BOT_TOKEN` in `/etc/openclaw/.env`.
- In container mode, recreate `openclaw-gateway` after changing the token, then verify the running container sees it.
- Start gateway runtime, then complete pairing:
  - host/systemd mode:
    - `openclaw pairing list telegram`
    - `openclaw pairing approve telegram <CODE>`
  - container mode:
    - `docker compose -f /etc/openclaw/docker-compose.yml run --rm openclaw-cli pairing list telegram`
    - `docker compose -f /etc/openclaw/docker-compose.yml run --rm openclaw-cli pairing approve telegram <CODE>`
- Pairing/allow-list flow:
  - if Telegram replies `OpenClaw: access not configured`, transport is working but sender approval is still pending
  - ask user to send `/start` first to generate/update the pending pairing request
  - list pending requests:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli pairing list telegram`
  - approve with code from list:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli pairing approve telegram <CODE>`
  - expected state files:
    - pending requests: `/var/lib/openclaw/.openclaw/credentials/telegram-pairing.json`
    - approved senders: `/var/lib/openclaw/.openclaw/credentials/telegram-default-allowFrom.json`
  - no manual Telegram user ID input is required when the pairing request is present.
- Pairing is done when:
  - `pairing list telegram` shows `No pending telegram pairing requests.`
  - `/var/lib/openclaw/.openclaw/credentials/telegram-default-allowFrom.json` contains your Telegram user ID.
  - a real Telegram test message gets a bot reply.

### Slack
- Set both `SLACK_APP_TOKEN` and `SLACK_BOT_TOKEN` in `/etc/openclaw/.env`.
- In container mode, ensure compose env pass-through exists for channel tokens in:
  - `templates/ansible/roles/openclaw/templates/docker-compose.yml.j2`
  - both `openclaw-gateway` and `openclaw-cli` must include:
    - `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`
  - without this mapping, `.env` values do not reach the running container.
- Enable Slack channel config:
  - container mode:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config set channels.slack.enabled true --strict-json`
  - systemd mode:
    - `sudo -u assistant -H /usr/bin/openclaw config set channels.slack.enabled true --strict-json`
- Apply channel config/env changes:
  - container mode:
    - after config-only changes, restart is enough:
      - `sudo docker compose -f /etc/openclaw/docker-compose.yml restart openclaw-gateway`
    - after `/etc/openclaw/.env` changes, recreate is required:
      - `sudo docker compose -f /etc/openclaw/docker-compose.yml up -d --force-recreate openclaw-gateway`
  - systemd mode:
    - `sudo systemctl restart openclaw`
- Slack app config required for replies:
  - OAuth bot scopes:
    - required for channel mentions: `app_mentions:read`, `chat:write`
    - required for DM message events: `im:history`
    - required for native exec approval DM delivery in some workspaces: `im:write` (keep `chat:write`)
    - optional broader channel history scopes when needed: `channels:history`, `groups:history`, `mpim:history`
  - Event subscriptions:
    - recommended mention-mode setup: `app_mention` + `message.im`
    - avoid enabling `app_mention` together with `message.channels` / `message.groups` unless intentionally handling dedupe, otherwise mentions can produce duplicate replies
    - channel-wide (non-mention) mode requires:
      - events: `message.channels` and/or `message.groups`
      - scopes: `channels:history` and/or `groups:history`
      - OpenClaw channel route with `requireMention=false` for the target channel(s)
  - after scope/event changes, reinstall the Slack app to workspace.
- Explicit channel routing fallback (when DM works but channel mention stays silent):
  - set `channels.slack.groupPolicy="open"`
  - set `channels.slack.channels.<CHANNEL_ID>={"enabled":true,"requireMention":true}`
  - restart gateway and confirm log signals:
    - `channels resolved: <CHANNEL_ID>→<name>`
    - `delivered reply to channel:C...`
- Pairing/allow-list flow:
  - if Slack replies `OpenClaw: access not configured`, channel connectivity works but sender approval is pending
  - approve with:
    - `sudo docker exec -it openclaw-openclaw-gateway-1 node dist/index.js pairing approve slack <CODE>`
  - expected state files:
    - pending requests: `/var/lib/openclaw/.openclaw/credentials/slack-pairing.json`
    - approved senders: `/var/lib/openclaw/.openclaw/credentials/slack-default-allowFrom.json`
  - once approved, re-running approve for the same code should report no pending request.
- Native Slack exec approvals for tool calls:
  - set:
    - `channels.slack.execApprovals.enabled=true`
    - `channels.slack.execApprovals.approvers=["<YOUR_SLACK_USER_ID>"]`
  - verify:
    - `sudo jq -c '.channels.slack.execApprovals' /var/lib/openclaw/.openclaw/openclaw.json`
  - if logs show `slack exec approvals: ... missing_scope`, add missing Slack scopes (typically `im:write`) and reinstall app.

## X extraction (runtime-safe, article-aware)
- Prefer running X fetches inside `openclaw-openclaw-gateway-1` so runtime env matches Telegram/Codex execution context.
- Container workspace script path:
  - `/home/node/.openclaw/workspace/scripts/x_fetch_user_tweets.py`
- Host workspace script path:
  - `/var/lib/openclaw/workspace/scripts/x_fetch_user_tweets.py`
- In container mode, do not assume `/etc/openclaw/.env` exists inside the container.
  - host-side sourcing: valid (`set -a; source /etc/openclaw/.env; set +a`)
  - container-side: use injected env (`printenv X_BEARER_TOKEN`)
- For article-style posts (short `text` + `x.com/i/article/...`), request article fields and expansions:
  - `tweet.fields` must include `article` (plus `note_tweet`, `public_metrics`, etc.)
  - `expansions` should include `article.cover_media,article.media_entities`
  - include `media.fields` to hydrate article media
- Normalize content fallback in tooling:
  - `full_text = note_tweet.text // article.plain_text // text`
- Persist result files under workspace `X/` (default):
  - `/var/lib/openclaw/workspace/X`
  - store timestamped archive + `*_latest.json`
- Ensure container runtime can write `*_latest.json`:
  - avoid creating `latest` files as root-only writable
  - fix ownership/mode when needed:
    - `sudo chown -R <admin_user>:<admin_user> /var/lib/openclaw/workspace/X`
    - `sudo find /var/lib/openclaw/workspace/X -type f -name "*_latest.json" -exec chmod 664 {} +`

## Exec allowlist for Markdown edits
- OpenClaw exec policy is command-based (allowlisted executables), not extension-based (`.md` cannot be granted directly).
- Inspect current approvals:
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals get`
- Add common Markdown-safe tooling to allowlist:
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/cat`
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/tee`
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/sed`
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/touch`
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/mkdir`
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/cp`
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" /usr/bin/mv`
- Batch form (same result, faster to run):
  - `for cmd in /usr/bin/cat /usr/bin/tee /usr/bin/sed /usr/bin/touch /usr/bin/mkdir /usr/bin/cp /usr/bin/mv; do sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist add --agent "*" "$cmd"; done`
- Remove entries with:
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js approvals allowlist remove --agent "*" <PATTERN>`

## Safe access pattern (recommended)
- Keep host-published gateway ports bound to loopback on VPS (`127.0.0.1`).
- In container mode, keep gateway bind `lan` (not `loopback`) so host loopback publishing remains reachable.
- Tunnel from laptop:
  - `ssh -N -L 18789:127.0.0.1:18789 <user>@<vps-ip>`
- Open local dashboard URL: `http://127.0.0.1:18789/`

## Repo placement on VPS
- Host-only repos can live under `<host_repos_dir>/<repo>`, but OpenClaw cannot see that path unless it is explicitly mounted.
- Assistant-accessible repos should live under `/var/lib/openclaw/workspace/repos/<repo>`.
  - host path: `/var/lib/openclaw/workspace/repos/<repo>`
  - container path: `/home/node/.openclaw/workspace/repos/<repo>`
- For host-side convenience, create `<host_repos_dir>/<repo>` as a symlink to the workspace repo.
- Keep secret-bearing runtime files out of these repos; use `.env.example` and sanitized config snapshots instead of committing `/etc/openclaw/.env`, OAuth profiles, pairing state, session history, or private SSH keys.

## OpenClaw workspace skills
- OpenClaw discovers workspace skills from `/var/lib/openclaw/workspace/skills/<skill>/SKILL.md`.
- Keep source-controlled local skills in `openclaw-config/skills/<skill>/SKILL.md`, then deploy them to the workspace skill directory.
- Current deploy command:
  - `sudo install -d -o <admin_user> -g <admin_user> /var/lib/openclaw/workspace/skills`
  - `sudo rsync -a --delete --chown=<admin_user>:<admin_user> /var/lib/openclaw/workspace/repos/openclaw-config/skills/ /var/lib/openclaw/workspace/skills/`
- Validate discovery:
  - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli skills info <skill>`
- The `crawl` workspace skill teaches OpenClaw to use Firecrawl privately at `http://firecrawl:3002`.

## Firecrawl private stack
- Use official Firecrawl self-host docs and upstream repo as source of truth:
  - `https://docs.firecrawl.dev/contributing/self-host`
  - `https://github.com/firecrawl/firecrawl`
- Do not switch Firecrawl to SQLite unless upstream adds explicit support. Current self-host runtime uses Redis, RabbitMQ, and NUQ on Postgres (`POSTGRES_*`, schema `nuq.*`, `pg_cron`).
- Keep Firecrawl private on the VPS:
  - API bind: `127.0.0.1:3002`
  - OpenClaw container endpoint: `http://firecrawl:3002`
  - laptop tunnel: `ssh -N -L 3002:127.0.0.1:3002 openclaw-vps`
- Current layout:
  - upstream source: `/var/lib/openclaw/workspace/repos/firecrawl`
  - config repo: `/var/lib/openclaw/workspace/repos/openclaw-config/firecrawl`
  - runtime compose: `/opt/firecrawl/docker-compose.yml`
  - runtime env: `/etc/firecrawl/firecrawl.env` (secret-bearing; never commit)
- Ansible role:
  - `templates/ansible/roles/firecrawl`
  - role is gated by `install_firecrawl` (repo default: `false`)
  - service state is gated by `firecrawl_enable_service` (repo default: `false`)
  - image pins are required before role execution unless `firecrawl_allow_floating_images=true` is set deliberately
  - API service joins `openclaw_default` with alias `firecrawl`; Postgres/Redis/RabbitMQ remain on `firecrawl_backend`
  - env secrets are generated only when missing/placeholder and `firecrawl_auto_generate_secrets=true`
- Use low-concurrency defaults on 4 CPU / 8 GB VPS:
  - `NUM_WORKERS_PER_QUEUE=2`
  - `CRAWL_CONCURRENT_REQUESTS=2`
  - `MAX_CONCURRENT_JOBS=1`
  - `BROWSER_POOL_SIZE=1`
- Compose operations:
  - `sudo docker compose --env-file /etc/firecrawl/firecrawl.env -f /opt/firecrawl/docker-compose.yml ps`
  - `sudo docker compose --env-file /etc/firecrawl/firecrawl.env -f /opt/firecrawl/docker-compose.yml up -d`
  - `sudo docker compose --env-file /etc/firecrawl/firecrawl.env -f /opt/firecrawl/docker-compose.yml logs --tail=100 api`
- Validation:
  - root endpoint: `curl -fsS http://127.0.0.1:3002`
  - OpenClaw container endpoint:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml exec -T openclaw-gateway sh -lc 'curl -fsS http://firecrawl:3002'`
  - scrape endpoint:
    - `curl -fsS -X POST http://127.0.0.1:3002/v1/scrape -H 'Content-Type: application/json' -d '{"url":"https://docs.firecrawl.dev","formats":["markdown"]}'`
  - scrape from OpenClaw container:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml exec -T openclaw-gateway sh -lc 'curl -fsS -X POST http://firecrawl:3002/v1/scrape -H "Content-Type: application/json" -d "{\"url\":\"https://docs.firecrawl.dev\",\"formats\":[\"markdown\"]}"'`
- If API restarts with `relation "nuq.queue_*" does not exist`:
  - ensure `POSTGRES_DB=postgres`; upstream `nuq-postgres` config sets `cron.database_name = 'postgres'`
  - if this is a fresh failed init, recreate only the Firecrawl volumes: `sudo docker compose --env-file /etc/firecrawl/firecrawl.env -f /opt/firecrawl/docker-compose.yml down -v`, then `up -d`

## Validation checklist
- Service/container status:
  - systemd: `sudo systemctl status openclaw --no-pager`
  - container: `sudo docker compose -f /etc/openclaw/docker-compose.yml ps`
- Gateway health:
  - `curl -fsS http://127.0.0.1:18789/healthz`
- Gateway token readiness:
  - `sudo bash -lc 'v=$(grep -E "^OPENCLAW_GATEWAY_TOKEN=" /etc/openclaw/.env | cut -d= -f2- || true); [ -n "$v" ] && [ "$v" != "placeholder" ] && echo "OPENCLAW_GATEWAY_TOKEN=set" || echo "OPENCLAW_GATEWAY_TOKEN=missing_or_placeholder"'`
- Swap readiness:
  - `swapon --show`
  - `free -h`
  - `sysctl vm.swappiness`
  - expected for current CX33: `/swapfile` around `4G`, `vm.swappiness = 10`
- Telegram readiness:
  - verify the token works with Telegram API without printing it:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml exec -T openclaw-gateway sh -lc 'curl -fsS -o /tmp/telegram-getme.json -w "telegram_getme_http=%{http_code}\n" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"; node -e "const r=require(\"/tmp/telegram-getme.json\"); console.log(\"telegram_api_ok=\"+Boolean(r.ok))"'`
  - check pending pairing queue:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli pairing list telegram`
  - check approved senders:
    - `sudo test -f /var/lib/openclaw/.openclaw/credentials/telegram-default-allowFrom.json && sudo cat /var/lib/openclaw/.openclaw/credentials/telegram-default-allowFrom.json`
  - if user still gets `OpenClaw: access not configured`, re-run `/start`, then approve newest code and verify queue is empty.
  - if pairing is approved but chat appears silent:
    - first verify outbound delivery from inside the running gateway container (this sends one test message):
      - `sudo docker compose -f /etc/openclaw/docker-compose.yml exec -T openclaw-gateway sh -lc 'chat=$(node -e "const fs=require(\"fs\"); const c=JSON.parse(fs.readFileSync(\"/home/node/.openclaw/openclaw.json\",\"utf8\")); const v=(c.commands&&c.commands.ownerAllowFrom||[]).find(x=>x.startsWith(\"telegram:\")); if(!v) process.exit(2); console.log(v.slice(9));"); curl -fsS -o /tmp/telegram-send-result.json -w "telegram_send_http=%{http_code}\n" -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="$chat" --data-urlencode text="OpenClaw transport test vanuit VPS."; node -e "const r=require(\"/tmp/telegram-send-result.json\"); console.log(\"telegram_api_ok=\"+Boolean(r.ok))"'`
    - if direct delivery works, inspect session files/logs before changing tokens; slow `gpt-5.5` / Codex cold runs can take around 1-2 minutes before the reply is generated.
- Slack readiness:
  - verify env values are non-empty (without printing secrets):
    - `sudo bash -lc 'for k in SLACK_APP_TOKEN SLACK_BOT_TOKEN; do grep -Eq "^${k}=.+" /etc/openclaw/.env && echo "${k}=set" || echo "${k}=missing"; done'`
  - verify tokens are present inside running gateway container:
    - `sudo docker exec openclaw-openclaw-gateway-1 sh -lc 'for k in SLACK_APP_TOKEN SLACK_BOT_TOKEN; do v=$(printenv "$k" || true); [ -n "$v" ] && echo "$k=set" || echo "$k=missing"; done'`
  - verify channel toggle:
    - `sudo jq -c '.channels.slack' /var/lib/openclaw/.openclaw/openclaw.json`
  - verify runtime connection signal:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml logs --since=10m openclaw-gateway | grep -F "socket mode connected"`
  - verify sender pairing state:
    - `sudo cat /var/lib/openclaw/.openclaw/credentials/slack-default-allowFrom.json`
  - verify native exec approvals config:
    - `sudo jq -c '.channels.slack.execApprovals' /var/lib/openclaw/.openclaw/openclaw.json`
  - verify explicit channel routing config when needed:
    - `sudo jq -c '.channels.slack.groupPolicy, .channels.slack.channels' /var/lib/openclaw/.openclaw/openclaw.json`
  - if DM replies work but `#channel` mentions do not:
    - re-check Slack Event Subscriptions includes `app_mention`
    - temporarily set explicit channel route (`channels.slack.channels.<CHANNEL_ID>`)
    - re-check app reinstall after scope/event changes
  - if channel replies are duplicated:
    - remove overlapping event subscriptions (`app_mention` vs `message.channels`/`message.groups`) so only one message-ingress path is active
  - if native approvals fail with `missing_scope`:
    - add required Slack scopes (typically `im:write`) and reinstall
  - send a real Slack message/mention to confirm end-to-end delivery.
- Deployed model routing:
  - verify the runtime actually exposes the desired model before setting it:
    - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli models list | grep -E 'openai/gpt-5\\.5|openai-codex/gpt-5\\.5'`
    - for the pinned 2026.5.2 subscription route, configure `openai-codex/gpt-5.5` and leave `agents.defaults.agentRuntime` unset.
    - for the pinned 2026.4.29 fallback route, configure `openai-codex/gpt-5.4` and leave `agents.defaults.agentRuntime` unset.
    - if `models list` and runtime auth hints disagree, trust only a real `openclaw agent ... --json` smoke test.
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.model.primary`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.model.fallbacks`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.agentRuntime.id`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get plugins.entries.codex.enabled`
- Deployed cost profile:
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.params.cacheRetention`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.contextPruning.mode`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.contextPruning.ttl`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.heartbeat.every`
  - `docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.heartbeat.target`
- OpenAI Codex OAuth readiness:
  - ensure at least one auth profile exists in state:
    - `sudo test -f /var/lib/openclaw/.openclaw/agents/main/agent/auth-profiles.json`
  - verify profile key without printing token payloads:
    - `sudo jq -r '.profiles | keys[]' /var/lib/openclaw/.openclaw/agents/main/agent/auth-profiles.json`
  - re-check deployed model/runtime routing after OAuth:
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.model.primary`
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.model.fallbacks`
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get agents.defaults.agentRuntime.id`
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps --entrypoint node openclaw-gateway dist/index.js config get plugins.entries.codex.enabled`
  - optional diagnostic (order override only, not profile existence):
    - `sudo docker compose -f /etc/openclaw/docker-compose.yml run --rm --no-deps openclaw-cli models auth order get --provider openai-codex`
- Port exposure sanity:
  - `sudo ss -ltnp | rg '18789|18790'`
  - verify only loopback unless intentionally public.
- GitHub CLI readiness (when VPS repo operations are expected):
  - `gh auth status -h github.com`
  - `sudo docker exec openclaw-openclaw-gateway-1 sh -lc 'ssh -T -o StrictHostKeyChecking=accept-new git@github.com'`
- X runtime readiness (article-aware):
  - verify X env in runtime container:
    - `sudo docker exec openclaw-openclaw-gateway-1 sh -lc 'for k in X_BEARER_TOKEN X_CONSUMER_KEY X_CONSUMER_SECRET; do v=$(printenv "$k" || true); [ -n "$v" ] && echo "$k=set" || echo "$k=missing"; done'`
  - verify full article extraction in runtime context:
    - `sudo docker exec openclaw-openclaw-gateway-1 sh -lc 'python3 /home/node/.openclaw/workspace/scripts/x_fetch_user_tweets.py --tweet 2044738504286974459' | python3 -c 'import json,sys; o=json.load(sys.stdin); print(\"ok\",o.get(\"ok\"),\"full_text_len\",len(((o.get(\"tweet\") or {}).get(\"full_text\") or \"\")),\"save_error\",o.get(\"save_error\"))'`

## Safe update sequence
1) Run Terraform plan and inspect for destroy/replace.
2) If destructive and rebuild is not approved, skip Terraform apply.
3) Run Ansible apply.
4) Verify runtime health:
   - systemd mode: `systemctl is-active <openclaw_service_name>`
   - container mode: `docker compose -f /etc/openclaw/docker-compose.yml ps`
5) Verify gateway health and access model:
   - `curl -fsS http://127.0.0.1:18789/healthz`
   - check listening sockets (`ss -ltnp`) match intended exposure.

## Secret leak remediation
- If gateway token/API keys/channel tokens leak:
  - rotate compromised token/key immediately
  - update `/etc/openclaw/.env`
  - restart runtime (`systemctl restart` or `docker compose up -d`)
  - scrub sensitive logs if needed:
    - `sudo journalctl --rotate`
    - `sudo journalctl --vacuum-time=1s`

## Update workflow
- Container mode:
  - set/update `OPENCLAW_IMAGE` in `/etc/openclaw/.env`
  - optionally set `openclaw_compose_pull=true` for one run
  - rerun playbook and verify health
- Systemd mode:
  - set `openclaw_update_cli=true` for one run
  - rerun playbook, verify `openclaw gateway status`

## Learnings
- Keep extended operational learnings in `LEARNINGS.md`.
- Keep this SKILL file concise and procedure-focused.

## Guardrails
- Do not invent VPS facts; verify against templates and current config.
- Do not log/store secrets in repo or command output snippets.
- Do not conclude X/Telegram runtime failure based on host-only paths; confirm from `openclaw-openclaw-gateway-1` first.
