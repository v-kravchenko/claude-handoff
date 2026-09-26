#!/usr/bin/env bash
# Installs the handoff and pickup skills as personal skills
# (${CLAUDE_CONFIG_DIR:-~/.claude}/skills), so they run as /handoff and /pickup.
# Usage: ./install.sh [--uninstall]
# Saved handoffs (~/.claude/handoffs) are never touched.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd -P)/skills"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
SKILLS=(handoff pickup)

case "${1:-}" in
  "")
    [[ -f $SRC/handoff/handoff.sh ]] || { echo "error: run from a clone of the repository" >&2; exit 1; }
    mkdir -p "$DEST"
    for s in "${SKILLS[@]}"; do
      if [[ -d $DEST/$s ]]; then echo "updating $DEST/$s"; else echo "installing $DEST/$s"; fi
      rm -rf "${DEST:?}/$s"
      cp -R "$SRC/$s" "$DEST/$s"
    done
    chmod +x "$DEST/handoff/handoff.sh"
    echo "done: restart Claude Code (or start a new session), then use /handoff and /pickup"
    ;;
  --uninstall)
    for s in "${SKILLS[@]}"; do
      if [[ -d $DEST/$s ]]; then rm -rf "${DEST:?}/$s"; echo "removed $DEST/$s"; fi
    done
    echo "done: saved handoffs were kept"
    ;;
  *)
    echo "usage: $0 [--uninstall]" >&2
    exit 2
    ;;
esac
