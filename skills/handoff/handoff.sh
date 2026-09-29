#!/usr/bin/env bash
# Handoff storage helper. Usage: handoff.sh PROJECT_DIR COMMAND [ARGS]
#
# Handoffs are keyed by the session's project directory (pass
# ${CLAUDE_PROJECT_DIR}; the shell cwd drifts with `cd`) and a task slug:
#   $HANDOFF_ROOT/<project>/<task>.md                        latest handoff
#   $HANDOFF_ROOT/<project>/_archive/<task>.md               (finished tasks)
#   $HANDOFF_ROOT/<project>/_history/<task>/YYYY-MM-DD_HHMMSS.md  older handoffs
#   $HANDOFF_ROOT/<project>/_project.md                      (description, optional)
# <project> is the directory's name (lowercased, a-z0-9._- only), wherever the
# directory is: ~/x/app and /srv/app are the same project `app`. A project
# created with `describe --parent` is <parent>~<name> (x~app) and wins over
# <name> for directories named like that.
# Git metadata in the handoff comes from the cwd at save time (where the work
# happened), which may be a nested repo inside the project.
# Always exits 0: skill `!` injections abort on failure.
# Portable: bash 3.2+ (macOS), GNU and BSD userland, git 2.31+.
set -uo pipefail

# root: $HANDOFF_ROOT, else `root=` in the config file, else the default.
HANDOFF_CONFIG="${HANDOFF_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-handoff/config}"
config_root() {
  local v
  v=$(sed -n 's/^[[:space:]]*root[[:space:]]*=[[:space:]]*//p' "$HANDOFF_CONFIG" 2>/dev/null | tail -n 1)
  v=${v%"${v##*[![:space:]]}"}
  # shellcheck disable=SC2088  # a literal ~ in the file
  [[ $v == "~" || $v == "~/"* ]] && v=$HOME${v#\~}
  printf '%s' "$v"
}
ROOT=${HANDOFF_ROOT:-$(config_root)}
ROOT=${ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-handoff}
KEEP="${HANDOFF_KEEP:-10}"
[[ $KEEP =~ ^[1-9][0-9]*$ ]] || KEEP=10
ARCHIVE=_archive
HISTORY=_history
DESC=_project.md
PROJECT=${1:-}
CMD=${2:-}
WORKDIR=$(pwd -P)

# Directory name -> project name: lowercase, a-z0-9._- (runs of anything else
# become one -), no leading . _ or -; `root` for /.
name_of() {
  local n
  n=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' |
    LC_ALL=C sed -e 's/[^a-z0-9._-]/-/g' -e 's/--*/-/g' -e 's/^[._-]*//')
  echo "${n:-root}"
}
# Frontmatter value of KEY; a YAML "double" or 'single' quoted one unquoted.
field() { sed -n "s/^$1: //p" "$2" | head -n 1 | tr -d '\r' | unquote; }
unquote() {
  sed -e '/^".*"$/{s/^"//;s/"$//;s/\\"/"/g;s/\\\\/\\/g;}' -e "/^'.*'\$/{s/^'//;s/'\$//;s/''/'/g;}"
}

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
# Cached in KEY: the dispatch below calls key once in the main shell, since
# $(key) runs in a subshell and could not keep the value.
key() {
  [[ -n ${KEY:-} ]] || KEY=$ROOT/$(
    cd "$PROJECT" || exit
    d=$(pwd -P) n=$(name_of "${d##*/}")
    p=${d%/*}; p=${p##*/}
    if [[ -n $p ]] && p=$(name_of "$p") && [[ -d $ROOT/$p~$n ]]; then echo "$p~$n"; else echo "$n"; fi
  )
  echo "$KEY"
}

# Absolute path of the project dir.
project_dir() { (cd "$PROJECT" && pwd -P); }

# Path for a handoff: relative inside the project (`.` for the project
# itself), ~/... under $HOME, else absolute.
# shellcheck disable=SC2088  # a literal ~/ is written to the handoff
relpath() {
  local p=$1 pd; pd=$(project_dir)
  case $p in
    "$pd") echo . ;;
    "$pd"/*) echo "${p#"$pd"/}" ;;
    "$HOME") echo "~" ;;
    "$HOME"/*) echo "~/${p#"$HOME"/}" ;;
    *) echo "$p" ;;
  esac
}

# A path from a handoff (see relpath) -> absolute. PROJECT_WAS is the
# handoff's `project:`; an old absolute path under it follows the project
# when it has moved.
# shellcheck disable=SC2088  # a literal ~/ read from the handoff
abspath() {
  local p=$1 pd was=${2:-}; pd=$(project_dir)
  case $p in
    .) echo "$pd" ;;
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${p#"~/"}" ;;
    /*)
      if [[ ! -e $p && -n $was && ($p == "$was" || $p == "$was"/*) ]]; then
        echo "$pd${p#"$was"}"
      else
        echo "$p"
      fi ;;
    *) echo "$pd/$p" ;;
  esac
}

valid_task() { [[ $1 =~ ^[a-z0-9][a-z0-9._-]*$ ]]; }

# A task is one file: <key>/<task>.md (active) or <key>/_archive/<task>.md
# (done). Its older handoffs are in <key>/_history/<task>/, for both.
# stamp FILE: YYYY-MM-DD_HHMMSS from its `created`, else from its mtime.
stamp() {
  local c; c=$(field created "$1")
  if [[ $c =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
    echo "${BASH_REMATCH[1]}_${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
  else
    # GNU `date -r FILE`; BSD/macOS `-r` takes epoch seconds.
    date -r "$1" +%Y-%m-%d_%H%M%S 2>/dev/null ||
      date -r "$(stat -f %m "$1" 2>/dev/null)" +%Y-%m-%d_%H%M%S 2>/dev/null || echo 0000-00-00_000000
  fi
}

# to_history FILE TASK: moves a handoff into the task's history, named by its stamp.
to_history() {
  local d="$KEY/$HISTORY/$2" s n=0 f
  s=$(stamp "$1")
  mkdir -p "$d" || return
  f="$d/$s.md"
  while [[ -e $f ]]; do n=$((n + 1)); f="$d/${s}_$n.md"; done
  mv -- "$1" "$f" && echo "$f"
}

# Older handoffs of a task, oldest first (C order: <stamp>.md before <stamp>_1.md).
handoffs() {
  local f
  for f in "$(key)/$HISTORY/$1"/*.md; do [[ -f $f ]] && echo "$f"; done | LC_ALL=C sort
}

# latest TASK | latest _archive/TASK: the task's file, or nothing.
latest() { [[ -f $(key)/$1.md ]] && echo "$KEY/$1.md"; }

# "YYYY-MM-DD HH:MM:SS +ZZZZ" -> epoch seconds (GNU date, then BSD date).
epoch() {
  date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S %z' "$1" +%s 2>/dev/null
}

# Task names, most recently saved first; `task_names _archive` lists archived ones.
task_names() {
  local f t pre=${1:+$1/}
  for f in "$(key)/$pre"*.md; do
    [[ -f $f ]] || continue
    t=$(basename "$f" .md); valid_task "$t" || continue
    echo "$(stamp "$f") $t"
  done | LC_ALL=C sort -r | cut -d' ' -f2
}

# First line of a handoff's ## State section, without a list marker.
state_line() {
  awk '/^## /{on=($0=="## State"); next} on && NF {sub(/^[-*] +/, ""); print; exit}' "$1" | tr -d '\r'
}

# Status of a task: active, done YYYY-MM-DD (archived) or missing.
task_status() {
  local f
  if [[ -n $(latest "$1") ]]; then echo active
  elif f=$(latest "$ARCHIVE/$1"); [[ -n $f ]]; then f=$(stamp "$f"); echo "done ${f%_*}"
  else echo missing
  fi
}

# Forks of a task (tasks whose latest handoff has `from: TASK`), active first:
# @task | title | status | first line of State
forks() {
  local t f pre
  for pre in "" "$ARCHIVE/"; do
    while read -r t; do
      [[ -n $t ]] || continue
      f=$(latest "$pre$t")
      [[ $(field from "$f") == "$1" ]] || continue
      printf '@%s | %s | %s | %s\n' "$t" "$(field title "$f")" "$(task_status "$t")" "$(state_line "$f")"
    done < <(task_names "${pre%/}")
  done
}

# @query -> task (exact name). Prints the task or a message.
resolve() {
  local q=${1#@}
  if valid_task "$q" && [[ -f $(key)/$q.md ]]; then
    echo "$q"
  elif valid_task "$q" && [[ -f $(key)/$ARCHIVE/$q.md ]]; then
    echo "ARCHIVED: @$q"; return 1
  else
    echo "NO TASK: @$q"; return 1
  fi
}

cmd_meta() {
  echo "project: $(project_dir)"
  echo "dir: $(relpath "$WORKDIR")"
  if in_git; then
    echo "branch: $(branch)"
    echo "commit: $(git rev-parse -q --verify HEAD 2>/dev/null || echo none)"
  else
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

# tasks [all]: active tasks; with `all`, then archived ones marked `archived`.
cmd_tasks() {
  local t f ts pre n=0 dirs=("")
  [[ ${1:-} == all ]] && dirs+=("$ARCHIVE/")
  for pre in "${dirs[@]}"; do
    while read -r t; do
      [[ -n $t ]] || continue
      f=$(latest "$pre$t"); n=$((n + 1))
      ts=$(stamp "$f")
      printf '@%s | %s | %s %s:%s%s\n' "$t" "$(field title "$f")" "${ts%_*}" "${ts:11:2}" "${ts:13:2}" "${pre:+ | archived}"
    done < <(task_names "${pre%/}")
  done
  ((n)) || echo "(no tasks)"
}

# new TASK: the task's file is free to write; the previous handoff, if any,
# moves to the history and is printed as `latest`. With no file (a /handoff
# stopped before writing it), `latest` is the newest in the history.
cmd_new() {
  local t=${1#@} f prev=""
  valid_task "$t" || { echo "INVALID TASK: '$t' (use lowercase a-z0-9._-)"; return; }
  mkdir -p "$(key)" || return
  f="$KEY/$t.md"
  if [[ -f $f ]]; then prev=$(to_history "$f" "$t")
  elif [[ ! -f $KEY/$ARCHIVE/$t.md ]]; then prev=$(handoffs "$t" | tail -n 1)
  fi
  echo "file: $f"
  echo "task: $t"
  echo "latest: $prev"
  if [[ -z $prev && -f $KEY/$ARCHIVE/$t.md ]]; then
    echo "note: @$t was archived; to continue it instead, restore it: /pickup @$t offers Restore"
  fi
}

# cancel TASK: undoes `new` when no file was written: the newest handoff in
# the history becomes the task's file again.
cmd_cancel() {
  local t=${1#@} f
  valid_task "$t" || { echo "INVALID TASK: '$t'"; return; }
  if [[ -f $(key)/$t.md ]]; then echo "kept: @$t"; return; fi
  f=$(handoffs "$t" | tail -n 1)
  [[ -n $f ]] || { echo "NO TASK: @$t"; return; }
  mv -- "$f" "$KEY/$t.md" && rmdir -- "$KEY/$HISTORY/$t" "$KEY/$HISTORY" 2>/dev/null
  echo "kept: @$t"
}

# prune TASK: keeps the newest KEEP-1 older handoffs (the task's file is the KEEP-th).
cmd_prune() {
  local t=${1#@}
  valid_task "$t" || return
  handoffs "$t" | LC_ALL=C sort -r | tail -n +"$KEEP" | while read -r f; do rm -f -- "$f"; done
  rmdir -- "$KEY/$HISTORY/$t" "$KEY/$HISTORY" 2>/dev/null
}

# move_task SRC DST TASK: moves a task file; one already at DST goes to the history.
move_task() {
  [[ -f $2 ]] && { to_history "$2" "$3" >/dev/null || return; }
  mkdir -p "$(dirname "$2")" && mv -- "$1" "$2"
}

cmd_done() {
  local t=${1#@}
  if ! valid_task "$t" || [[ ! -f $(key)/$t.md ]]; then echo "NO TASK: @$t"; return; fi
  move_task "$KEY/$t.md" "$KEY/$ARCHIVE/$t.md" "$t" && echo "archived: @$t -> $KEY/$ARCHIVE/$t.md"
}

# Runs in a subshell: it cd's into the dir recorded in the handoff.
cmd_stale() (
  local f commit created dir
  [[ -f ${1:-} ]] || { echo "NO FILE: ${1:-}"; exit; }
  f="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  commit=$(field commit "$f")
  created=$(field created "$f")
  dir=$(field dir "$f")
  [[ -n $dir ]] && dir=$(abspath "$dir" "$(field project "$f")")
  echo "## staleness"
  echo "created: ${created:-unknown}"
  if [[ -n $created ]]; then
    local saved h
    if saved=$(epoch "$created"); then
      h=$((($(date +%s) - saved) / 3600))
      if ((h < 48)); then echo "age: ${h}h"; else echo "age: $((h / 24))d"; fi
    fi
  fi
  if [[ -n $dir ]]; then
    cd "$dir" 2>/dev/null || { echo "WARNING: work dir $dir no longer exists"; exit; }
    echo "work dir: $dir"
  fi
  if in_git; then
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || :  # dirty paths relative to the repo
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

# restore TASK: moves an archived task back (an active one goes to the history first).
cmd_restore() {
  local t=${1#@}
  if ! valid_task "$t" || [[ ! -f $(key)/$ARCHIVE/$t.md ]]; then echo "NO TASK: @$t (not archived)"; return; fi
  move_task "$KEY/$ARCHIVE/$t.md" "$KEY/$t.md" "$t" && echo "restored: @$t"
}

# show [@task|task|FILE]; with no argument, the only task or a task list.
# A FILE must contain a slash or end in .md; words after a task are ignored.
cmd_show() {
  local arg=${1:-} f t
  if [[ ($arg == */* || $arg == *.md) && -f $arg ]]; then
    f=$arg
  elif [[ -n $arg ]]; then
    if ! t=$(resolve "${arg%%[[:space:]]*}"); then
      echo "$t"
      # An archived task's last handoff stays readable without a restore.
      [[ $t == ARCHIVED:* ]] && echo "file: $(latest "$ARCHIVE/${t#ARCHIVED: @}")"
      echo; echo "## tasks"; cmd_tasks; return
    fi
    f=$(latest "$t")
  else
    local names; names=$(task_names)
    if [[ -z $names ]]; then
      echo "NO HANDOFF for project=$(project_dir) ($(key))"
      return
    fi
    if [[ $(wc -l <<<"$names") -gt 1 ]]; then
      echo "CHOOSE TASK"
      echo; echo "## tasks"; cmd_tasks
      return
    fi
    f=$(latest "$names")
  fi
  # <key>/t.md, <key>/_archive/t.md or <key>/_history/t/<stamp>.md
  t=$(basename "$f" .md)
  [[ $(basename "$(dirname "$(dirname "$f")")") == "$HISTORY" ]] && t=$(basename "$(dirname "$f")")
  echo "file: $f"
  echo "task: $t"
  project_line
  local from list; from=$(field from "$f")
  valid_task "$from" && echo "fork of: @$from ($(task_status "$from"))"
  echo
  cmd_stale "$f"
  list=$(forks "$t")
  if [[ -n $list ]]; then
    echo
    echo "## forks"
    echo "$list"
  fi
  echo
  echo "## handoff"
  cat "$f"
}

# Project line: `project: @name — description`.
project_line() {
  local d
  d=$(desc_text)
  echo "project: @${KEY#"$ROOT"/}${d:+ — $d}"
}
desc_text() { [[ -f $KEY/$DESC ]] && tr '\r\n' '  ' <"$KEY/$DESC" | sed 's/  *$//'; }

# describe [--parent|--no-parent] [TEXT]: prints or sets the project's
# description. --parent makes <parent>~<name> this directory's project (a new
# one; <name> stays as it is); --no-parent renames it back to <name>.
cmd_describe() {
  local mode="" d n p
  case ${1:-} in --parent|--no-parent) mode=$1; shift ;; esac
  d=$(project_dir) n=$(name_of "${d##*/}") p=${d%/*}; p=${p##*/}
  case $mode in
    --parent)
      [[ -n $p ]] || { echo "NO PARENT: $d"; return; }
      p=$(name_of "$p")
      if [[ $KEY != "$ROOT/$p~$n" ]]; then
        mkdir -p "$ROOT/$p~$n" || return
        KEY=$ROOT/$p~$n TIPS_SLUG=""
        echo "note: project is now @$p~$n; @$n is kept as it was"
      fi ;;
    --no-parent)
      if [[ $KEY == "$ROOT/$n" ]]; then :
      elif [[ -e $ROOT/$n || -e $TIPS_ROOT/$n ]]; then
        echo "EXISTS: @$n; merge or remove it by hand first"; return
      else
        mv -- "$KEY" "$ROOT/$n" || return
        [[ -d $TIPS_ROOT/${KEY##*/} ]] && mv -- "$TIPS_ROOT/${KEY##*/}" "$TIPS_ROOT/$n"
        echo "note: project @${KEY##*/} renamed to @$n"
        KEY=$ROOT/$n TIPS_SLUG=""
      fi ;;
  esac
  if (($#)); then
    mkdir -p "$KEY" && printf '%s\n' "$*" >"$KEY/$DESC.tmp" && mv -- "$KEY/$DESC.tmp" "$KEY/$DESC"
  fi
  project_line
}

# shellcheck source=SCRIPTDIR/tips.sh
. "$(dirname "${BASH_SOURCE[0]}")/tips.sh"

USAGE="usage: handoff.sh PROJECT_DIR meta|git|tasks|describe [--parent|--no-parent] [TEXT]|new TASK|cancel TASK|prune TASK|done TASK|restore TASK|stale FILE|show [@TASK|FILE]|tips ..."

if [[ -z $PROJECT || ! -d $PROJECT ]]; then
  echo "$USAGE"
  exit 0
fi

# The hooks run on every prompt or failure: they compute the key only when
# there are tips to search (tips_init).
case "$CMD ${3:-}" in
  meta\ *|git\ *|"tips hook"|"tips prompt-hook") ;;
  *) key >/dev/null ;;
esac

case "$CMD" in
  meta) cmd_meta ;;
  git) cmd_git ;;
  tasks) project_line; cmd_tasks all ;;
  describe) shift 2; cmd_describe "$@" ;;
  new) cmd_new "${3:-}" ;;
  cancel) cmd_cancel "${3:-}" ;;
  prune) cmd_prune "${3:-}" ;;
  done) cmd_done "${3:-}" ;;
  restore) cmd_restore "${3:-}" ;;
  stale) cmd_stale "${3:-}" ;;
  show) cmd_show "${3:-}" ;;
  tips) shift 2; cmd_tips "$@" ;;
  *) echo "$USAGE" ;;
esac
exit 0
