# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Claude Code skills `/handoff` (save session state as Markdown) and `/pickup` (resume it), optional `/tips`, and the `handoffs` web dashboard. Bash 3.2+ and git only (Linux, macOS, Termux); the dashboard is Python 3.8+ stdlib only. README.md is the user-facing spec: keep it, CHANGELOG.md and `--help` texts in sync with behavior changes.

## Commands

- Tests: `tests/test.sh` (one script, no per-test filter; uses throwaway `HANDOFF_ROOT`/`HANDOFF_STATE`, never touches real data or the service). Prints `passed: N, failed: M`.
- Lint (CI, not run by tests): `shellcheck -x skills/handoff/handoff.sh skills/handoff/tips.sh install.sh tests/test.sh` (use `uvx --from shellcheck-py shellcheck ...` if missing). SC2015 (`A && B || C`) is a recurring failure.
- Dashboard JS check (tests cover only the Python API): `python3 tests/page_js.py /tmp/page.js && node --check /tmp/page.js`.
- Run dashboard on fixtures: `HANDOFF_ROOT=<dir> python3 bin/handoffs --no-open --port 8799`; restart after each edit (it serves the HTML it loaded).
- Local install: `./install.sh [--skills|--no-skills] [--dashboard|--no-dashboard] [--tips|--no-tips] [--dashboard-auth|--no-dashboard-auth] | --dashboard-only | --uninstall`. It restarts but does not rewrite the systemd unit; use `handoffs service install` for that.

## Architecture

- `skills/handoff/SKILL.md`, `skills/pickup/SKILL.md`: the model writes the summary; ```` ```! ```` injection blocks call `handoff.sh` for context. Every injected command must exit 0 (a non-zero exit aborts the skill), so `handoff.sh` always ends with `exit 0`. Injected output is not re-scanned: `${CLAUDE_*}` placeholders only work in SKILL.md itself.
- `skills/handoff/handoff.sh PROJECT_DIR <cmd>`: storage, task listing, pruning, archive/restore, staleness, per-machine paths. Sources `tips.sh` (tip search/write, plus `tips hook` / `tips prompt-hook` used by the hooks `install.sh` adds to `~/.claude/settings.json`).
- `tips.sh` awk programs live inside bash single quotes: never put `'` in them, use `sprintf("%c", 39)` or `\047`.
- `bin/handoffs`: single-file dashboard (HTTP server, embedded `LOGIN_PAGE`/`PAGE` HTML/CSS/JS, password auth, service install via systemd `--user`/launchd, `paths`). Reads files on every request.
- `install.sh` runs under `set -euo pipefail`: helpers captured with `$(...)` must return 0 (`[[ -f $X ]] || return 0`, not `[[ -f $X ]] && cmd`).
- Plugin (`.claude-plugin/`, `"source": "./"`) ships every dir in `skills/`. Skills that only `install.sh` installs (e.g. `tips`) go in `extras/`.
- Storage: `$HANDOFF_ROOT/<project>/<task>.md` + `_archive/`, `_history/<task>/`, `_tips/{_global,<project>}/`; root holds only `.md` (shared across machines via sync). Per-machine data (paths, logs, PID, sessions) is in `$HANDOFF_STATE`. Project key = basename of `$CLAUDE_PROJECT_DIR`, sanitized.

## Conventions

- Dashboard access is full or none: never propose a read-only mode (removed in 1.5.5). Non-loopback `--host` or `public_url` requires `auth = on`.
- Release: bump `VERSION` in `bin/handoffs` AND `version` in `.claude-plugin/plugin.json`; CHANGELOG `## [X.Y.Z] - date` plus compare link; run shellcheck; commit `Release X.Y.Z: ...`; tag `vX.Y.Z`; `git push origin main vX.Y.Z`; `gh release create vX.Y.Z --title X.Y.Z --notes-file <changelog section>` (a tag alone is not a release). If `gh` returns 403, run it as `env -u GITHUB_TOKEN gh ...`. Commit/tag/push only after the user confirms.
