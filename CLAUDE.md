# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Docker environment for running Claude Code in an autonomous loop ("Ralph Loop"), based on Geoffrey Huntley's technique. It uses a Claude Max subscription (OAuth token) instead of API keys. The container runs with a whitelist firewall, non-root user, and rate limiting for safety.

## Architecture

The system has three layers:

1. **Docker layer** (`Dockerfile`, `docker-compose.yml`) — Ubuntu 24.04 container with Node.js 22, Claude Code CLI, iptables-based firewall. Two services: `ralph` (interactive shell) and `loop` (autonomous execution).

2. **Scripts layer** (`scripts/`):
   - `entrypoint.sh` — Validates OAuth token, writes credentials to `/home/claude/.claude/.credentials.json`, initializes firewall, drops to command.
   - `init-firewall.sh` — Resolves whitelisted domains via `dig`, populates an `ipset`, configures `iptables` OUTPUT chain to DROP all except whitelisted IPs on ports 80/443, DNS (53), and SSH (22). Requires `NET_ADMIN` capability.
   - `ralph-loop.sh` — The core loop. Reads PRD file, builds a prompt instructing Claude to work on one task per iteration, runs `claude --dangerously-skip-permissions --print --output-format text`, checks for `<promise>COMPLETE</promise>` sentinel to stop, handles rate limiting and timeouts.

3. **Workspace layer** (`workspace/`) — Mounted as `/workspace` in the container. Contains `tasks/prd.md` (user-defined requirements) and `tasks/progress.md` (auto-generated progress tracking).

## Key Commands

```bash
# Build the Docker image
docker compose build

# Run autonomous loop (non-interactive)
docker compose run loop

# Run interactive shell (can then use `claude` or `ralph-loop.sh`)
docker compose run ralph

# Disable firewall
ENABLE_FIREWALL=false docker compose run ralph
```

## Configuration

All configuration is via environment variables in `.env` (copy from `.env.example`):

- `CLAUDE_CODE_OAUTH_TOKEN` (required) — Get via `claude setup-token` on host
- `MAX_ITERATIONS` (default: 50) — Loop iteration cap
- `TIMEOUT_MINUTES` (default: 30) — Per-iteration timeout
- `RATE_LIMIT_CALLS` (default: 100) — Max calls per hour
- `PRD_FILE` / `PROGRESS_FILE` — Task file paths relative to `/workspace`

## Loop Behavior

The ralph-loop invokes Claude Code once per iteration with a prompt that instructs it to:
1. Read the PRD to understand scope
2. Read progress file for completed work
3. Pick the next pending task and implement only that one
4. Update progress file and commit

The loop terminates when Claude outputs `<promise>COMPLETE</promise>` or `MAX_ITERATIONS` is reached. Rate limit detection pauses for 5 minutes on API throttling.

## Firewall Whitelist

Allowed outbound destinations: `api.anthropic.com`, `claude.ai`, `statsig.anthropic.com`, `sentry.io`, `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `github.com`, `gitlab.com`, `bitbucket.org`, plus DNS resolvers `1.1.1.1` and `8.8.8.8`. Everything else is blocked at the iptables level.
