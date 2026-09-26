#!/usr/bin/env bash
# Handoff storage helper. Usage: handoff.sh PROJECT_DIR COMMAND [ARGS]
#
# Handoffs are keyed by the session's project directory (pass
# ${CLAUDE_PROJECT_DIR}; the shell cwd drifts with `cd`) and a task slug:
#   $HANDOFF_ROOT/<project-slug>/<task>/YYYY-MM-DD_HHMMSS.md
#   $HANDOFF_ROOT/<project-slug>/_archive/<task>/...   (finished tasks)
# Inside git the project key is the main repo root, so worktrees share it.
# Git metadata in the handoff comes from the cwd at save time (where the work
# happened), which may be a nested repo inside the project.
# Always exits 0: skill `!` injections abort on failure.
# Portable: bash 3.2+ (macOS), GNU and BSD userland, git 2.31+.
set -uo pipefail

ROOT="${HANDOFF_ROOT:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"
KEEP="${HANDOFF_KEEP:-10}"
[[ $KEEP =~ ^[1-9][0-9]*$ ]] || KEEP=10
ARCHIVE=_archive
PROJECT=${1:-}
CMD=${2:-}
WORKDIR=$(pwd -P)

# /path/to/dir -> path~to~dir; $HOME -> home, $HOME/x -> home~x; / -> root.
slug() {
  local p=$1
  case $p in
    "$HOME") p=home ;;
    "$HOME"/*) p=home${p#"$HOME"} ;;
  esac
  p=${p#/}
  if [[ -n $p ]]; then tr / '~' <<<"$p"; else echo root; fi
}
field() { sed -n "s/^$1: //p" "$2" | head -n 1; }

in_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

repo_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [[ $common == */.git ]]; then dirname "$common"; else git rev-parse --show-toplevel; fi
}

branch() {
  git symbolic-ref --short -q HEAD || echo "detached-$(git rev-parse --short HEAD 2>/dev/null)"
}

# Key is computed inside the project dir, independent of the caller's cwd.
key() (
  cd "$PROJECT" || exit
  local base; if in_git; then base=$(repo_root); else base=$(pwd -P); fi
  echo "$ROOT/$(slug "$base")"
)

valid_task() { [[ $1 =~ ^[a-z0-9][a-z0-9._-]*$ && $1 != "$ARCHIVE" ]]; }

# Handoffs of a task, oldest first (timestamped names sort chronologically).
handoffs() {
  local f
  for f in "$(key)/$1"/*.md; do [[ -f $f ]] && echo "$f"; done
}

latest() { handoffs "$1" | tail -n 1; }

# "YYYY-MM-DD HH:MM:SS +ZZZZ" -> epoch seconds (GNU date, then BSD date).
epoch() {
  date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S %z' "$1" +%s 2>/dev/null
}

# Task names, most recently saved first.
task_names() {
  local d f
  for d in "$(key)"/*/; do
    [[ -d $d ]] || continue
    d=$(basename "$d"); [[ $d == "$ARCHIVE" ]] && continue
    f=$(latest "$d"); [[ -n $f ]] && echo "$(basename "$f") $d"
  done | sort -r | cut -d' ' -f2
}

# Shell command that moves an archived task back (also merges into an active
# task of the same name).
restore_cmd() {
  local k; k=$(key)
  echo "mkdir -p '$k/$1' && mv '$k/$ARCHIVE/$1'/*.md '$k/$1'/ && rmdir '$k/$ARCHIVE/$1'"
}

# @query -> task (exact name). Prints the task or a message.
resolve() {
  local q=${1#@}
  if valid_task "$q" && [[ -d $(key)/$q ]]; then
    echo "$q"
  elif valid_task "$q" && [[ -d $(key)/$ARCHIVE/$q ]]; then
    echo "ARCHIVED: @$q (restore: $(restore_cmd "$q"))"; return 1
  else
    echo "NO TASK: @$q"; return 1
  fi
}

cmd_meta() {
  echo "project: $(cd "$PROJECT" && pwd -P)"
  echo "dir: $WORKDIR"
  if in_git; then
    echo "repo: $(repo_root)"
    echo "branch: $(branch)"
    echo "commit: $(git rev-parse -q --verify HEAD 2>/dev/null || echo none)"
  else
    echo "repo: none"
    echo "branch: none"
    echo "commit: none"
  fi
  echo "created: $(date '+%Y-%m-%d %H:%M:%S %z')"
}

cmd_git() {
  in_git || { echo "(not a git repository: $WORKDIR)"; return; }
  echo "## git status ($(repo_root))"
  git status --short --branch 2>/dev/null | head -n 40
  echo
  echo "## recent commits"
  git log --oneline -n 10 2>/dev/null || echo "(no commits)"
}

cmd_tasks() {
  local t f n=0
  while read -r t; do
    [[ -n $t ]] || continue
    f=$(latest "$t"); n=$((n + 1))
    local ts; ts=$(basename "$f" .md)
    printf '@%s | %s | %s %s:%s\n' "$t" "$(field title "$f")" "${ts%_*}" "${ts:11:2}" "${ts:13:2}"
  done < <(task_names)
  ((n)) || echo "(no tasks)"
}

cmd_new() {
  local t=${1#@} f
  valid_task "$t" || { echo "INVALID TASK: '$t' (use lowercase a-z0-9._-)"; return; }
  local prev; prev=$(latest "$t")
  mkdir -p "$(key)/$t"
  # Names have one-second resolution; never hand out an existing file.
  while f="$(key)/$t/$(date +%Y-%m-%d_%H%M%S).md"; [[ -e $f ]]; do sleep 1; done
  echo "file: $f"
  echo "task: $t"
  echo "previous: $prev"
  if [[ -z $prev && -d $(key)/$ARCHIVE/$t ]]; then
    echo "note: @$t was archived; to continue it instead, restore: $(restore_cmd "$t")"
  fi
}

cmd_prune() {
  local t=${1#@}
  valid_task "$t" || return
  handoffs "$t" | sort -r | tail -n +"$((KEEP + 1))" | while read -r f; do rm -f -- "$f"; done
}

cmd_done() {
  local t=${1#@} dst
  if ! valid_task "$t" || [[ ! -d $(key)/$t ]]; then echo "NO TASK: @$t"; return; fi
  if [[ -z $(latest "$t") ]]; then
    rmdir -- "$(key)/$t" 2>/dev/null
    echo "NO TASK: @$t (no handoffs saved)"; return
  fi
  dst="$(key)/$ARCHIVE/$t"
  mkdir -p "$dst" && mv -- "$(key)/$t"/*.md "$dst"/ 2>/dev/null
  rmdir -- "$(key)/$t" 2>/dev/null
  echo "archived: @$t -> $dst"
}

# Runs in a subshell: it cd's into the repo/dir recorded in the handoff.
cmd_stale() (
  local f commit created dir
  [[ -f ${1:-} ]] || { echo "NO FILE: ${1:-}"; exit; }
  f="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  commit=$(field commit "$f")
  created=$(field created "$f")
  dir=$(field repo "$f")
  [[ -z $dir || $dir == none ]] && dir=$(field dir "$f")
  echo "## staleness"
  echo "created: ${created:-unknown}"
  if [[ -n $created ]]; then
    local saved
    saved=$(epoch "$created") && echo "age: $((($(date +%s) - saved) / 3600))h"
  fi
  if [[ -n $dir ]]; then
    cd "$dir" 2>/dev/null || { echo "WARNING: work dir $dir no longer exists"; exit; }
    echo "work dir: $dir"
  fi
  if in_git; then
    if [[ -n $commit && $commit != none ]]; then
      if git cat-file -e "$commit^{commit}" 2>/dev/null; then
        local n; n=$(git rev-list --count "$commit..HEAD" 2>/dev/null)
        echo "commits since handoff: $n"
        [[ $n -gt 0 ]] && git log --oneline -n 10 "$commit..HEAD"
        git merge-base --is-ancestor "$commit" HEAD 2>/dev/null ||
          echo "WARNING: handoff commit is not an ancestor of HEAD (rebase/reset?)"
      else
        echo "WARNING: handoff commit $commit not found (rebased or different repo?)"
      fi
    else
      local n; n=$(git rev-list --count HEAD 2>/dev/null || echo 0)
      echo "no commit at handoff time; commits now: $n"
      [[ $n -gt 0 ]] && git log --oneline -n 10
    fi
    git status --short 2>/dev/null | head -n 20 | sed 's/^/dirty: /'
  fi
)

# show [@task|task|FILE]; with no argument, the only task or a task list.
# A FILE must contain a slash or end in .md; words after a task are ignored.
cmd_show() {
  local arg=${1:-} f t
  if [[ ($arg == */* || $arg == *.md) && -f $arg ]]; then
    f=$arg
  elif [[ -n $arg ]]; then
    t=$(resolve "${arg%%[[:space:]]*}") || { echo "$t"; echo; echo "## tasks"; cmd_tasks; return; }
    f=$(latest "$t")
    [[ -n $f ]] || { echo "NO TASK: @$t (no handoffs saved)"; return; }
  else
    local names; names=$(task_names)
    if [[ -z $names ]]; then
      echo "NO HANDOFF for project=$(cd "$PROJECT" && pwd -P) ($(key))"
      return
    fi
    if [[ $(wc -l <<<"$names") -gt 1 ]]; then
      echo "CHOOSE TASK"
      echo; echo "## tasks"; cmd_tasks
      return
    fi
    f=$(latest "$names")
  fi
  echo "file: $f"
  echo "task: $(basename "$(dirname "$f")")"
  echo
  cmd_stale "$f"
  echo
  echo "## handoff"
  cat "$f"
}

USAGE="usage: handoff.sh PROJECT_DIR meta|git|tasks|new TASK|prune TASK|done TASK|stale FILE|show [@TASK|FILE]"

if [[ -z $PROJECT || ! -d $PROJECT ]]; then
  echo "$USAGE"
  exit 0
fi

case "$CMD" in
  meta) cmd_meta ;;
  git) cmd_git ;;
  tasks) cmd_tasks ;;
  new) cmd_new "${3:-}" ;;
  prune) cmd_prune "${3:-}" ;;
  done) cmd_done "${3:-}" ;;
  stale) cmd_stale "${3:-}" ;;
  show) cmd_show "${3:-}" ;;
  *) echo "$USAGE" ;;
esac
exit 0
