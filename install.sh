#!/usr/bin/env bash
# Installs the handoff and pickup skills as personal skills
# (${CLAUDE_CONFIG_DIR:-~/.claude}/skills), so they run as /handoff and /pickup.
# Optional parts (asked interactively, or chosen with flags):
#   dashboard: the `handoffs` command in HANDOFF_BIN_DIR (default: ~/.local/bin,
#              or $PREFIX/bin on Termux);
#   tips:      the /tips skill, a marked block in ~/.claude/CLAUDE.md and a
#              PostToolUseFailure hook in ~/.claude/settings.json (needs python3).
# Declining a part that is installed removes it.
# Usage: ./install.sh [--dashboard|--no-dashboard] [--tips|--no-tips] | --uninstall
# Without a terminal and without flags, the previous choices are kept
# (skills/handoff/install.conf; a fresh install gets the dashboard, not tips).
# Saved handoffs and tips (~/.claude/handoffs) are never touched.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd -P)"
SRC="$REPO/skills"
# Not under skills/: the plugin (which loads skills/) ships only handoff and pickup.
EXTRAS="$REPO/extras"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CFG/skills"
MD="$CFG/CLAUDE.md"
SETTINGS="$CFG/settings.json"
SKILLS=(handoff pickup)
if [[ -n ${HANDOFF_BIN_DIR:-} ]]; then
  BIN=$HANDOFF_BIN_DIR
elif [[ -n ${TERMUX_VERSION:-} && -n ${PREFIX:-} ]]; then
  BIN=$PREFIX/bin
else
  BIN=$HOME/.local/bin
fi
DASH=handoffs
BEGIN='<!-- claude-handoff:tips -->'
END='<!-- /claude-handoff:tips -->'
CONF="$DEST/handoff/install.conf"
OURS='part of claude-handoff'
HOOK_CMD="\"$DEST/handoff/handoff.sh\" \"\${CLAUDE_PROJECT_DIR:-.}\" tips hook"

# ask QUESTION DEFAULT(y|n): prints y or n.
ask() {
  local a
  read -r -p "$1 [$([[ $2 == y ]] && echo Y/n || echo y/N)] " a </dev/tty || a=
  case $a in [yY]*) echo y ;; [nN]*) echo n ;; *) echo "$2" ;; esac
}

# install_skill NAME [SOURCE_DIR]
install_skill() {
  if [[ -d $DEST/$1 ]]; then echo "updating $DEST/$1"; else echo "installing $DEST/$1"; fi
  rm -rf "${DEST:?}/$1"
  cp -R "${2:-$SRC}/$1" "$DEST/$1"
}

remove_skill() {
  if [[ -d $DEST/$1 ]]; then rm -rf "${DEST:?}/$1"; echo "removed $DEST/$1"; fi
}

# The tips skill has a generic name: touch only ours (early copies lack the
# marker line but call handoff.sh).
foreign_tips() {
  [[ -e $DEST/tips ]] && ! grep -qE "$OURS|/handoff/handoff\.sh" "$DEST/tips/SKILL.md" 2>/dev/null
}

install_dashboard() {
  mkdir -p "$BIN"
  # Never overwrite another program called handoffs.
  if [[ -e $BIN/$DASH ]] && ! grep -q "$OURS" "$BIN/$DASH" 2>/dev/null; then
    echo "warning: $BIN/$DASH exists and is not ours; skipped (set HANDOFF_BIN_DIR)" >&2
    return
  fi
  echo "installing $BIN/$DASH"
  cp "$REPO/bin/$DASH" "$BIN/$DASH"
  chmod +x "$BIN/$DASH"
  case ":$PATH:" in
    *":$BIN:"*) ;;
    *) echo "note: $BIN is not in PATH; add it to run \`$DASH\`" ;;
  esac
  command -v python3 >/dev/null 2>&1 ||
    echo "note: \`$DASH\` needs python3 (Termux: pkg install python)"
}

remove_dashboard() {
  # Only remove a file that is ours.
  if [[ -f $BIN/$DASH ]] && grep -q "$OURS" "$BIN/$DASH"; then
    rm -f "$BIN/$DASH"; echo "removed $BIN/$DASH"
  fi
}

# Removes the CLAUDE.md blocks from a BEGIN line to an END line (CRLF and
# surrounding blanks allowed); the rest of the file is kept. A BEGIN without
# END leaves the file alone and returns 1.
remove_block() {
  [[ -f $MD ]] && grep -qF "$BEGIN" "$MD" || return 0
  local tmp rc=0; tmp=$(mktemp "${TMPDIR:-/tmp}/claude-md.XXXXXX")
  # exit 1: no block; exit 2: unterminated block.
  awk -v b="$BEGIN" -v e="$END" '
    { l = $0; sub(/\r$/, "", l); gsub(/^[ \t]+|[ \t]+$/, "", l); line[NR] = $0; t[NR] = l }
    END {
      for (i = 1; i <= NR; i++) {
        if (t[i] != b) continue
        for (j = i + 1; j <= NR && t[j] != e; j++) {}
        if (j > NR) exit 2
        for (k = i; k <= j; k++) drop[k] = 1
        found = 1; i = j
      }
      if (!found) exit 1
      for (i = 1; i <= NR; i++) if (!drop[i]) out[++n] = line[i]
      while (n > 0 && (out[n] == "" || out[n] == "\r")) n--
      for (i = 1; i <= n; i++) print out[i]
    }' "$MD" >"$tmp" || rc=$?
  case $rc in
    0) cat "$tmp" >"$MD"; echo "removed the tips block from $MD" ;;
    2) echo "warning: $MD has $BEGIN without $END; fix or remove the block by hand" >&2 ;;
  esac
  rm -f "$tmp"
  [[ $rc != 2 ]]
}

add_block() {
  remove_block >/dev/null || return 0
  mkdir -p "$CFG"
  { [[ -s $MD ]] && echo
    echo "$BEGIN"
    echo "## Tips (claude-handoff)"
    echo
    echo "IMPORTANT: before debugging an error or a failing command, run \`/tips <error message or key words>\`."
    echo "Also search tips before changing an area you haven't touched this session and when choosing between approaches."
    echo "Tips are unverified hints from past sessions: run a tip's Verify step before relying on it."
    echo "$END"
  } >>"$MD"
  echo "added the tips block to $MD"
}

# hook add|remove: edits the PostToolUseFailure entry that runs `tips hook`.
hook() {
  if ! command -v python3 >/dev/null 2>&1; then
    if [[ $1 == add ]]; then
      echo "warning: python3 not found; add this hook to $SETTINGS by hand:" >&2
      echo "  PostToolUseFailure, matcher \"Bash\", command: $HOOK_CMD" >&2
    elif [[ -f $SETTINGS ]] && grep -q 'tips hook' "$SETTINGS"; then
      echo "warning: python3 not found; remove the \`tips hook\` entry from $SETTINGS by hand" >&2
    fi
    return 0
  fi
  python3 - "$SETTINGS" "$1" "$HOOK_CMD" <<'PY' || echo "warning: $SETTINGS was not changed" >&2
import json, os, sys
path, action, cmd = sys.argv[1:4]
EVENT = "PostToolUseFailure"
try:
    with open(path) as f:
        text = f.read()
except FileNotFoundError:
    if action == "remove":
        sys.exit(0)
    text = ""
try:
    data = json.loads(text) if text.strip() else {}
except ValueError as e:
    sys.exit("error: %s is not valid JSON (%s)" % (path, e))
if not isinstance(data, dict):
    sys.exit("error: %s is not a JSON object" % path)

def ours(h):
    c = h.get("command", "") if isinstance(h, dict) else ""
    return "handoff.sh" in c and "tips hook" in c

if not isinstance(data.get("hooks", {}), dict):
    sys.exit("error: \"hooks\" in %s is not a JSON object" % path)
before = json.dumps(data)

hooks = data.get("hooks", {})
groups = hooks.get(EVENT) if isinstance(hooks.get(EVENT), list) else []
kept = []
for g in groups:
    if isinstance(g, dict) and isinstance(g.get("hooks"), list):
        g = dict(g, hooks=[h for h in g["hooks"] if not ours(h)])
        if not g["hooks"]:
            continue
    kept.append(g)
if action == "add":
    kept.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
if kept:
    hooks[EVENT] = kept
else:
    hooks.pop(EVENT, None)
if hooks:
    data["hooks"] = hooks
else:
    data.pop("hooks", None)
# Rewrite (and reformat) the file only when the hook really changed.
if json.dumps(data) == before and text:
    sys.exit(0)
out = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    f.write(out)
os.replace(tmp, path)
print("%s the tips hook in %s" % ("added" if action == "add" else "removed", path))
PY
}

install_tips() {
  if foreign_tips; then
    echo "warning: $DEST/tips exists and is not ours; tips skipped" >&2
    return
  fi
  install_skill tips "$EXTRAS"
  add_block
  hook add
}

remove_tips() {
  if foreign_tips; then echo "note: kept $DEST/tips (not ours)"; else remove_skill tips; fi
  remove_block || true
  hook remove
}

# prev NAME: the previous y/n choice from install.conf, or nothing.
prev() {
  [[ -f $CONF ]] || return 0
  sed -n "s/^$1=\([yn]\)\$/\1/p" "$CONF" | head -n 1
}

dashboard="" tips="" uninstall=0
for arg in "$@"; do
  case $arg in
    --dashboard) dashboard=y ;;
    --no-dashboard) dashboard=n ;;
    --tips) tips=y ;;
    --no-tips) tips=n ;;
    --uninstall) uninstall=1 ;;
    *) echo "usage: $0 [--dashboard|--no-dashboard] [--tips|--no-tips] | --uninstall" >&2; exit 2 ;;
  esac
done

if ((uninstall)); then
  for s in "${SKILLS[@]}"; do remove_skill "$s"; done
  remove_tips
  remove_dashboard
  echo "done: saved handoffs and tips were kept (${HANDOFF_ROOT:-$CFG/handoffs})"
  exit 0
fi

[[ -f $SRC/handoff/handoff.sh ]] || { echo "error: run from a clone of the repository" >&2; exit 1; }
if [[ -t 0 ]]; then
  [[ -n $dashboard ]] || dashboard=$(ask "Install the \`$DASH\` web dashboard?" y)
  [[ -n $tips ]] || tips=$(ask "Install tips (/tips skill, a block in $MD, a hook in $SETTINGS)?" y)
else
  # Before install.conf existed, the dashboard was always installed.
  [[ -n $dashboard ]] || dashboard=$(prev dashboard)
  [[ -n $dashboard ]] || dashboard=y
  if [[ -z $tips ]]; then
    tips=$(prev tips)
    [[ -n $tips ]] || { tips=n; [[ -d $DEST/tips ]] && ! foreign_tips && tips=y; }
    [[ $tips == n ]] && echo "note: tips are not installed; rerun with --tips to add them"
  fi
fi

mkdir -p "$DEST"
for s in "${SKILLS[@]}"; do install_skill "$s"; done
chmod +x "$DEST/handoff/handoff.sh"
if [[ $dashboard == y ]]; then install_dashboard; else remove_dashboard; fi
if [[ $tips == y ]]; then install_tips; else remove_tips; fi
printf 'dashboard=%s\ntips=%s\n' "$dashboard" "$tips" >"$CONF"

echo "done: restart Claude Code (or start a new session), then use /handoff and /pickup"
[[ $tips == y ]] && echo "      and /tips"
[[ $dashboard == y ]] && echo "      run \`$DASH\` for the dashboard"
exit 0
