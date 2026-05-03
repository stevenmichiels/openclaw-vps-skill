# openclaw-vps - Operational Learnings

This file stores long-form operational memory for `openclaw-vps`.

This file contains sanitized operational lessons. It must not contain real tokens, user IDs, channel IDs, hostnames, OAuth payloads, IP addresses, private account labels, or other deployment-specific fingerprints.

## Initial notes
- Keep OpenClaw gateway bound to loopback on VPS by default.
- Use SSH tunneling for dashboard/API access unless public exposure is explicitly required.
- Never enable service with `__SET_ME__` placeholders still present in `/etc/openclaw/.env`.
- For container mode with `openclaw:local`, build or load the image before `openclaw_enable_service=true`.

## 2026-04-06 - OpenAI Codex OAuth rollout
- Symptom: `openai/*` model defaults did not align with ChatGPT OAuth goals.
  Root cause: `openai/*` expects API-key auth; ChatGPT OAuth is exposed via `openai-codex/*`.
  Verified fix: move default model routing to `openai-codex/*`; current policy is strongest exposed non-mini model as primary with an explicitly empty fallback list.
  Guardrail: skill docs now include explicit auth-mode mapping (`openai/*` vs `openai-codex/*`).
- Symptom: runtime image lagged behind desired OpenClaw release.
  Root cause: playbook/default docs were pinned to older OpenClaw releases.
  Verified fix: bump default image to the latest stable GitHub release tag in site/template/task defaults.
  Guardrail: keep image pin aligned with validated release when adding provider/model features.
- Symptom: OAuth login step was skipped in otherwise successful deploys.
  Root cause: model/config deployment and provider auth login are separate operations.
  Verified fix: add explicit post-deploy step to run `openclaw models auth login --provider openai-codex --set-default` (TTY required).
  Guardrail: validation checklist now includes auth-profile state check (`auth-profiles.json`).
- Symptom: browser reached `http://localhost:1455/auth/callback?...` and showed connection refused during OAuth.
  Root cause: OAuth CLI flow runs on VPS, while browser callback opened on laptop localhost where no listener was running.
  Verified fix: copy/paste callback query string (`code=...&scope=...&state=...`) into the waiting SSH login prompt.
  Guardrail: document this as expected for remote login flow and treat callback payload as sensitive/single-use.
- Symptom: validation looked for auth profiles in old path and reported false negatives.
  Root cause: active profile state is agent-scoped in this deployment (`/var/lib/openclaw/.openclaw/agents/main/agent/auth-profiles.json`).
  Verified fix: update readiness checks to use the agent path and inspect profile keys only (avoid printing tokens).
  Guardrail: prefer non-secret checks like `jq '.profiles | keys[]'` over dumping full auth files.
- Symptom: Slack stayed inactive after adding `SLACK_APP_TOKEN` to `.env`.
  Root cause: Slack runtime needs both tokens (`SLACK_APP_TOKEN` and `SLACK_BOT_TOKEN`) and channel config toggle (`channels.slack.enabled=true`).
  Verified fix: confirm both env vars are non-empty, set `channels.slack.enabled`, and recreate the gateway after env changes.
  Guardrail: treat Slack setup as a 3-step activation: env pair present, channel enabled, gateway recreated after env changes.
- Symptom: Slack mention still got no reply after env update + channel enable.
  Root cause: container template did not pass channel token env vars into runtime (`SLACK_APP_TOKEN`/`SLACK_BOT_TOKEN` missing inside `openclaw-gateway`).
  Verified fix: add channel token env mappings to compose template for both `openclaw-gateway` and `openclaw-cli`, then redeploy/recreate containers.
  Guardrail: validate channel tokens at both layers (host `.env` and in-container `printenv`) and confirm log signal `[slack] socket mode connected`.
- Symptom: Slack replied `OpenClaw: access not configured` after connect.
  Root cause: sender was not yet approved in Slack pairing allow-list.
  Verified fix: approve pairing code (`pairing approve slack <CODE>`) and confirm user appears in `slack-default-allowFrom.json` while `slack-pairing.json` request queue clears.
  Guardrail: treat this response as expected onboarding signal (not transport failure); verify allow-list state files after approval.
- Symptom: DM replies worked but native exec approval prompts said no interactive approval client available.
  Root cause: Slack channel-level exec approval routing was unset (`channels.slack.execApprovals` missing).
  Verified fix: set `channels.slack.execApprovals.enabled=true` and `channels.slack.execApprovals.approvers=["<slack_user_id>"]`, then reload/restart gateway.
  Guardrail: include exec-approval config verification in Slack readiness checks (`jq .channels.slack.execApprovals`).
- Symptom: Slack DM path worked while `#channel` mention path failed.
  Root cause: missing/unsynced Slack event subscription and scope setup for channel mentions.
  Verified fix: ensure Event Subscriptions include `app_mention` (and `message.im` for DMs), required scopes are present, then reinstall app.
  Guardrail: when channel replies fail but DM works, prioritize Slack event subscription + reinstall checks before server-side changes.
- Symptom: DM and channel mention paths both active, but channel replies appeared duplicated.
  Root cause: overlapping Slack ingress routes (`app_mention` plus `message.channels` / `message.groups`) caused the same user message to be processed twice.
  Verified fix: keep one ingress strategy active per channel behavior; use mention-first mode (`app_mention` + `message.im`) or broader channel message mode (`message.channels` / `message.groups`) with dedupe and `app_mention` disabled.
  Guardrail: after changing Event Subscriptions, reinstall app and run a single-message duplicate check in channel.
- Symptom: DM replies worked but `#channel` mentions stayed silent intermittently.
  Root cause: Slack channel routing policy was too implicit for this workspace/channel combination.
  Verified fix: set explicit route config (`channels.slack.groupPolicy="open"` and `channels.slack.channels.<CHANNEL_ID>={"enabled":true,"requireMention":true}`), then restart gateway and verify logs show channel resolution and delivery.
  Guardrail: when DM works but channel mention does not, add explicit channel mapping before deeper refactors.
- Symptom: Slack native exec approvals remained unavailable and logs showed `missing_scope`.
  Root cause: bot token lacked DM-delivery scope for approval prompts in this workspace path.
  Verified fix: add `im:write` (while keeping `chat:write`), reinstall Slack app, then re-test tool approval prompt delivery.
  Guardrail: include `missing_scope` log scan in approval-path validation and keep scope matrix documented.
- Symptom: user asked to allow `.md` file edits but OpenClaw still requested approval.
  Root cause: OpenClaw approval model is executable allowlist based, not file-extension based.
  Verified fix: allowlist common markdown tooling (`/usr/bin/cat`, `/usr/bin/tee`, `/usr/bin/sed`, `/usr/bin/touch`, `/usr/bin/mkdir`) via `approvals allowlist add`.
  Guardrail: document markdown-edit capability as command policy, not path/extension policy.

## 2026-04-18 - OAuth callback handling hardening
- Symptom: OAuth login seemed to stall or complete without persisting an auth profile.
  Root cause: non-interactive/weak TTY chain in SSH + docker-run wrapper, plus fragile parsing when pasting full callback URLs.
  Verified fix: force TTY end-to-end (`ssh -tt ... models auth login ...`) and paste the callback `code` value when the prompt wrapper is flaky.
  Guardrail: skill now marks OAuth login as interactive-only and prefers code-only callback input with full query string as fallback.
- Symptom: callback returned `error=invalid_state`.
  Root cause: callback state did not match the active login attempt (stale or empty state).
  Verified fix: cancel login, rerun login command, and use only the callback URL/state from the newly started attempt.
  Guardrail: explicit state-match check and restart rule documented.
- Symptom: `models auth order get --provider openai-codex` showed `(none)` after successful OAuth.
  Root cause: this command reports order override state, not whether an OAuth profile exists.
  Verified fix: use `auth-profiles.json` existence + profile-key check as primary readiness validation.
  Guardrail: readiness checklist now treats `auth-profiles.json` and `.profiles | keys[]` as canonical OAuth success evidence.

## 2026-04-18 - Telegram pairing approval guardrail
- Symptom: Telegram `/start` returned `OpenClaw: access not configured`.
  Root cause: Telegram transport was healthy, but sender remained unapproved in pairing allow-list.
  Verified fix: list pending Telegram pairing request, approve code, and confirm sender appears in `telegram-default-allowFrom.json` while pending queue is empty.
  Guardrail: skill now documents this as expected onboarding state and includes explicit Telegram readiness checks.

## 2026-04-19 - GitHub CLI + SSH key flow on VPS
- Symptom: `gh auth login -w` interactive flow appeared to hang in remote shell sessions.
  Root cause: TTY/prompt rendering in remote shell could stall without showing actionable device instructions.
  Verified fix: use `gh auth login -h github.com -p https -w --insecure-storage` to force stable device-code output.
  Guardrail: prefer HTTPS device auth first, then switch to SSH protocol only after key setup is validated.
- Symptom: `gh ssh-key add` failed with API 404 despite successful `gh auth login`.
  Root cause: default token scopes omitted `admin:public_key`.
  Verified fix: run `gh auth refresh -h github.com -s admin:public_key --insecure-storage`, then re-run `gh ssh-key add`.
  Guardrail: check `gh auth status -h github.com` scopes before key-management commands.
- Symptom: `gh repo clone <repo>` failed with `Permission denied (publickey)` after key creation.
  Root cause: SSH client on VPS did not select the intended GitHub key by default.
  Verified fix: enforce key selection in `~/.ssh/config` for `github.com` with the configured admin GitHub SSH key and `IdentitiesOnly yes`.
  Guardrail: after SSH config changes, verify with `ssh -T git@github.com` before cloning/pulling.
- Symptom: OpenClaw Telegram/Codex runtime could not use root-level GitHub keys and should not get access to `/root/.ssh`.
  Root cause: runtime runs as container user `node` with its own home, while admin keys lived under `/root/.ssh`.
  Verified fix: mount dedicated runtime SSH dir (`/var/lib/openclaw/.ssh` -> `/home/node/.ssh`), generate runtime-only key, add it to GitHub, and validate SSH handshake from inside `openclaw-gateway` container.
  Guardrail: keep admin and runtime keys separate; never bind-mount `/root/.ssh` into OpenClaw containers.

## 2026-04-19 - X article retrieval + runtime path alignment
- Symptom: single-tweet fetch returned only `https://t.co/...` text and looked incomplete.
  Root cause: the post was an X Article post; call requested regular tweet text but missed article fields/expansions.
  Verified fix: include `tweet.fields=article` and `expansions=article.cover_media,article.media_entities` (plus `media.fields`), then normalize `full_text` as `note_tweet.text // article.plain_text // text`.
  Guardrail: for any tweet that links to `x.com/i/article/...`, always run article-aware fetch and validate `full_text_len`.
- Symptom: Telegram runtime reported `/etc/openclaw/.env` missing and failed to reproduce host results.
  Root cause: Telegram executes in `openclaw-openclaw-gateway-1` where env vars are injected; host file path assumptions do not always hold inside container.
  Verified fix: run checks from runtime container (`docker exec openclaw-openclaw-gateway-1 ...`) and use container script path `/home/node/.openclaw/workspace/scripts/...`.
  Guardrail: treat runtime container context as canonical for Telegram/Codex behavior; do not debug via unrelated containers.
- Symptom: X script returned `save_error` permission denied for `*_latest.json`.
  Root cause: earlier files in `/var/lib/openclaw/workspace/X` were created as root and blocked overwrite by runtime user `node`.
  Verified fix: normalize ownership and permissions on X output folder/files.
  Guardrail: keep `/var/lib/openclaw/workspace/X` writable for runtime and avoid creating output files as root when the runtime needs to update `latest` pointers.

## 2026-05-02 - Fresh VPS rebuild and gateway token generation
- Symptom: On a fresh rebuild, `openclaw_auto_generate_gateway_token=true` skipped generation even though `/etc/openclaw/.env` contained `OPENCLAW_GATEWAY_TOKEN=__SET_ME__`.
  Root cause: the Ansible role used POSIX character class syntax (`[[:space:]]`) inside Python regex handling, producing a warning and failing placeholder detection.
  Verified fix: replace `[[:space:]]*` with Python-compatible `\s*` in the token detection/assert regexes, then generate the gateway token on-host without printing it.
  Guardrail: after first bootstrap, always validate token readiness with a non-secret check before enabling OpenClaw.
- Symptom: During OpenAI Codex OAuth, the interactive prompt drew the callback URL/code but then submitted as empty (`Required`) when driven through the Codex PTY.
  Root cause: the prompt wrapper did not reliably accept normal long paste/input through the PTY.
  Verified fix: paste only the `code` value using bracketed paste (`ESC[200~...ESC[201~`) and then Enter.
  Guardrail: prefer code-only input, and use bracketed paste when normal paste fails through an agent-controlled terminal.
- Symptom: Successful `models auth login --provider openai-codex --set-default` can rewrite model routing.
  Root cause: `--set-default` updates model routing as part of login.
  Verified fix: after OAuth, reapply primary `openai-codex/gpt-5.4`, fallback `[]`, then restart `openclaw-gateway`.
  Guardrail: always re-check model routing after OAuth before declaring OpenClaw ready.
- Symptom: Steven wanted the OpenClaw default to use the strongest available non-mini Codex model, ideally `gpt-5.5`.
  Root cause: OpenClaw 2026.4.9 listed only `openai-codex/gpt-5.4-mini` and `openai-codex/gpt-5.4`; after upgrading to latest stable 2026.4.29, `openai-codex/gpt-5.5` is still not exposed by the runtime.
  Verified fix: set default model routing to primary `openai-codex/gpt-5.4` and fallback `[]`, and update Ansible to enforce an explicitly empty fallback list.
  Guardrail: when OpenClaw exposes `openai-codex/gpt-5.5`, update the primary model in `site.yml` and SKILL.md; until then do not configure a non-listed model id.
- Symptom: Skill docs still said the default image was `ghcr.io/openclaw/openclaw:2026.4.5` while templates used `2026.4.9` and GitHub had newer stable releases.
  Root cause: the documented default image and template pins drifted from upstream OpenClaw releases.
  Verified fix: use GitHub Releases as source of truth, verify the container tag exists, and pin to the latest stable tag `ghcr.io/openclaw/openclaw:2026.4.29` instead of moving `latest`.
  Guardrail: prefer explicit stable release tags over `latest`; before changing, verify both the GitHub release and GHCR manifest.
- Symptom: After upgrading to `2026.4.29`, `docker compose up -d` also started `openclaw-cli` as a long-running interactive helper container, stuck in `health: starting`.
  Root cause: the compose template defined `openclaw-cli` as a normal service; newer image behavior keeps it alive instead of exiting quickly.
  Verified fix: put `openclaw-cli` behind a Compose profile (`profiles: ["cli"]`) so the gateway is the only default daemon while targeted `docker compose run --rm --no-deps openclaw-cli ...` still works for CLI operations. Use `docker compose --profile cli down --remove-orphans` during Ansible restarts so older profile-managed CLI containers are removed too.
  Guardrail: after image upgrades, verify `docker compose ps` shows only intended long-running services.
- Symptom: `TELEGRAM_BOT_TOKEN` was set correctly in `/etc/openclaw/.env`, but the running `openclaw-gateway` container still reported the token as missing after `docker compose restart`.
  Root cause: Docker restart keeps the already-created container and its old environment; it does not re-read Compose `.env` values.
  Verified fix: recreate the gateway with `docker compose -f /etc/openclaw/docker-compose.yml up -d --force-recreate openclaw-gateway`, then verify from inside the running container without printing the token.
  Guardrail: after any `/etc/openclaw/.env` token change in container mode, recreate the gateway instead of using restart; restart is only sufficient for config-only changes.
- Symptom: After pairing, Telegram looked silent even though the token and sender approval were configured.
  Root cause: Telegram outbound needed to be separated from agent latency. A direct `sendMessage` from inside the running gateway container returned HTTP 200, proving token/chat delivery was healthy; the remaining delay was in OpenClaw agent execution.
  Verified fix: test Telegram API outbound from the running container before changing tokens or pairing state, then inspect sessions/logs for agent runs.
  Guardrail: slow `gpt-5.4` cold runs can take around 1-2 minutes; wait for generation or inspect session JSONL before assuming Telegram is broken.
- Symptom: Skill text drifted toward `openai-codex/gpt-5.5` while the deployed runtime still used `openai-codex/gpt-5.4`.
  Root cause: `openclaw-cli models list` on `ghcr.io/openclaw/openclaw:2026.4.29` exposes `openai-codex/gpt-5.4` but not `openai-codex/gpt-5.5`.
  Verified fix: keep configured primary as `openai-codex/gpt-5.4` with fallback `[]` until the runtime lists `gpt-5.5`.
  Guardrail: always check `openclaw-cli models list` before changing model routing to a newer model id.
- Symptom: A runtime GitHub SSH key existed but could not be validated from inside `openclaw-gateway`.
  Root cause: the `ghcr.io/openclaw/openclaw:2026.4.29` container did not include an `ssh` binary.
  Verified fix: create a separate admin-user host key/alias for VPS-side Git operations, and treat runtime SSH as not ready until the image provides `openssh-client`.
  Guardrail: validate host GitHub SSH with the host alias, and validate runtime GitHub SSH with `command -v ssh` before attempting `ssh -T` inside the container.
- Symptom: Repos under `<host_repos_dir>` are convenient for the VPS user but not visible to OpenClaw.
  Root cause: container mode only mounts `/var/lib/openclaw/workspace` into the OpenClaw runtime.
  Verified fix: place assistant-accessible repos under `/var/lib/openclaw/workspace/repos/<repo>` and symlink `<host_repos_dir>/<repo>` to that path for host-side convenience.
  Guardrail: do not mount all of the admin user's home directory into OpenClaw; keep the assistant workspace deliberately scoped.
- Symptom: Self-hosted Firecrawl API restarted with `relation "nuq.queue_scrape" does not exist` / `relation "nuq.queue_crawl_finished" does not exist`.
  Root cause: Firecrawl's `nuq-postgres` image sets `cron.database_name = 'postgres'`; setting `POSTGRES_DB=firecrawl` caused `/docker-entrypoint-initdb.d/010-nuq.sql` to fail when creating `pg_cron`.
  Verified fix: use `POSTGRES_DB=postgres`, recreate the fresh Firecrawl volumes, and restart the stack.
  Guardrail: do not use SQLite for Firecrawl unless upstream adds explicit support; current self-host runtime depends on Postgres + `pg_cron` for NUQ.
- Symptom: Firecrawl ran on the VPS but was not part of repeatable infra.
  Root cause: Firecrawl had been started from a hand-authored Compose stack in `openclaw-config`, outside the `openclaw-vps` Ansible role graph.
  Verified fix: add a separate optional `firecrawl` Ansible role gated by `install_firecrawl` / `firecrawl_enable_service`, managing `/opt/firecrawl/docker-compose.yml` and `/etc/firecrawl/firecrawl.env`.
  Guardrail: keep Firecrawl loopback-only by default and preserve `/etc/firecrawl/firecrawl.env` secrets with `force: false`; generate required secrets only when missing or placeholder.
- Symptom: Firecrawl worked on the VPS host but OpenClaw could not crawl through it.
  Root cause: OpenClaw and Firecrawl ran on separate Docker networks; host loopback `127.0.0.1:3002` is not reachable from inside the OpenClaw container.
  Verified fix: attach only the Firecrawl API service to `openclaw_default` with alias `firecrawl`, while keeping Redis/RabbitMQ/Postgres on `firecrawl_backend`; OpenClaw can use `http://firecrawl:3002`.
  Guardrail: do not attach OpenClaw to the full Firecrawl backend network unless explicitly needed.
- Symptom: Firecrawl was reachable, but OpenClaw had no reusable crawl behavior.
  Root cause: no workspace skill existed under `/var/lib/openclaw/workspace/skills`.
  Verified fix: add `openclaw-config/skills/crawl/SKILL.md`, deploy it to `/var/lib/openclaw/workspace/skills/crawl/SKILL.md`, and verify with `openclaw-cli skills info crawl`.
  Guardrail: keep repo-tracked skills in `openclaw-config/skills` and deploy with `rsync`; validate OpenClaw lists the skill before relying on it in Telegram.
- Symptom: CX33 had enough RAM for OpenClaw + Firecrawl, but no swap safety net for browser/crawler memory spikes.
  Root cause: Hetzner image provisioned no swap by default.
  Verified fix: manage a persistent `/swapfile` through the `base` role with `swap_size_mb=4096` and `swap_swappiness=10`.
  Guardrail: do not resize an active swapfile silently; the role fails if an existing swapfile size differs from `swap_size_mb`.
- Symptom: The rebuilt VPS was prepared for Tailscale-only SSH but still accepted SSH from the public bootstrap `/32`.
  Root cause: Tailscale was installed but logged out, and Terraform/UFW still had the bootstrap source IP allow rule.
  Verified fix: authenticate Tailscale, set the configured Tailscale hostname, verify SSH via the Tailscale DNS name, remove the public UFW rule, and persist Terraform `ssh_source_ips=["100.64.0.0/10"]`.
  Guardrail: never remove the public bootstrap SSH rule until `tailscale ip -4` returns an address and SSH through the Tailscale IP/DNS has succeeded.
- Symptom: OpenClaw had a dedicated runtime GitHub SSH key, but `ssh -T git@github.com` inside the container failed because the pinned upstream image lacked `ssh`.
  Root cause: `ghcr.io/openclaw/openclaw:2026.4.29` includes `git` but not `openssh-client`.
  Verified fix: build a local derived runtime image (`openclaw-runtime:2026.4.29-ssh`) from the pinned upstream image with `openssh-client`, keep `/var/lib/openclaw/.ssh` mounted, add the runtime public key to the configured GitHub account, and verify container-side GitHub SSH authentication.
  Guardrail: keep the upstream base image pinned and validate `openclaw-vps-status` after image changes; the status script must fail when runtime GitHub SSH is not authenticated.
- Symptom: The VPS had no repeatable backup, restore, status, or Docker cleanup automation.
  Root cause: earlier setup relied on ad hoc manual checks and no root-only archive/timer for OpenClaw state.
  Verified fix: install `openclaw-vps-backup` + timer, `openclaw-vps-status`, `openclaw-docker-cleanup` + timer, Docker json-file log limits, and `references/restore.md`; create the first on-host backup and Mac-side copy.
  Guardrail: before calling must-haves complete, run `sudo openclaw-vps-status` and verify it ends with `OK status=healthy`.
- Symptom: The remaining OpenClaw VPS nice-to-haves were documented as policy but had no one-command operator wrapper, scheduled stable release check, or downtime alert.
  Root cause: the operational checks existed as separate manual commands and timers were only present for backups and Docker cleanup.
  Verified fix: install `openclaw-vps` with `status`, `backup`, `release-check`, `healthcheck`, `docker-cleanup`, and `timers`; install `openclaw-vps-release-check` + timer; install `openclaw-vps-healthcheck` + timer with Telegram transition alerts only.
  Guardrail: after operational changes, verify `openclaw-vps status`, `openclaw-vps release-check`, `openclaw-vps healthcheck`, and `openclaw-vps timers`.

## 2026-05-03 - Native Codex route is not valid on pinned OpenClaw 2026.4.29
- Symptom: Telegram returned the generic `Something went wrong while processing your request` for normal prompts after configuring primary model `openai/gpt-5.5` plus `agents.defaults.agentRuntime.id=codex`.
  Root cause: on pinned OpenClaw 2026.4.29, `openclaw-cli models list` shows `openai/gpt-5.5` with no configured auth and `openai-codex/gpt-5.4` with configured OAuth auth. The `openai/gpt-5.5` path called `/v1/responses` without bearer auth and failed with `401 Unauthorized: Missing bearer or basic authentication in header`.
  Verified fix: set primary model back to `openai-codex/gpt-5.4`, unset `agents.defaults.agentRuntime`, restart the gateway, and verify `openclaw agent --agent main --message "Reply exactly: OK" --json` succeeds with provider `openai-codex`, model `gpt-5.4`, and `authMode=auth-profile`.
  Guardrail: for the pinned runtime, do not configure `openai/gpt-5.5` without `OPENAI_API_KEY` and do not force native Codex routing until `models list` plus a real agent run prove the path is authenticated.

## 2026-05-03 - OpenClaw 2026.5.2 exposes GPT-5.5 through openai-codex OAuth
- Symptom: After upgrading to pinned OpenClaw 2026.5.2 and configuring the upstream-documented native route (`openai/gpt-5.5` plus `agents.defaults.agentRuntime.id=codex`), the live agent run still failed with `No API key found for provider "openai"` and explicitly suggested `openai-codex/gpt-5.5`.
  Root cause: in this deployment, the ChatGPT/Codex subscription auth profile is still consumed through the `openai-codex/*` provider path. The `openai/*` path remains API-key auth unless a future runtime proves otherwise in a real agent run.
  Verified fix: keep OpenClaw pinned to `ghcr.io/openclaw/openclaw:2026.5.2`, set primary model to `openai-codex/gpt-5.5`, unset `agents.defaults.agentRuntime`, keep fallback list `[]`, and verify `openclaw agent --agent main --message "Reply exactly: OK" --json` succeeds with provider `openai-codex`, model `gpt-5.5`, and `authMode=auth-profile`.
  Guardrail: version bump validation must include a real agent run, not just `models list` or `openclaw-vps status`; update docs to prefer the verified route over the release-note route when they diverge.

## 2026-05-03 - Channel-safe chart/media output
- Symptom: Telegram responses could say `Canvas failed` or `Media failed` after a chart-like response even when the text answer succeeded.
  Root cause: Canvas is not a reliable primary delivery path for chat channels, and the runtime image did not provide a deterministic Python/matplotlib PNG rendering path.
  Verified fix: extend the derived runtime image to include Python, matplotlib, NumPy, and fonts; deploy a `chart-media` workspace skill plus `/home/node/.openclaw/workspace/scripts/render_chart.py`; and make `openclaw-vps-status` validate helper, skill, and matplotlib readiness.
  Guardrail: for Telegram/Slack charts, render PNG files under `/home/node/.openclaw/workspace/out` and include a final `MEDIA:/home/node/.openclaw/workspace/out/<file>.png` attachment line instead of relying on Canvas.

## Add new learnings
When incidents or surprises happen, append entries with:
- Date/time
- Symptom
- Root cause
- Verified fix
- Follow-up guardrail/template change
