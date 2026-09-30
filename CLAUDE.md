# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infra-as-code for a containerized multi-agent dev environment built around eight AI coding CLIs — **Claude Code**, **Gemini CLI**, **Qwen Code**, **Cursor CLI**, **OpenCode CLI**, **Codex CLI**, **Cline CLI**, and **Aider** — deployed as a Docker Swarm service on a VPS. Browser tooling (Lightpanda, Playwright), `cloudflared`, language toolchains (Go, Rust, uv/Python), and shell utilities are bundled as supporting accessories for the agents but are not the focus of this repo. There is no application code here — only the Dockerfile, the Swarm stack, host/container shell scripts, and shell configs. Edits to this repo change how the workspace container is built and how users interact with it.

## Build / deploy

- Image build is automated by GitHub Actions (`.github/workflows/build.yml`). Every push to `main` triggers an **auto-bump** of the patch version (`v0.x.y → v0.x.(y+1)`) via `mathieudutour/github-tag-action`, which creates and pushes the new tag back to the repo. The build then publishes `:latest`, `:main`, `:sha-<short>`, `:0.x.y` (the new patch), and `:0.x` (minor pin), and opens a GitHub Release marked as prerelease with auto-generated changelog. Tags pushed by `GITHUB_TOKEN` don't trigger workflows (GitHub safety), so there's no infinite loop.
- **Versioning policy**: this project lives in **permanent v0.x beta**. There is no v1.0.0 and no plan to issue one. Patch bumps are automatic on every main push. Minor bumps (`v0.1.x → v0.2.0`) are manual and rare — done by pushing a tag explicitly when there's a meaningful behavioral change or new CLI. The "major" slot stays at 0 forever — semver's "anything goes in 0.x" applies.
- Local build: `docker build -t ai-workspace:latest .`
- Deploy: Portainer stack from `aiworkspace.yaml`, or `docker stack deploy -c aiworkspace.yaml aiworkspace`.
- Runtime update on the VPS: `ai-update` (pulls `ghcr.io/ffmenezes/ai-workspace:latest` and force-updates the `aiworkspace_aiworkspace` service; service name overridable via `AI_WORKSPACE_SERVICE` env var).
- There are no tests, linters, or package manager — changes are validated by building the image and running it.

## Architecture

- **Base image**: `node:22-bookworm-slim`. Choice is load-bearing: Gemini CLI and Qwen Code require Node 20+, and Claude Code ships glibc-linked binaries (Alpine/musl crashes). Don't switch to Alpine.
- **The eight CLIs**:
  - Claude Code — Anthropic's native installer; auth in `~/.claude/.credentials.json` (volume `aiworkspace_claude`).
  - Gemini CLI — `npm i -g @google/gemini-cli`; auth via `GEMINI_API_KEY` env var (configure in stack file, not bashrc).
  - Qwen Code — `npm i -g @qwen-code/qwen-code`; OAuth (free tier) in `~/.qwen` (volume `aiworkspace_qwen`).
  - Cursor CLI — native installer; auth in `~/.cursor/cli-config.json` via `agent login` (volume `aiworkspace_cursor`).
  - OpenCode CLI — `npm i -g opencode-ai`; multi-provider auth in `~/.local/share/opencode/auth.json` via `opencode auth login` (volume `aiworkspace_opencode`).
  - Codex CLI — `npm i -g @openai/codex`; auth in `~/.codex/auth.json` via `codex login --device-auth` or API key in config.toml (volume `aiworkspace_codex`). Credential store set to `file` (no keyring in Docker).
  - Cline CLI — `npm i -g cline`; auth via `cline auth -p <provider> -k <key>` (volume `aiworkspace_cline`).
  - Aider — `uv tool install aider-chat`; auth via env vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) or `.env` file in project. Config in `~/.aider*` (volume `aiworkspace_aider`).
- **Browser automation**: `agent-browser` (Vercel Labs) — `npm i -g agent-browser`; native Rust CLI that controls Chrome/Chromium via CDP. Auto-detects Playwright's Chromium in `/opt/ms-playwright` and supports Lightpanda as alternative engine (`--engine lightpanda`). Installed globally, not an AI CLI — it's a tool the agents use. SKILL.md is a default global skill seeded into `~/.agents/skills/agent-browser/` on first boot from `/opt/default-skills/`.
  **Update story**: Claude and Cursor have native auto-updaters that are *intentionally bypassed* — both binaries are copied to `/opt/{claude,cursor-agent}` (read-only) and symlinked into PATH. Auto-updates download to `~/.local/share/...` but the symlink keeps pointing at the build-time version, so they never run. The only reliable update path for any CLI is image rebuild + `ai-update`. Gemini/Qwen/OpenCode can be updated pontually via `npm update -g ...` inside the container, but those changes vanish on rebuild. When changing how a CLI is installed, updated, or authenticated, update Dockerfile + aiworkspace.yaml + README in lockstep.
- **Container user**: runs as non-root `dev`. Dockerfile ends with `USER root` (for sshd), but the entrypoint drops to `dev` via `gosu`. All host aliases use `-u dev`. No sudo inside; use `docker exec -u root` from the host for system changes.
- **Entrypoint** (`scripts/entrypoint.sh`): runs as root — starts sshd, seeds skills, restores backups — then drops to `dev` via `gosu` for Herdr + tail.
- **Persistence** is entirely in named Docker volumes mounted into `/home/dev`:
  - `aiworkspace_projects` → `~/projects`
  - `aiworkspace_config` → `~/.config`
  - `aiworkspace_claude` → `~/.claude` (Claude auth + skills)
  - `aiworkspace_gemini` → `~/.gemini`
  - `aiworkspace_qwen` → `~/.qwen`
  - `aiworkspace_cursor` → `~/.cursor`
  - `aiworkspace_opencode` → `~/.local/share/opencode`
  - `aiworkspace_codex` → `~/.codex` (Codex auth + config)
  - `aiworkspace_cline` → `~/.cline` (Cline auth)
  - `aiworkspace_aider` → `~/.aider` (Aider config/history)
  - `aiworkspace_agents` → `~/.agents` (global skills shared across all CLIs)
  - `aiworkspace_ssh` → `~/.ssh`
  Anything written outside these paths is lost on rebuild.
- **Networking**: container joins `network_swarm_public` so agent MCPs can reach sibling Swarm services (Postgres, Redis, n8n, etc.).
- **Host integration**: `setup-host-aliases.sh` installs shell functions on the VPS host, all prefixed `ai-` (`ai-enter`, `ai-attach`, `ai-dev`, `ai-dev-danger`, `ai-sessions`, `ai-kill`, `ai-kill-all`, `ai-fix-perms`, `ai-update`, `ai-ssh`, `ai-tunnel`, `ai-clipboard`, `ai-help`). These are the user's main entry points — most just `docker exec` the equivalently-named script inside the container. `ai-help` is the canonical reference and includes a column showing where each command runs (host vs container).
- **SSH server**: `sshd` on port 2222 (pubkey only, no root login). Enables SSH tunneling through the Swarm overlay network. Use `ai-ssh` to connect, `ai-tunnel <port>` to forward ports. See `docs/cdp-live-debugging.md` for setup and `docs/troubleshooting.md` for common issues.
- **Clipboard bridge** (`scripts/ai-clipboard`): Node.js web server (port 3456) that lets the developer paste images from their PC browser into `~/.clipboard/` in the container. Started via `ai-dev --clipboard` or `ai-clipboard` on the host. Agents can reference pasted images via `@path` and save their own screenshots to the same directory. Zero external dependencies.
- **Shared Chromium CDP** (`scripts/ai-browser`): Starts a headless Chromium with `--remote-debugging-port=9222`. Started via `ai-dev --browser`. The same browser is accessible to both the developer (via `chrome://inspect` on their PC through SSH tunnel) and AI agents (via Playwright `connectOverCDP()` or `agent-browser --cdp 9222`). This enables bidirectional interaction — the dev can set up a page in DevTools and ask an agent to screenshot or interact with it. Agents must never call `browser.close()` on the shared instance.

## How `ai-dev` works (the core UX)

`scripts/ai-dev` is the workspace launcher invoked from the host. It:
1. Resolves a project name to `~/projects/<name>` inside the container.
2. Creates (or attaches to) a named Herdr session for the project.
3. Creates one workspace with an agent per tab plus a shell tab. **Default (no agent flag) opens all eight agents**; naming any agent flag (`--claude`, `--gemini`, `--qwen`, `--cursor`, `--opencode`, `--codex`, `--cline`, `--aider`) restricts to only the named ones. `--rc` adds Remote Control to Claude. `--danger` passes the per-CLI danger flag (`--dangerously-skip-permissions`, `--yolo`, `-f`, `--yes-always`). `--clipboard` starts the clipboard bridge. `--browser` starts the shared Chromium CDP. `ai-dev-danger` = `ai-dev <projeto> --danger`.

When changing agent invocation, flags, or window layout, edit `scripts/ai-dev` and keep `scripts/ai-kill`, `scripts/ai-kill-all`, and `scripts/ai-sessions` consistent with session naming. Container scripts and host aliases share the same names by convention — if you rename one, rename both and update `ai-help`.

## Agent Links (setup-agent-links)

`scripts/setup-agent-links` runs automatically on every `ai-dev` invocation (both create and reconnect). It unifies skills discovery across all 8 CLIs using `.agents/skills/` as the canonical directory (Agent Skills open standard). Key behaviors:
- Creates `.agents/skills/` in the project if missing.
- Symlinks global skills from `~/.agents/skills/` into the project's `.agents/skills/`.
- Creates directory-level symlinks `.claude/skills → .agents/skills` and `.qwen/skills → .agents/skills` (these CLIs don't natively scan `.agents/`). Gemini, Cursor, OpenCode, and Codex read `.agents/skills/` natively.
- If `.claude/skills/` or `.qwen/skills/` already exist as real directories, migrates their contents to `.agents/skills/` before replacing with symlink.
- Generates thin-wrapper instruction files (`CLAUDE.md`, `GEMINI.md`, `QWEN.md`, `AGENTS.md`, `.clinerules`, `.cursor/rules/base.mdc`, `CONVENTIONS.md`) pointing to `AGENTS.md` as the shared source of truth. Never overwrites existing files.

Skills created by any CLI (e.g. Claude writing to `.claude/skills/new-skill/`) transparently land in `.agents/skills/` thanks to the directory symlink — all CLIs see it immediately.

## Default Skills

Skills in the repo's `.agents/skills/` directory are baked into the image at `/opt/default-skills/`. On container boot, any skill not already present in the `~/.agents/skills/` volume is copied (seeded) automatically. This means:
- New default skills added to the repo appear in the container after rebuild + `ai-update` (next boot).
- User modifications to skills in the volume are never overwritten (seed only copies if the skill directory doesn't exist).
- Current default skills: `agent-browser` (browser automation via CDP), `cdp-shared` (shared Chromium CDP — agents connect to the same browser the dev inspects via DevTools), `clipboard` (clipboard bridge — pasting images from PC, saving screenshots for dev reference), `ralph-prompt` (prompt engineering for ralph loops), `playwright-login` (login test templates: screenshots, video+trace, CDP ao vivo).

## Ralph loop

`scripts/ralph` runs an agent (claude/gemini/qwen/cursor/opencode) in a loop until it emits a stop word (default `RALPH_DONE`) or hits `--max`. Iteration logs go to `.ralph-logs/` inside the target project. Used for long-running autonomous tasks; users typically start it then detach from Herdr. OpenCode uses a `run` subcommand instead of `-p` and has no danger mode.

## Docs

Detailed guides live in `docs/`:
- `docs/browser-automation.md` — agent-browser, Playwright, Lightpanda usage
- `docs/cdp-live-debugging.md` — CDP ao vivo: SSH tunnel setup, Chrome DevTools remoto, Playwright scripts
- `docs/troubleshooting.md` — diagnóstico de problemas comuns (user root vs dev, SSH, CDP, permissões)

## Conventions

- README.md is in Portuguese and is the canonical user-facing doc — keep it in sync when changing flags, scripts, volume names, or the stack.
- The GHCR image owner is hardcoded as `ffmenezes` in `setup-host-aliases.sh` (`ai-update` default) and throughout the README; forks must update both. The Swarm service name is also hardcoded as `aiworkspace_aiworkspace` but is overridable via `AI_WORKSPACE_SERVICE` env var.
- Shell scripts target bash on Debian 12 inside the container (and bash on the Debian VPS host). Don't assume GNU-only flags work everywhere, but POSIX-strict isn't required.
- This repo is developed on Windows (`win32`) but every script runs on Linux — use Unix line endings and forward slashes.
