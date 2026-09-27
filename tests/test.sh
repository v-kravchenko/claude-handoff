#!/usr/bin/env bash
# Tests for skills/handoff/handoff.sh. Usage: tests/test.sh
# Runs against a throwaway HANDOFF_ROOT and throwaway projects; touches nothing else.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/skills/handoff/handoff.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")" && pwd -P)  # physical path (macOS /var -> /private/var)
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
has "latest: $F2" "new reports the latest handoff"

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

# --- plain directory staleness -------------------------------------------
cd "$P" || exit 1
run "$P" show @alpha
has "work dir: $P" "non-git handoff reports its work dir"
lacks "commits since" "non-git handoff has no git report"

# --- paths with spaces ---------------------------------------------------
S="$TMP/My Proj"; mkdir -p "$S"; cd "$S" || exit 1
SF=$(save "$S" spaced "Spaced task")
case $SF in *"My Proj/spaced/"*.md) ok ;; *) fail "project path with a space: $SF" ;; esac
run "$S" show @spaced
has "file: $SF" "show works in a project path with a space"

# --- skill injections, run the way Claude Code substitutes them ------------
SKILLS="$(dirname "$SCRIPT")/.."
# inject SKILL_NAME ARGUMENTS: runs every ```! block of the skill.
# shellcheck disable=SC2016  # literal placeholders
inject() {
  local cmd
  cmd=$(awk '/^```!$/ {on=1; next} /^```$/ {on=0} on' "$SKILLS/$1/SKILL.md")
  cmd=${cmd//'${CLAUDE_SKILL_DIR}'/$SKILLS/$1}
  cmd=${cmd//'${CLAUDE_PROJECT_DIR}'/$S}
  cmd=${cmd//'$ARGUMENTS'/$2}
  OUT=$(bash -c "$cmd" 2>&1) || fail "injection failed for /$1 $2"
}
inject handoff ""
has "project: $S" "/handoff meta works with a space in the project path"
has "@spaced | Spaced task" "/handoff task list works with a space in the project path"
lacks "usage:"
inject pickup ""
has "task: spaced" "/pickup works with a space in the project path"
inject pickup "@spaced some notes"
has "task: spaced" "/pickup ignores words after the task"

for f in "$SKILLS"/handoff/SKILL.md "$SKILLS"/pickup/SKILL.md "$SKILLS"/../extras/tips/SKILL.md; do
  s=$(basename "$(dirname "$f")")
  assert "$s: frontmatter starts the file" [ "$(head -n 1 "$f")" = "---" ]
  assert "$s: frontmatter is closed" [ "$(sed -n '2,$p' "$f" | grep -c '^---$')" -ge 1 ]
  assert "$s: name matches the directory" grep -qx "name: $s" "$f"
  assert "$s: has a description" grep -q '^description: .' "$f"
done
assert "pickup: offers a menu via AskUserQuestion" grep -q AskUserQuestion "$SKILLS/pickup/SKILL.md"
assert "pickup: restores via the script" grep -qF 'handoff.sh restore' "$SKILLS/pickup/SKILL.md"

# --- same-second saves -----------------------------------------------------
A=$(save "$S" fast "One"); B=$(save "$S" fast "Two")
assert "two saves in a row get different files" [ "$A" != "$B" ]
assert "the first save is kept" grep -q "title: One" "$A"

# --- HANDOFF_KEEP validation ---------------------------------------------
HANDOFF_KEEP=0 run "$S" prune fast
assert "HANDOFF_KEEP=0 falls back to the default" [ -f "$A" ]
assert "HANDOFF_KEEP=0 keeps the newest file" [ -f "$B" ]
HANDOFF_KEEP=abc run "$S" prune fast
assert "HANDOFF_KEEP=abc falls back to the default" [ -f "$A" ]

# --- aborted save, reopening ----------------------------------------------
run "$S" new empty
run "$S" "done" empty
has "no handoffs saved" "done on a task with no handoffs"
K=$(dirname "$(dirname "$SF")")
assert "no empty archive is created" [ ! -d "$K/_archive/empty" ]
assert "the empty task dir is removed" [ ! -d "$K/empty" ]

run "$S" "done" spaced
run "$S" new spaced
has "note: @spaced was archived" "new warns about an archived task of the same name"
C=$(save "$S" spaced "Spaced again")
run "$S" show @spaced
has "file: $C"
run "$S" "done" spaced
run "$S" show @spaced
restore=$(sed -n 's/^ARCHIVED: .*(restore: \(.*\))$/\1/p' <<<"$OUT")
assert "restore hint is printed" [ -n "$restore" ]
bash -c "$restore"
n=$(find "$K/spaced" -name '*.md' | wc -l | tr -d ' ')
assert "restore brings back all handoffs (got $n)" [ "$n" -eq 2 ]
assert "restore removes the archive entry" [ ! -d "$K/_archive/spaced" ]

# --- restore command -----------------------------------------------------
run "$S" "done" spaced
run "$S" restore @spaced
has "restored: @spaced"
n=$(find "$K/spaced" -name '*.md' | wc -l | tr -d ' ')
assert "restore command brings back all handoffs (got $n)" [ "$n" -eq 2 ]
assert "restore command removes the archive entry" [ ! -d "$K/_archive/spaced" ]
run "$S" restore spaced
has "NO TASK: @spaced (not archived)" "restore of an active task is refused"
run "$S" restore ../x
has "NO TASK:" "restore rejects invalid names"

# --- show: files vs tasks ------------------------------------------------
: >"$S/spaced"
run "$S" show spaced
has "file: $C" "a bare word is a task even if such a file exists"

# --- project keys ----------------------------------------------------------
mkdir -p "$TMP/h" "$TMP/hx"
HOME="$TMP/h" run "$TMP/h" new t
has "$HANDOFF_ROOT/home/t/" "\$HOME maps to home"
HOME="$TMP/h" run "$TMP/hx" new t
lacks "$HANDOFF_ROOT/homex" "a sibling of \$HOME is not treated as home"
HANDOFF_ROOT="$TMP/r2" run / new t
has "$TMP/r2/root/t/" "the filesystem root maps to root"

# --- tips ------------------------------------------------------------------
TP="$TMP/tipsproj"; mkdir -p "$TP"; cd "$TP" || exit 1
git init -q && echo one >a.txt && git add a.txt && git commit -qm one
C1=$(git rev-parse --short HEAD)
KEYDIR=$(basename "$("$SCRIPT" "$TP" new probe | sed -n 's/^file: //p' | xargs dirname | xargs dirname)")
TROOT="$HANDOFF_ROOT/_tips"
# tip DIR ID TITLE KEYWORDS [EXTRA_FRONTMATTER]: writes a tip file.
tip() {
  mkdir -p "$1"
  local extra=${5:-}
  [[ $extra == *status:* ]] || extra="status: active\n$extra"
  printf -- '---\ntitle: %s\nwhen: sometimes\nkeywords: %s\n%b---\nTip: body text here\nVerify: true\n' \
    "$3" "$4" "$extra" >"$1/$2.md"
}

run "$TP" tips
has "usage: handoff.sh PROJECT_DIR tips" "tips without a subcommand prints usage"
run "$TP" tips status
has "tips: off" "tips are off in the repo layout (the plugin loads skills/ only)"
assert "the plugin ships only handoff and pickup" [ "$(ls "$SKILLS")" = "$(printf 'handoff\npickup')" ]
TOFF="$TMP/notips"; mkdir -p "$TOFF"; cp -R "$SKILLS/handoff" "$TOFF/"
OUT=$("$TOFF/handoff/handoff.sh" "$TP" tips status)
has "tips: off" "tips are off without the tips skill next to handoff"
has "project tips: $TROOT/$KEYDIR"
has "global tips: $TROOT/_global"
run "$TP" tips list
has "(no tips)"
run "$TP" tips search anything
has "(no tips match: anything)"
run "$TP" tips search
has "usage: tips search"

run "$TP" tips new wt-key project
has "file: $TROOT/$KEYDIR/wt-key.md" "new: project tips go under _tips/<project>"
has "source: project=$KEYDIR commit=$C1" "new: source has the project and commit"
run "$TP" tips new Bad
has "INVALID ID"
run "$TP" tips new x nowhere
has "INVALID LEVEL"
tip "$TROOT/$KEYDIR" wt-key "git worktree breaks the handoff key" 'worktree, git-common-dir, "fatal: not a git repository"' "cites: a.txt@$C1\n"
tip "$TROOT/_global" no-tmp "Termux has no /tmp; use TMPDIR" 'TMPDIR, mktemp, "No such file or directory"'
tip "$TROOT/_global" mac-only "a macOS-only trick" 'worktree, darwin' "env: darwin-nowhere\n"
tip "$TROOT/_global" dead "an old refuted idea" 'worktree' "status: refuted\n"
tip "$TROOT/home~other" foreign "worktree tip of another project" 'worktree, git-common-dir'
run "$TP" tips new no-tmp global
has "EXISTS: no-tmp" "new refuses an id taken on either level"

run "$TP" tips search worktree handoff
has "wt-key | project | git worktree breaks the handoff key" "search finds a project tip"
lacks "foreign" "search never sees other projects"
lacks "mac-only" "search skips tips for another env"
lacks "dead |" "search skips refuted tips"
run "$TP" tips search worktrees
has "wt-key" "search matches a longer word form"
run "$TP" tips search tmp directory missing
has "no-tmp | global" "search finds a global tip"
run "$TP" tips search "totally unrelated words"
has "(no tips match"
run "$TP" tips search --error "mktemp: failed to create file via template /tmp/x: No such file or directory"
has "no-tmp" "error mode: a long keyword item matches"
run "$TP" tips search --error "cannot find module express"
has "(no tips match" "error mode: no match"
run "$TP" tips list
has "dead | global | refuted |" "list shows all levels and statuses"

run "$TP" tips show wt-key
has "level: project"
has "Verify: true"
lacks "WARNING" "show: no warning while cited files are unchanged"
echo two >a.txt
run "$TP" tips show wt-key
has "WARNING: a.txt has uncommitted changes"
git commit -qam two
run "$TP" tips show wt-key
has "WARNING: a.txt changed in 1 commit(s) since $C1" "show warns when a cited file changed"
run "$TP" tips show nope
has "NO TIP: nope"

run "$TP" tips verified no-tmp
has "verified: no-tmp"
assert "verified sets last_verified" grep -q "^last_verified: $(date +%Y-%m-%d)" "$TROOT/_global/no-tmp.md"
run "$TP" tips refuted wt-key it was fixed upstream
assert "refuted sets the status" grep -qx "status: refuted" "$TROOT/$KEYDIR/wt-key.md"
assert "refuted keeps the reason" grep -q "^refuted: .* it was fixed upstream" "$TROOT/$KEYDIR/wt-key.md"
assert "refuted keeps the body" grep -qx "Verify: true" "$TROOT/$KEYDIR/wt-key.md"
run "$TP" tips search worktree
lacks "wt-key" "a refuted tip is no longer found"
run "$TP" tips verified wt-key
run "$TP" tips search worktree
has "wt-key" "verified makes a refuted tip active again"
tip "$TROOT/$KEYDIR" wt-key2 "worktree key, newer" 'worktree'
run "$TP" tips supersede wt-key wt-key2
has "superseded: wt-key -> wt-key2"
assert "supersede links the new tip" grep -qx "superseded_by: wt-key2" "$TROOT/$KEYDIR/wt-key.md"
run "$TP" tips supersede wt-key2 wt-key2
has "SAME TIP"
run "$TP" tips move wt-key2 global
has "moved: wt-key2 -> global"
assert "move puts the file in _global" [ -f "$TROOT/_global/wt-key2.md" ]
run "$TP" tips move wt-key2 global
has "already global"
run "$TP" tips move wt-key2 elsewhere
has "usage: tips move"
assert "events are logged" grep -q '"event":"refuted","project":"'"$KEYDIR"'","id":"wt-key"' "$TROOT/log.jsonl"

# The hook reads Claude Code's PostToolUseFailure JSON; it stays silent while
# the tips skill is not installed.
HOOKIN='{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"mktemp -p /tmp","description":"x \"q\""},"error":"Exit code 1\nmktemp: failed to create file via template /tmp/tmp.X: No such file or directory","is_interrupt":false}'
OUT=$("$TOFF/handoff/handoff.sh" "$TP" tips hook <<<"$HOOKIN")
assert "hook is silent when tips are off" [ -z "$OUT" ]
TS="$TMP/tipskills"; mkdir -p "$TS"; cp -R "$SKILLS/handoff" "$SKILLS/../extras/tips" "$TS/"
OUT=$("$TS/handoff/handoff.sh" "$TP" tips status)
has "tips: on" "tips are on with the tips skill installed"
OUT=$("$TS/handoff/handoff.sh" "$TP" tips hook <<<"$HOOKIN")
if python3 -c 'import json,sys; d=json.loads(sys.argv[1])["hookSpecificOutput"]; assert d["hookEventName"]=="PostToolUseFailure"; assert "no-tmp (global)" in d["additionalContext"]' "$OUT" 2>/dev/null
then ok; else fail "hook prints valid JSON naming the matching tip"; fi
OUT=$("$TS/handoff/handoff.sh" "$TP" tips hook <<<'{"tool_name":"Bash","tool_input":{"command":"node x"},"error":"Exit code 1\nError: Cannot find module express","is_interrupt":false}')
assert "hook is silent without a match" [ -z "$OUT" ]
OUT=$("$TS/handoff/handoff.sh" "$TP" tips hook <<<"${HOOKIN/\"is_interrupt\":false/\"is_interrupt\":true}")
assert "hook is silent for an interrupt" [ -z "$OUT" ]
OUT=$("$TS/handoff/handoff.sh" "$TP" tips hook </dev/null)
assert "hook is silent on empty input" [ -z "$OUT" ]
assert "hook logs the matched ids" grep -q '"event":"hook","project":"'"$KEYDIR"'","id":"no-tmp"' "$TROOT/log.jsonl"
assert "hook does not log the error text" [ "$(grep '"event":"hook"' "$TROOT/log.jsonl" | grep -c 'failed to create')" = 0 ]
TNM="$TMP/tipsnomark"; mkdir -p "$TNM/tips"; cp -R "$SKILLS/handoff" "$TNM/"
printf -- '---\nname: tips\n---\nmine\n' >"$TNM/tips/SKILL.md"
OUT=$("$TNM/handoff/handoff.sh" "$TP" tips status)
has "tips: off" "tips are off with a foreign tips skill next to handoff"

# Awk gets text through ENVIRON: backslashes stay literal, no warnings.
tip "$TROOT/$KEYDIR" win-path "Windows path" '"C:\temp\build"'
run "$TP" tips search --error 'open C:\temp\build failed'
has "win-path" "error mode matches a keyword with backslashes"
lacks "warning" "no awk escape warnings"
run "$TP" tips refuted win-path 'bad \n regex'
assert "refuted keeps backslashes literal" grep -qF 'bad \n regex' "$TROOT/$KEYDIR/win-path.md"
run "$TP" tips refuted win-path "$(printf 'two\nlines')"
assert "refuted folds a newline into one line" grep -qx "refuted: $(date +%Y-%m-%d) two lines" "$TROOT/$KEYDIR/win-path.md"
# A quoted keyword keeps its commas.
tip "$TROOT/$KEYDIR" comma-kw "Comma message" '"permission denied, please try again"'
run "$TP" tips search --error "ssh: Permission denied, please try again."
has "comma-kw" "error mode matches a quoted keyword with a comma"
run "$TP" tips search --error "ls: Permission denied"
lacks "comma-kw" "error mode does not match a fragment of a quoted keyword"
# The log masks likely secrets.
run "$TP" tips search "token=hunter2 key ABCDEFGHIJKLMNOPQRSTUVWXYZ0123 fine"
assert "log masks a token value" [ "$(grep -c hunter2 "$TROOT/log.jsonl")" = 0 ]
assert "log masks a long token" [ "$(grep -c ABCDEFGHIJKLMNOP "$TROOT/log.jsonl")" = 0 ]
assert "log keeps plain words" grep -q 'token=\*\*\* key \*\*\* fine' "$TROOT/log.jsonl"

# Cites are checked in the session's checkout: a worktree, not the main repo.
C2=$(git -C "$TP" rev-parse --short HEAD)
git -C "$TP" worktree add -q "$TMP/tipswt" -b tipswt 2>/dev/null
echo worktree >"$TMP/tipswt/a.txt"; git -C "$TMP/tipswt" commit -qam worktree
tip "$TROOT/$KEYDIR" wt-cite "Worktree cite" "cite" "cites: a.txt@$C2\n"
run "$TMP/tipswt" tips show wt-cite
has "WARNING: a.txt changed in 1 commit(s) since $C2" "show checks cites in the worktree"
run "$TP" tips show wt-cite
lacks "WARNING" "show checks cites in the main checkout"
cd "$TMP" || exit 1

# --- dashboard (bin/handoffs) ----------------------------------------------
DASH="$(cd "$(dirname "$SCRIPT")/../.." && pwd -P)/bin/handoffs"
if ! command -v python3 >/dev/null 2>&1; then
  echo "skip: dashboard tests (no python3)"
else
  D="$TMP/dash"
  mkdir -p "$D/home~app/alpha" "$D/home~app/empty" "$D/home~app/_archive/old" "$D/other/bare" "$D/.hidden/x"
  cat >"$D/home~app/alpha/2026-09-25_101500.md" <<'EOF'
---
title: first
---
EOF
  cat >"$D/home~app/alpha/2026-09-26_173557.md" <<EOF
---
project: $P
repo: none
branch: none
created: 2026-09-26 17:35:57 +0300
task: alpha
title: Fix "quotes" & \`code\` — кирилиця
---

# Fix

## Goal
Line one of the goal
continues here.

Second paragraph is not shown.

## State
- 1. not a next step

## Next steps
1. First step
   wraps here.
2. Second
3. Third
4. Fourth
5. Fifth

## Verify
- nope
EOF
  printf -- '---\nproject: /no/such/dir\ntitle: archived one\n---\n## Goal\n%s\n' "$(printf 'word %.0s' {1..80})" \
    >"$D/home~app/_archive/old/2026-09-01_080000.md"
  printf 'no frontmatter here\n' >"$D/other/bare/2026-09-02_090000.md"
  printf -- '---\ntitle: hidden\n---\n' >"$D/.hidden/x/2026-09-03_090000.md"
  mkdir -p "$D/_tips/home~app" && printf -- '---\ntitle: a tip\n---\n' >"$D/_tips/home~app/tip.md"
  mkdir -p "$D/_tips/_global" "$D/_tips/home~gone"
  printf -- '---\r\ntitle: global one\r\nkeywords: a, "b, c"\r\nenv: termux\r\nstatus: refuted\r\n---\r\nTip: body\r\n' \
    >"$D/_tips/_global/g1.md"
  printf 'no frontmatter\n' >"$D/_tips/home~gone/raw.md"
  printf -- '---\ntitle: x\n---\n' | tee "$D/_tips/home~app/Bad Name.md" >"$D/_tips/home~app/.hidden.md"
  printf '{"event":"search"}\n' >"$D/_tips/log.jsonl"

  OUT=$(HANDOFF_ROOT="$D" python3 "$DASH" --json 2>&1) || fail "handoffs --json failed"
  # jcheck EXPR MSG: EXPR is Python over d (the JSON) and t (task by name).
  jcheck() {
    if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); t={x["task"]:x for x in d["tasks"]}; sys.exit(0 if eval(sys.argv[2]) else 1)' "$OUT" "$1" 2>/dev/null
    then ok; else fail "$2"; fi
  }
  jcheck 'sorted(t) == ["alpha", "bare", "old"]' "tasks: dirs without .md, dot dirs and _tips are skipped"
  # shellcheck disable=SC2016 # backticks are part of the expected title
  jcheck 't["alpha"]["title"] == "Fix \"quotes\" & `code` — кирилиця"' "title with quotes and Cyrillic"
  jcheck 't["alpha"]["versions"] == 2 and t["alpha"]["status"] == "active"' "versions and status"
  jcheck 't["alpha"]["created"] == "2026-09-26T17:35:57+03:00"' "created is ISO 8601"
  jcheck 't["alpha"]["goal"] == "Line one of the goal continues here."' "goal is the first paragraph"
  jcheck 't["alpha"]["next"] == ["First step wraps here.", "Second", "Third"] and t["alpha"]["next_more"] == 2' "next steps: 3 items plus the rest"
  jcheck 't["alpha"]["project"] == "'"$P"'" and t["alpha"]["project_exists"]' "project path from frontmatter"
  jcheck 't["alpha"]["repo"] == "" and t["alpha"]["branch"] == "" and t["alpha"]["slug"] == "home~app"' "missing repo/branch are empty"
  jcheck 't["old"]["status"] == "archived" and not t["old"]["project_exists"]' "archived task, missing path"
  jcheck 'len(t["old"]["goal"]) <= 201 and t["old"]["goal"].endswith("…")' "long goal is truncated"
  jcheck 't["bare"]["title"] == "bare" and t["bare"]["project"] == "other" and t["bare"]["created"].startswith("2026-09-02T09:00")' "no frontmatter: task name, slug, date from file name"
  jcheck '[x["task"] for x in d["tasks"]] == ["alpha", "bare", "old"]' "newest first"
  # tips: TT maps "slug/id" to the tip.
  TT='{x["slug"] + "/" + x["id"]: x for x in d["tips"]}'
  jcheck 'sorted('"$TT"') == ["_global/g1", "home~app/tip", "home~gone/raw"]' "tips: bad names, dot files and log.jsonl are skipped"
  jcheck '(lambda t: t["title"] == "a tip" and t["status"] == "active" and t["level"] == "project" and t["body"] == "")('"$TT"'["home~app/tip"])' "tip without status is active"
  jcheck '(lambda t: t["level"] == "global" and t["status"] == "refuted" and t["env"] == "termux" and t["keywords"] == "a, \"b, c\"" and t["body"] == "Tip: body")('"$TT"'["_global/g1"])' "global tip with CRLF and fields"
  jcheck '(lambda t: t["title"] == "raw" and t["body"] == "no frontmatter")('"$TT"'["home~gone/raw"])' "tip without frontmatter: id as title"

  OUT=$(HANDOFF_ROOT="$TMP/none" python3 "$DASH" --json 2>&1)
  jcheck 'd["tasks"] == []' "missing root gives no tasks"
  jcheck 'd["home"] and d["root"].endswith("none")' "reports home and root"

  # Git projects: the project dir is the repo (reported) vs. a nested repo (not).
  G="$TMP/gitproj"; mkdir -p "$G/nested"
  git -C "$G" init -q && git -C "$G" commit -q --allow-empty -m one
  GC=$(git -C "$G" rev-parse HEAD)
  git -C "$G" commit -q --allow-empty -m two
  git -C "$G/nested" init -q && git -C "$G/nested" commit -q --allow-empty -m n
  mkdir -p "$D/gitproj/repo" "$D/gitproj/nest"
  printf -- '---\nproject: %s\nrepo: %s\nbranch: main\ncommit: %s\ntitle: r\n---\n' "$G" "$G" "$GC" \
    >"$D/gitproj/repo/2026-09-04_090000.md"
  printf -- '---\nproject: %s\nrepo: %s/nested\nbranch: main\ncommit: %s\ntitle: n\n---\n' "$G" "$G" "$GC" \
    >"$D/gitproj/nest/2026-09-04_090000.md"
  # A worktree: repo is the main checkout, project and dir are the worktree.
  W="$TMP/gitwt"
  git -C "$G" worktree add -q -b wt "$W" 2>/dev/null
  W=$(cd "$W" && pwd -P)
  mkdir -p "$D/gitproj/wt"
  printf -- '---\nproject: %s\ndir: %s\nrepo: %s\nbranch: wt\ncommit: %s\ntitle: w\n---\n' "$W" "$W" "$G" "$GC" \
    >"$D/gitproj/wt/2026-09-04_090000.md"
  OUT=$(HANDOFF_ROOT="$D" python3 "$DASH" --json 2>&1)
  jcheck 't["repo"]["git"] and t["wt"]["git"] and not t["nest"]["git"] and not t["alpha"]["git"]' \
    "git info only for the project repo or its worktree"

  # HTTP: start on a free port, probe, stop.
  PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  HANDOFF_ROOT="$D" python3 "$DASH" --no-open --port "$PORT" >"$TMP/dash.log" 2>&1 &
  DPID=$!
  OUT=$(python3 - "$PORT" "$D" <<'EOF'
import http.client, os, sys, time
port = int(sys.argv[1])
def get(path, host):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.request("GET", path, headers={"Host": host})
    r = c.getresponse(); body = r.read().decode()
    return r.status, body
for _ in range(50):
    try:
        get("/", "127.0.0.1"); break
    except OSError:
        time.sleep(0.1)
h = "127.0.0.1:%d" % port
s, b = get("/", h); print("root", s, "<title>Handoffs</title>" in b)
s, b = get("/api/tasks", h); print("api", s, '"alpha"' in b)
s, b = get("/api/tasks", "localhost:%d" % port); print("localhost", s)
s, b = get("/api/tasks", "evil.example:%d" % port); print("evil", s)
s, b = get("/home~app/alpha/2026-09-26_173557.md", h); print("file", s)
s, b = get("/api/handoff?slug=home~app&status=active&task=alpha", h); print("body", s, "## Next steps" in b, "title:" not in b)
s, b = get("/api/handoff?slug=home~app&status=archived&task=old", h); print("archbody", s)
s, b = get("/api/handoff?slug=home~app&status=active&task=_archive", h); print("archdir", s)
s, b = get("/api/handoff?slug=..&status=active&task=root", h); print("traversal", s)
s, b = get("/api/handoff?slug=home~app&status=active&task=empty", h); print("nomd", s)
import json, re
A = "slug=home~app&status=active&task=alpha"
s, b = get("/api/history?" + A, h); v = json.loads(b); print("history", s, [x["file"] for x in v] == ["2026-09-26_173557.md", "2026-09-25_101500.md"])
s, b = get("/api/handoff?" + A + "&file=2026-09-25_101500.md", h); print("version", s)
s, b = get("/api/handoff?" + A + "&file=../../x.md", h); print("badfile", s)
s, b = get("/api/diff?" + A + "&old=2026-09-25_101500.md&new=2026-09-26_173557.md", h); print("diff", s, "+## Next steps" in json.loads(b)["diff"])
s, b = get("/api/diff?" + A + "&old=nope.md&new=2026-09-26_173557.md", h); print("baddiff", s)
s, b = get("/api/search?q=SECOND+paragraph", h); print("search", s, [x["task"] for x in json.loads(b)])
s, b = get("/api/search?q=x", h); print("shortsearch", s, json.loads(b))
s, b = get("/api/stale?" + A, h); print("nostale", s)
token = re.search(r'const TOKEN = "([^"]*)"', get("/", h)[1]).group(1)
print("token", len(token) > 10)
def post(path, body, hdrs):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.request("POST", path, body=json.dumps(body), headers=dict({"Host": h, "Content-Type": "application/json"}, **hdrs))
    r = c.getresponse(); r.read(); return r.status
body = {"slug": "home~app", "task": "alpha"}
print("notoken", post("/api/done", body, {}))
print("badorigin", post("/api/done", body, {"X-Handoffs-Token": token, "Origin": "http://evil.example"}))
print("done", post("/api/done", body, {"X-Handoffs-Token": token, "Origin": "http://" + h}))
print("done-again", post("/api/done", body, {"X-Handoffs-Token": token}))
print("restore", post("/api/restore", body, {"X-Handoffs-Token": token}))
open(sys.argv[2] + "/home~app/alpha/.DS_Store", "w").close()
print("done-extra", post("/api/done", body, {"X-Handoffs-Token": token}))
print("restore-extra", post("/api/restore", body, {"X-Handoffs-Token": token}))
print("traversal-post", post("/api/done", {"slug": "..", "task": "home~app"}, {"X-Handoffs-Token": token}))
tk = {"X-Handoffs-Token": token}
ren = lambda task, new, status="active": post("/api/rename", {"slug": "home~app", "status": status, "task": task, "new": new}, tk)
print("rename-notoken", post("/api/rename", {"slug": "home~app", "status": "active", "task": "alpha", "new": "beta"}, {}))
print("rename-bad", ren("alpha", "Bad Name"), ren("alpha", "_archive"), ren("alpha", "../x"))
print("rename-taken", ren("alpha", "old"), ren("alpha", "empty"))
print("rename-missing", ren("nope", "zeta"))
print("rename-nofield", post("/api/rename", {"slug": "home~app", "task": "alpha"}, tk))
print("rename", ren("alpha", "beta"))
crlf = sys.argv[2] + "/home~app/_archive/old/2026-09-01_070000.md"
open(crlf, "wb").write(b"---\r\ntask: old\r\ntitle: \xff raw\r\n---\r\nbody")
os.utime(crlf, (1000000000, 1000000000))
print("rename-arch", ren("old", "older", "archived"))
crlf = crlf.replace("/old/", "/older/")
deltip = lambda slug, i: post("/api/tip/delete", {"slug": slug, "id": i}, tk)
print("tip-notoken", post("/api/tip/delete", {"slug": "home~app", "id": "tip"}, {}))
print("tip-bad", deltip("home~app", "nope"), deltip("..", "tip"), deltip("home~app", "../tip"),
      deltip("home~app", "Bad Name"), deltip("_tips", "log"))
print("tip-nofield", post("/api/tip/delete", {"slug": "home~app"}, tk))
print("tip-delete", deltip("home~gone", "raw"), deltip("home~gone", "raw"), deltip("_global", "g1"))
print("rename-bytes", open(crlf, "rb").read() == b"---\r\ntask: older\r\ntitle: \xff raw\r\n---\r\nbody",
      int(os.stat(crlf).st_mtime) == 1000000000, [f for f in os.listdir(os.path.dirname(crlf)) if f.startswith(".")])
EOF
)
  kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null
  has "root 200 True" "GET / serves the page"
  has "api 200 True" "GET /api/tasks serves the data"
  has "localhost 200" "Host localhost is allowed"
  has "evil 403" "a foreign Host header is rejected (DNS rebinding)"
  has "file 404" "handoff files are not served"
  has "body 200 True True" "GET /api/handoff returns the body without frontmatter"
  has "archbody 200" "archived handoff body"
  has "archdir 404" "_archive is not a task"
  has "traversal 404" "names outside the listing are rejected"
  has "nomd 404" "a task dir without handoffs gives 404"
  has "history 200 True" "history lists versions, newest first"
  has "version 200" "an older version can be read"
  has "badfile 404" "a file outside the version list is rejected"
  has "diff 200 True" "diff between versions"
  has "baddiff 404" "diff of an unknown version is rejected"
  has "search 200 ['alpha']" "full-text search finds text beyond the summary"
  has "shortsearch 200 []" "one-letter search returns nothing"
  has "nostale 404" "the dashboard has no staleness API"
  has "token True" "the page carries a write token"
  has "notoken 403" "POST without the token is rejected"
  has "badorigin 403" "POST from a foreign Origin is rejected"
  has "done 200" "done archives the task"
  has "done-again 409" "done of an archived task fails"
  has "restore 200" "restore brings the task back"
  has "done-extra 200" "done works with a stray file in the task dir"
  has "restore-extra 200" "restore works with a stray file in the task dir"
  has "traversal-post 409" "POST names outside the listing are rejected"
  has "rename-notoken 403" "rename without the token is rejected"
  has "rename-bad 409 409 409" "rename to an invalid name is rejected"
  has "rename-taken 409 409" "rename to an existing active or archived task is rejected"
  has "rename-missing 409" "rename of an unknown task fails"
  has "rename-nofield 400" "rename without status/new is a bad request"
  has "rename 200" "rename renames an active task"
  has "rename-arch 200" "rename renames an archived task"
  has "rename-bytes True True []" "rename keeps line endings, raw bytes and mtime, leaves no temp file"
  has "tip-notoken 403" "tip delete without the token is rejected"
  has "tip-bad 409 409 409 409 409" "tip delete of an unknown tip, slug or id is rejected"
  has "tip-nofield 400" "tip delete without an id is a bad request"
  has "tip-delete 200 409 200" "tip delete, then it is gone; global tips too"
  assert "delete removes the tip file" [ ! -e "$D/_tips/home~gone/raw.md" ]
  assert "delete removes a global tip file" [ ! -e "$D/_tips/_global/g1.md" ]
  assert "delete keeps other tips" [ -f "$D/_tips/home~app/tip.md" ]
  assert "tip deletes are logged" [ "$(grep -c '"via": "dashboard"' "$D/_tips/log.jsonl")" -eq 2 ]
  assert "delete is logged" grep -q '"event": "deleted", "project": "home~gone", "id": "raw"' "$D/_tips/log.jsonl"
  assert "rename moves the task directory" [ -d "$D/home~app/beta" ]
  assert "rename leaves no old directory" [ ! -e "$D/home~app/alpha" ]
  assert "rename keeps the archived task archived" [ -d "$D/home~app/_archive/older" ]
  assert "rename updates the task field" grep -qx 'task: beta' "$D/home~app/beta/2026-09-26_173557.md"
  assert "done/restore round trip keeps both versions" [ "$(find "$D/home~app/beta" -name '*.md' | wc -l | tr -d ' ')" -eq 2 ]
  assert "restore removes the archive entry" [ ! -d "$D/home~app/_archive/alpha" ]

  # --read-only: no token, POST refused.
  HANDOFF_ROOT="$D" python3 "$DASH" --no-open --read-only --host 0.0.0.0 --port "$PORT" >"$TMP/dash.log" 2>&1 &
  DPID=$!
  OUT=$(python3 - "$PORT" <<'EOF'
import http.client, json, sys, time
port = int(sys.argv[1]); h = "127.0.0.1:%d" % port
def req(method, path, body=None, hdrs=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.request(method, path, body=body, headers=dict({"Host": h}, **(hdrs or {})))
    r = c.getresponse(); return r.status, r.read().decode()
for _ in range(50):
    try:
        req("GET", "/"); break
    except OSError:
        time.sleep(0.1)
print("ro-writable", json.loads(req("GET", "/api/tasks")[1])["writable"])
print("ro-token", 'const TOKEN = ""' in req("GET", "/")[1])
print("ro-post", req("POST", "/api/done", '{"slug":"home~app","task":"alpha"}', {"X-Handoffs-Token": ""})[0])
print("ro-ip", req("GET", "/api/tasks", hdrs={"Host": "192.168.1.5:%d" % port})[0])
print("ro-name", req("GET", "/api/tasks", hdrs={"Host": "evil.example:%d" % port})[0])
EOF
)
  kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null
  has "ro-writable False" "--read-only reports writable: false"
  has "ro-token True" "--read-only page has no token"
  has "ro-post 403" "--read-only refuses POST"
  has "ro-ip 200" "on 0.0.0.0 a LAN IP Host is allowed"
  has "ro-name 403" "on 0.0.0.0 a host name is still rejected"
  OUT=$(HANDOFF_PORT=abc python3 "$DASH" --json 2>&1); rc=$?
  assert "a bad HANDOFF_PORT exits with 2" [ "$rc" -eq 2 ]
  has "HANDOFF_PORT must be a port number" "a bad HANDOFF_PORT gives a clear error"
  OUT=$(cat "$TMP/dash.log")
  has "http://127.0.0.1:$PORT/" "prints the URL"

  # install.sh puts the command into HANDOFF_BIN_DIR and removes only its own file.
  INST="$(dirname "$DASH")/../install.sh"
  OUT=$(CLAUDE_CONFIG_DIR="$TMP/cfg" HANDOFF_BIN_DIR="$TMP/bin" "$INST" 2>&1)
  assert "install copies the dashboard" [ -x "$TMP/bin/handoffs" ]
  assert "install copies the skills" [ -f "$TMP/cfg/skills/handoff/handoff.sh" ]
  OUT=$(CLAUDE_CONFIG_DIR="$TMP/cfg" HANDOFF_BIN_DIR="$TMP/bin" "$INST" --uninstall 2>&1)
  assert "uninstall removes the dashboard" [ ! -e "$TMP/bin/handoffs" ]
  echo "#!/bin/sh" >"$TMP/bin/handoffs"
  OUT=$(CLAUDE_CONFIG_DIR="$TMP/cfg" HANDOFF_BIN_DIR="$TMP/bin" "$INST" --uninstall 2>&1)
  assert "uninstall keeps a foreign handoffs command" [ -f "$TMP/bin/handoffs" ]
  OUT=$(CLAUDE_CONFIG_DIR="$TMP/cfg" HANDOFF_BIN_DIR="$TMP/bin" "$INST" 2>&1)
  has "is not ours; skipped" "install warns about a foreign handoffs command"
  assert "install keeps a foreign handoffs command" grep -qx '#!/bin/sh' "$TMP/bin/handoffs"

  # Tips: skill, CLAUDE.md block and hook; foreign content is kept.
  IC="$TMP/icfg"; mkdir -p "$IC"
  printf '# mine\nkeep me\n' >"$IC/CLAUDE.md"
  printf '{"theme": "dark", "hooks": {"PostToolUseFailure": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "echo other"}]}]}}\n' >"$IC/settings.json"
  inst() { OUT=$(CLAUDE_CONFIG_DIR="$IC" HANDOFF_BIN_DIR="$TMP/ibin" "$INST" "$@" 2>&1 </dev/null); }
  # scount PY_EXPR: evaluates PY_EXPR over s (settings.json) and prints it.
  scount() { python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$IC/settings.json" "$1"; }
  OURS='sum("tips hook" in h["command"] for g in s["hooks"]["PostToolUseFailure"] for h in g["hooks"])'
  inst --tips --no-dashboard
  assert "install --tips copies the tips skill" [ -f "$IC/skills/tips/SKILL.md" ]
  assert "install --no-dashboard skips the dashboard" [ ! -e "$TMP/ibin/handoffs" ]
  assert "install --tips adds the CLAUDE.md block" grep -qF '<!-- claude-handoff:tips -->' "$IC/CLAUDE.md"
  assert "install --tips keeps CLAUDE.md content" grep -qx 'keep me' "$IC/CLAUDE.md"
  assert "install --tips adds the hook" [ "$(scount "$OURS")" = 1 ]
  assert "install --tips keeps other settings" [ "$(scount 's["theme"]')" = dark ]
  assert "the hook runs the installed script" [ "$(scount 's["hooks"]["PostToolUseFailure"][1]["hooks"][0]["command"]')" = "\"$IC/skills/handoff/handoff.sh\" \"\${CLAUDE_PROJECT_DIR:-.}\" tips hook" ]
  inst
  assert "reinstall without a terminal keeps tips" [ -f "$IC/skills/tips/SKILL.md" ]
  assert "reinstall without a terminal keeps no dashboard" [ ! -e "$TMP/ibin/handoffs" ]
  inst --tips --dashboard
  assert "reinstall keeps one CLAUDE.md block" [ "$(grep -cxF '<!-- claude-handoff:tips -->' "$IC/CLAUDE.md")" = 1 ]
  assert "reinstall keeps one hook" [ "$(scount "$OURS")" = 1 ]
  assert "install --dashboard adds the dashboard" [ -x "$TMP/ibin/handoffs" ]
  inst --no-tips --no-dashboard
  assert "--no-tips removes the tips skill" [ ! -e "$IC/skills/tips" ]
  assert "--no-tips removes the CLAUDE.md block" [ "$(cat "$IC/CLAUDE.md")" = "$(printf '# mine\nkeep me')" ]
  assert "--no-tips removes only our hook" [ "$(scount "$OURS"), $(scount 'len(s["hooks"]["PostToolUseFailure"])')" = "0, 1" ]
  assert "--no-dashboard removes the dashboard" [ ! -e "$TMP/ibin/handoffs" ]
  inst --tips --dashboard
  inst --uninstall
  assert "uninstall removes all skills" [ -z "$(ls -A "$IC/skills")" ]
  assert "uninstall removes the dashboard" [ ! -e "$TMP/ibin/handoffs" ]
  assert "uninstall removes the CLAUDE.md block" [ "$(cat "$IC/CLAUDE.md")" = "$(printf '# mine\nkeep me')" ]
  assert "uninstall removes our hook" [ "$(scount "$OURS")" = 0 ]
  printf '{"only": "ours"}\n' >"$IC/settings.json"
  inst --tips; inst --uninstall
  assert "uninstall drops an emptied hooks key" [ "$(scount 'sorted(s)')" = "['only']" ]
  printf '{broken\n' >"$IC/settings.json"
  inst --tips
  has "is not valid JSON" "install reports broken settings.json"
  assert "install leaves broken settings.json alone" [ "$(cat "$IC/settings.json")" = "{broken" ]
  rm -rf "$IC/CLAUDE.md" "$IC/settings.json"
  inst --tips
  assert "install creates CLAUDE.md" grep -qF '<!-- claude-handoff:tips -->' "$IC/CLAUDE.md"
  assert "install creates settings.json" [ "$(scount "$OURS")" = 1 ]
  inst --bogus
  has "usage:" "install rejects an unknown flag"

  # A foreign tips skill is never replaced or removed.
  mkdir -p "$IC/skills/tips"; printf 'mine\n' >"$IC/skills/tips/SKILL.md"
  inst --no-tips; inst --tips
  has "is not ours; tips skipped" "install warns about a foreign tips skill"
  assert "install keeps a foreign tips skill" [ "$(cat "$IC/skills/tips/SKILL.md")" = mine ]
  assert "install adds no block for a foreign tips skill" [ "$(grep -c 'claude-handoff:tips' "$IC/CLAUDE.md")" = 0 ]
  inst --uninstall
  assert "uninstall keeps a foreign tips skill" [ "$(cat "$IC/skills/tips/SKILL.md")" = mine ]
  rm -rf "$IC/skills/tips"
  # A block without its END line is left alone.
  printf '# mine\n<!-- claude-handoff:tips -->\nedited\n## later\nkeep\n' >"$IC/CLAUDE.md"
  cp "$IC/CLAUDE.md" "$TMP/md.orig"
  inst --no-tips
  has "without <!-- /claude-handoff:tips -->" "install warns about an unterminated block"
  assert "--no-tips leaves an unterminated block alone" cmp -s "$IC/CLAUDE.md" "$TMP/md.orig"
  inst --tips
  assert "--tips adds no block next to an unterminated one" cmp -s "$IC/CLAUDE.md" "$TMP/md.orig"
  # CRLF lines and duplicate blocks are removed.
  printf '# mine\r\n<!-- claude-handoff:tips -->\r\nold\r\n<!-- /claude-handoff:tips -->\r\nkeep\r\n <!-- claude-handoff:tips -->\nold\n<!-- /claude-handoff:tips --> \n' >"$IC/CLAUDE.md"
  inst --no-tips
  assert "--no-tips removes CRLF and duplicate blocks" [ "$(cat "$IC/CLAUDE.md")" = "$(printf '# mine\r\nkeep\r')" ]
  inst --tips
  assert "reinstall leaves one block" [ "$(grep -cxF '<!-- claude-handoff:tips -->' "$IC/CLAUDE.md")" = 1 ]
  # settings.json is not rewritten when the hook does not change.
  printf '{"theme": "dark"}\n' >"$IC/settings.json"
  inst --no-tips
  assert "--no-tips without a hook keeps settings.json as is" [ "$(cat "$IC/settings.json")" = '{"theme": "dark"}' ]
  lacks "the tips hook" "--no-tips without a hook reports nothing"
  inst --tips; cp "$IC/settings.json" "$TMP/s.orig"; inst --tips
  lacks "the tips hook" "reinstall with the same hook reports nothing"
  assert "reinstall with the same hook keeps settings.json" cmp -s "$IC/settings.json" "$TMP/s.orig"
  # Choices are kept in install.conf; an install without it gets the dashboard.
  inst --no-dashboard --tips; inst
  assert "install.conf keeps a declined dashboard" [ ! -e "$TMP/ibin/handoffs" ]
  assert "install.conf keeps tips" [ -f "$IC/skills/tips/SKILL.md" ]
  rm -f "$IC/skills/handoff/install.conf"; inst
  assert "an install without install.conf gets the dashboard" [ -x "$TMP/ibin/handoffs" ]
fi

echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
