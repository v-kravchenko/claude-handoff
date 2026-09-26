#!/usr/bin/env bash
# Installs the handoff and pickup skills as personal skills
# (${CLAUDE_CONFIG_DIR:-~/.claude}/skills), so they run as /handoff and /pickup,
# and the `handoffs` dashboard command into HANDOFF_BIN_DIR (default: ~/.local/bin,
# or $PREFIX/bin on Termux).
# Usage: ./install.sh [--uninstall]
# Saved handoffs (~/.claude/handoffs) are never touched.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd -P)"
SRC="$REPO/skills"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
SKILLS=(handoff pickup)
if [[ -n ${HANDOFF_BIN_DIR:-} ]]; then
  BIN=$HANDOFF_BIN_DIR
elif [[ -n ${TERMUX_VERSION:-} && -n ${PREFIX:-} ]]; then
  BIN=$PREFIX/bin
else
  BIN=$HOME/.local/bin
fi
DASH=handoffs

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
    mkdir -p "$BIN"
    # Never overwrite another program called handoffs.
    if [[ -e $BIN/$DASH ]] && ! grep -q 'part of claude-handoff' "$BIN/$DASH" 2>/dev/null; then
      echo "warning: $BIN/$DASH exists and is not ours; skipped (set HANDOFF_BIN_DIR)" >&2
    else
      echo "installing $BIN/$DASH"
      cp "$REPO/bin/$DASH" "$BIN/$DASH"
      chmod +x "$BIN/$DASH"
    fi
    case ":$PATH:" in
      *":$BIN:"*) ;;
      *) echo "note: $BIN is not in PATH; add it to run \`$DASH\`" ;;
    esac
    command -v python3 >/dev/null 2>&1 ||
      echo "note: \`$DASH\` needs python3 (Termux: pkg install python)"
    echo "done: restart Claude Code (or start a new session), then use /handoff and /pickup;"
    echo "      run \`$DASH\` for the dashboard"
    ;;
  --uninstall)
    for s in "${SKILLS[@]}"; do
      if [[ -d $DEST/$s ]]; then rm -rf "${DEST:?}/$s"; echo "removed $DEST/$s"; fi
    done
    # Only remove a file that is ours.
    if [[ -f $BIN/$DASH ]] && grep -q 'part of claude-handoff' "$BIN/$DASH"; then
      rm -f "$BIN/$DASH"; echo "removed $BIN/$DASH"
    fi
    echo "done: saved handoffs were kept"
    ;;
  *)
    echo "usage: $0 [--uninstall]" >&2
    exit 2
    ;;
esac
