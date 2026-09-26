#!/usr/bin/env bash
# Tests for skills/handoff/handoff.sh. Usage: tests/test.sh
# Runs against a throwaway HANDOFF_ROOT and throwaway projects; touches nothing else.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/skills/handoff/handoff.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

export HANDOFF_ROOT="$TMP/root"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

PASS=0 FAIL=0
OUT=""

# run PROJECT CMD [ARG]: runs the script from the current dir, captures output,
# and fails the test if the exit code is not 0.
run() {
  OUT=$("$SCRIPT" "$@" 2>&1)
  local rc=$?
  [[ $rc -eq 0 ]] || fail "exit code $rc for: $*"
}

ok() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; printf '    | %s\n' "$OUT"; }

assert() { local msg=$1; shift; if "$@"; then ok; else fail "$msg"; fi; }
has() { if grep -qF -- "$1" <<<"$OUT"; then ok; else fail "${2:-expected \"$1\"}"; fi; }
lacks() { if grep -qF -- "$1" <<<"$OUT"; then fail "${2:-unexpected \"$1\"}"; else ok; fi; }

# save PROJECT TASK TITLE: creates a handoff the way the skill does and prints its path.
save() {
  local file
  file=$("$SCRIPT" "$1" new "$2" | sed -n 's/^file: //p')
  { "$SCRIPT" "$1" meta; echo "task: $2"; echo "title: $3"; echo "---"; echo "# $3"; } >"$file"
  echo "$file"
}

# --- usage ---------------------------------------------------------------
run
has "usage:" "no arguments prints usage"
run "$TMP/missing" show
has "usage:" "missing project dir prints usage"
run "$TMP" bogus
has "usage:" "unknown command prints usage"

# --- plain directory -----------------------------------------------------
P="$TMP/plain"; mkdir -p "$P"; cd "$P" || exit 1

run "$P" show
has "NO HANDOFF" "empty project reports no handoff"

run "$P" tasks
has "(no tasks)"

run "$P" meta
has "repo: none"
has "dir: $P"

run "$P" new "Bad Name"
has "INVALID TASK"
run "$P" new _archive
has "INVALID TASK" "_archive is reserved"

F1=$(save "$P" alpha "Alpha task")
case $F1 in "$HANDOFF_ROOT"/*/alpha/*.md) ok ;; *) fail "new returns a path under the task dir: $F1" ;; esac

run "$P" show
has "task: alpha" "single task is shown without choosing"
has "# Alpha task"
has "## staleness"

sleep 1
F2=$(save "$P" alpha "Alpha task v2")
run "$P" new alpha
has "previous: $F2" "new reports the latest handoff as previous"

save "$P" beta "Beta task" >/dev/null
run "$P" show
has "CHOOSE TASK" "several tasks require a choice"
has "@alpha | Alpha task v2"
has "@beta | Beta task"

run "$P" show @alpha
has "file: $F2" "show @task picks the latest handoff"
run "$P" show alpha
has "file: $F2" "show accepts a task without @"
run "$P" show @alp
has "NO TASK: @alp" "no prefix matching"
has "@beta" "unknown task lists the tasks"

run "$P" show "$F1"
has "file: $F1" "show accepts a file path"
run "$P" stale "$TMP/nope.md"
has "NO FILE"

# --- prune ---------------------------------------------------------------
D=$(dirname "$F1")
for i in 1 2 3 4 5; do : >"$D/2000-01-0${i}_000000.md"; done
HANDOFF_KEEP=3 run "$P" prune alpha
n=$(find "$D" -name '*.md' | wc -l | tr -d ' ')
assert "prune keeps HANDOFF_KEEP files (got $n)" [ "$n" -eq 3 ]
assert "prune keeps the newest handoff" [ -f "$F2" ]

# --- done / archive ------------------------------------------------------
run "$P" "done" beta
has "archived: @beta"
run "$P" show @beta
has "ARCHIVED: @beta" "archived task is reported"
has "mv " "archived message includes restore hint"
run "$P" tasks
lacks "@beta" "archived task is hidden from the list"
run "$P" "done" beta
has "NO TASK: @beta"
run "$P" show
has "task: alpha" "one task left after archiving"

# --- git repository ------------------------------------------------------
G="$TMP/repo"; mkdir -p "$G/sub"; cd "$G" || exit 1
git init -q -b main . && git commit -q --allow-empty -m first

cd "$G/sub" || exit 1
run "$G" meta
has "repo: $G"
has "branch: main"
has "dir: $G/sub" "dir is the cwd, not the project"

run "$G" git
has "## recent commits"
has "first"

GF=$(save "$G" gtask "Git task")
run "$G" show @gtask
has "commits since handoff: 0"
lacks "WARNING"

git commit -q --allow-empty -m second
echo x >"$G/dirty.txt"
run "$G" show @gtask
has "commits since handoff: 1"
has "second"
has "dirty: ?? dirty.txt"

git worktree add -q "$TMP/wt" -b feature 2>/dev/null
run "$TMP/wt" show @gtask
has "file: $GF" "worktrees share the main repo's handoffs"

git reset -q --hard HEAD~1 && git commit -q --allow-empty -m other
git reflog expire --expire=now --all && git gc -q --prune=now 2>/dev/null
sed -i.bak "s/^commit: .*/commit: 0123456789abcdef0123456789abcdef01234567/" "$GF" && rm -f "$GF.bak"
run "$G" show @gtask
has "WARNING: handoff commit" "missing commit is reported"

sed -i.bak "s|^repo: .*|repo: $TMP/gone|" "$GF" && rm -f "$GF.bak"
run "$G" show @gtask
has "no longer exists" "missing work dir is reported"

# --- age -----------------------------------------------------------------
sed -i.bak "s/^created: .*/created: 2000-01-01 00:00:00 +0000/" "$F2" && rm -f "$F2.bak"
run "$P" show @alpha
if grep -qE '^age: [0-9]{5,}h' <<<"$OUT"; then ok; else fail "age is computed from created"; fi

echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
