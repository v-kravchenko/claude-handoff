# shellcheck shell=bash
# Tips: short unverified hints saved by /handoff and searched on demand.
# Sourced by handoff.sh (uses ROOT, PROJECT, key, in_git, repo_root, valid_task).
#   $HANDOFF_ROOT/_tips/<project-slug>/<id>.md   project tips
#   $HANDOFF_ROOT/_tips/_global/<id>.md          global tips (this machine)
#   $HANDOFF_ROOT/_tips/log.jsonl                search/show/verify events
# Tips live outside project dirs: every subdir of a project dir is a task.
# The file name is the tip id. Search sees the current project and global only.

TIPS_ROOT="$ROOT/_tips"
GLOBAL=_global
TIPS_MAX=5
SKILLS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The project slug costs a few git calls; cmd_tips computes it once.
tips_init() { [[ -n ${TIPS_SLUG:-} ]] || TIPS_SLUG=$(basename "$(key)"); }
tips_pdir() { tips_init; echo "$TIPS_ROOT/$TIPS_SLUG"; }
tips_gdir() { echo "$TIPS_ROOT/$GLOBAL"; }
# On when our tips skill (with its marker line) sits next to this skill.
tips_on() { grep -q 'part of claude-handoff' "$SKILLS_DIR/tips/SKILL.md" 2>/dev/null; }

# termux | linux | darwin | ...: a tip with `env:` set only matches there.
tips_env() {
  if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == *com.termux* ]]; then echo termux
  else uname -s | tr '[:upper:]' '[:lower:]'; fi
}

# Tip file for ID (project first, then global), or nothing.
tip_file() {
  local d
  valid_task "$1" || return 1
  for d in "$(tips_pdir)" "$(tips_gdir)"; do
    [[ -f $d/$1.md ]] && { echo "$d/$1.md"; return; }
  done
  return 1
}

tip_level() { [[ $1 == "$(tips_gdir)"/* ]] && echo global || echo project; }

tip_files() {
  local f
  for f in "$(tips_pdir)"/*.md "$(tips_gdir)"/*.md; do [[ -f $f ]] && echo "$f"; done
}

json_str() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/ }
  printf '"%s"' "$s"
}

# Masks likely secrets (key=value after a secret-ish name, long tokens).
tips_redact() {
  sed -E 's/([Aa]uthorization|[Bb]earer|[Tt]oken|[Pp]assw(or)?d|[Ss]ecret|[Aa]pi[_-]?[Kk]ey)([^[:alnum:]]{1,3})[^[:space:]"'"'"']+/\1\3***/g; s/[A-Za-z0-9_+=-]{24,}/***/g'
}

# tips_log EVENT [ID] [QUERY] [HITS]; QUERY is redacted.
tips_log() {
  tips_init
  mkdir -p "$TIPS_ROOT" 2>/dev/null || return
  printf '{"ts":"%s","event":"%s","project":%s,"id":%s,"query":%s,"hits":%s}\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$(json_str "$TIPS_SLUG")" \
    "$(json_str "${2:-}")" "$(json_str "$(tips_redact <<<"${3:-}")")" "${4:-0}" >>"$TIPS_ROOT/log.jsonl" 2>/dev/null
}

# set_field FILE KEY VALUE: replaces KEY in the frontmatter or adds it.
# VALUE goes through ENVIRON: awk -v would expand backslash escapes.
set_field() {
  local tmp="$1.tmp.$$"
  TIPS_V=$3 awk -v k="$2" '
    BEGIN { v = ENVIRON["TIPS_V"]; gsub(/[\r\n]+/, " ", v) }
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { if (!done) print k ": " v; fm = 0; print; next }
    fm && index($0, k ":") == 1 { print k ": " v; done = 1; next }
    { print }' "$1" >"$tmp" && mv -- "$tmp" "$1"
}

# Scores active tips; prints "score<TAB>level<TAB>id<TAB>title", best first.
# Query mode: words of QUERY vs keywords (3), title/when (2), body (1);
# words longer than 6 chars are cut to 5 (cheap stemming).
# Error mode: keyword items (4+ chars) found in the error text; a tip needs
# 2 items or one of 10+ chars; a quoted item may contain commas.
# Text goes through ENVIRON: awk -v would expand backslash escapes.
tips_score() {
  local mode=$1 f files=()
  while IFS= read -r f; do files+=("$f"); done < <(tip_files)
  ((${#files[@]})) || return
  TIPS_Q=$2 TIPS_GDIR="$(tips_gdir)/" awk -v mode="$mode" -v env="$(tips_env)" '
    BEGIN { q = ENVIRON["TIPS_Q"]; gdir = ENVIRON["TIPS_GDIR"] }
    # Splits keywords on commas outside double quotes; drops the quotes.
    function splitkw(s, a,   n, i, c, cur, inq) {
      n = 0; cur = ""; inq = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\"") inq = !inq
        else if (c == "," && !inq) { a[++n] = cur; cur = "" }
        else cur = cur c
      }
      a[++n] = cur
      return n
    }
    function flush(   id, level, n, i, t, s, e, it, items, w, kw, ti, wh, bo, score, hits, strong, ok) {
      if (fname == "") return
      id = fname; sub(/.*\//, "", id); sub(/\.md$/, "", id)
      level = index(fname, gdir) == 1 ? "global" : "project"
      if (F["status"] != "active") return
      if (F["env"] != "") {
        ok = 0; n = split(tolower(F["env"]), items, /[ ,]+/)
        for (i = 1; i <= n; i++) if (items[i] == env) ok = 1
        if (!ok) return
      }
      if (mode == "error") {
        e = tolower(q); n = splitkw(F["keywords"], items); hits = 0; strong = 0
        for (i = 1; i <= n; i++) {
          it = tolower(items[i]); gsub(/^ +| +$/, "", it)
          if (length(it) >= 4 && index(e, it)) { hits++; if (length(it) >= 10) strong = 1 }
        }
        if (!(strong || hits >= 2)) return
        score = hits
      } else {
        n = split(tolower(q), w, /[ \t,;:()"`'\''|]+/); score = 0; hits = 0
        kw = tolower(F["keywords"]); ti = tolower(F["title"]); wh = tolower(F["when"]); bo = tolower(body)
        for (i = 1; i <= n; i++) {
          t = w[i]
          if (length(t) < 3 || t ~ /^(the|and|for|with|not|why|how|what|when|does|что|що|як|при|для|або|чому)$/) continue
          if (length(t) > 6) t = substr(t, 1, 5)
          s = index(kw, t) ? 3 : index(ti, t) ? 2 : index(wh, t) ? 2 : index(bo, t) ? 1 : 0
          if (s) { score += s; hits++ }
        }
        if (!hits) return
      }
      printf "%d\t%s\t%s\t%s\n", score, level, id, F["title"]
    }
    FNR == 1 { flush(); fname = FILENAME; fm = 0; body = ""; split("", F) }
    FNR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*: */, "", v); F[k] = v; next }
    { body = body " " $0 }
    END { flush() }' "${files[@]}" |
    sort -t "$(printf '\t')" -k1,1nr -k3,3 |
    awk -F '\t' -v mode="$mode" 'NR == 1 { top = $1 } mode == "error" || ($1 >= 3 && $1 * 2 >= top)' |
    head -n "$TIPS_MAX"
}

# search [--error] WORDS...
tips_search() {
  local mode=query out n
  [[ ${1:-} == --error ]] && { mode=error; shift; }
  local q="$*"
  [[ -n ${q// /} ]] || { echo "usage: tips search [--error] WORDS"; return; }
  out=$(tips_score "$mode" "$q")
  n=$(grep -c . <<<"$out")
  tips_log search "" "$q" "$n"
  if [[ -z $out ]]; then echo "(no tips match: $q)"; return; fi
  echo "## tips (unverified: run a tip's Verify step before relying on it)"
  awk -F '\t' '{ printf "%s | %s | %s\n", $3, $2, $4 }' <<<"$out"
}

tips_list() {
  local f n=0
  while read -r f; do
    [[ -n $f ]] || continue
    n=$((n + 1))
    printf '%s | %s | %s | %s\n' "$(basename "$f" .md)" "$(tip_level "$f")" \
      "$(field status "$f")" "$(field title "$f")"
  done < <(tip_files)
  ((n)) || echo "(no tips)"
}

# Warnings for `cites:` entries of the form path[:line]@commit.
tip_stale() (
  local cites c path commit n
  cites=$(field cites "$1")
  [[ -n $cites ]] || exit
  cd "$PROJECT" 2>/dev/null || exit
  # Cites are relative to this checkout (a worktree, not the main repo).
  if in_git; then cd "$(git rev-parse --show-toplevel)" || exit; fi
  local IFS=,
  for c in $cites; do
    c=${c#"${c%%[![:space:]]*}"}; c=${c%"${c##*[![:space:]]}"}; c=${c//\`/}
    [[ $c == *@* ]] || continue
    path=${c%@*}; commit=${c##*@}; path=${path%%:*}
    # shellcheck disable=SC2088 # a literal "~/" prefix written in the tip
    [[ $path == "~/"* ]] && path=$HOME/${path#"~/"}
    if [[ ! -e $path ]]; then echo "WARNING: cited $path no longer exists"; continue; fi
    if ! in_git || ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then continue; fi
    if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
      echo "WARNING: cited commit $commit not found in $(pwd -P)"; continue
    fi
    n=$(git rev-list --count "$commit..HEAD" -- "$path" 2>/dev/null)
    [[ ${n:-0} -gt 0 ]] && echo "WARNING: $path changed in $n commit(s) since $commit"
    git diff --quiet HEAD -- "$path" 2>/dev/null || echo "WARNING: $path has uncommitted changes"
  done
)

tips_show() {
  local f
  f=$(tip_file "${1:-}") || { echo "NO TIP: ${1:-}"; return; }
  tips_log show "$1"
  echo "file: $f"
  echo "level: $(tip_level "$f")"
  tip_stale "$f"
  echo
  cat "$f"
}

# new ID [project|global]: prints the target file; refuses an existing id.
tips_new() {
  local id=${1:-} level=${2:-project} dir f commit=none
  valid_task "$id" || { echo "INVALID ID: '$id' (use lowercase a-z0-9._-)"; return; }
  if f=$(tip_file "$id"); then echo "EXISTS: $id ($f); update it or pick another id"; return; fi
  case $level in
    project) dir=$(tips_pdir) ;;
    global) dir=$(tips_gdir) ;;
    *) echo "INVALID LEVEL: '$level' (project|global)"; return ;;
  esac
  mkdir -p "$dir"
  (cd "$PROJECT" && in_git) && commit=$(cd "$PROJECT" && git rev-parse -q --short HEAD 2>/dev/null || echo none)
  echo "file: $dir/$id.md"
  echo "level: $level"
  echo "env: $(tips_env)"
  echo "source: project=$(basename "$(key)") commit=$commit date=$(date +%Y-%m-%d)"
}

tips_verified() {
  local f
  f=$(tip_file "${1:-}") || { echo "NO TIP: ${1:-}"; return; }
  set_field "$f" status active
  set_field "$f" last_verified "$(date +%Y-%m-%d)"
  tips_log verified "$1"
  echo "verified: $1"
}

tips_refuted() {
  local f id=${1:-}
  f=$(tip_file "$id") || { echo "NO TIP: $id"; return; }
  shift
  set_field "$f" status refuted
  set_field "$f" refuted "$(date +%Y-%m-%d) ${*:-no reason given}"
  tips_log refuted "$id"
  echo "refuted: $id"
}

tips_supersede() {
  local old new
  old=$(tip_file "${1:-}") || { echo "NO TIP: ${1:-}"; return; }
  new=$(tip_file "${2:-}") || { echo "NO TIP: ${2:-}"; return; }
  [[ $old != "$new" ]] || { echo "SAME TIP: $1"; return; }
  set_field "$old" status superseded
  set_field "$old" superseded_by "$2"
  tips_log superseded "$1"
  echo "superseded: $1 -> $2"
}

tips_move() {
  local f id=${1:-} dir
  f=$(tip_file "$id") || { echo "NO TIP: $id"; return; }
  case ${2:-} in
    global) dir=$(tips_gdir) ;;
    project) dir=$(tips_pdir) ;;
    *) echo "usage: tips move ID global|project"; return ;;
  esac
  [[ $f == "$dir/$id.md" ]] && { echo "already $2: $id"; return; }
  [[ -e $dir/$id.md ]] && { echo "EXISTS: $dir/$id.md"; return; }
  mkdir -p "$dir" && mv -- "$f" "$dir/$id.md" && echo "moved: $id -> $2"
}

tips_status() {
  if tips_on; then echo "tips: on"; else echo "tips: off"; fi
  echo "project tips: $(tips_pdir)"
  echo "global tips: $(tips_gdir)"
  echo "env: $(tips_env)"
}

# PostToolUseFailure hook: reads the hook JSON on stdin, prints
# additionalContext with matching tip titles, or nothing.
tips_hook() {
  local in err cmd out n text
  in=$(head -c 65536 | tr -d '\n')
  tips_on && [[ -d $TIPS_ROOT ]] || return
  [[ $in =~ \"is_interrupt\":[[:space:]]*true ]] && return
  err=$(sed -nE 's/.*"error":[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' <<<"$in" | head -c 4000)
  cmd=$(sed -nE 's/.*"command":[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' <<<"$in" | head -c 2000)
  [[ -n $err ]] || return
  tips_init
  out=$(tips_score error "$(printf '%s %s' "$cmd" "$err" | sed 's/\\[nt]/ /g; s/\\"/"/g; s/\\\\/\\/g')")
  [[ -n $out ]] || return
  n=$(grep -c . <<<"$out")
  # Error text is not logged: it may hold secrets. The matched ids are.
  tips_log hook "$(cut -f3 <<<"$out" | paste -sd, -)" "" "$n"
  text="claude-handoff: $n unverified tip(s) may match this error:"$'\n'
  text+=$(awk -F '\t' '{ printf "- %s (%s): %s\n", $3, $2, $4 }' <<<"$out")
  text+=$'\n'"Before acting on one, run /tips show <id>, then its Verify step, then /tips verified <id> or /tips refuted <id> <why>."
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":%s}}\n' "$(json_str "$text")"
}

TIPS_USAGE="usage: handoff.sh PROJECT_DIR tips status|list|search [--error] WORDS|show ID|new ID [project|global]|verified ID|refuted ID REASON|supersede OLD NEW|move ID global|project|hook"

cmd_tips() {
  local sub=${1:-}
  shift 2>/dev/null
  [[ $sub == hook ]] || tips_init
  case $sub in
    status) tips_status ;;
    list) tips_list ;;
    search) tips_search "$@" ;;
    show) tips_show "${1:-}" ;;
    new) tips_new "${1:-}" "${2:-project}" ;;
    verified) tips_verified "${1:-}" ;;
    refuted) tips_refuted "$@" ;;
    supersede) tips_supersede "${1:-}" "${2:-}" ;;
    move) tips_move "${1:-}" "${2:-}" ;;
    hook) tips_hook ;;
    *) echo "$TIPS_USAGE" ;;
  esac
}
