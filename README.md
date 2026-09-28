# claude-handoff

[![CI](https://github.com/v-kravchenko/claude-handoff/actions/workflows/ci.yml/badge.svg)](https://github.com/v-kravchenko/claude-handoff/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Two [Claude Code](https://code.claude.com) skills that carry work across sessions:

- **`/handoff`** saves the essence of the current session (goal, state,
  decisions, gotchas, next steps) as a Markdown file.
- **`/pickup`** loads it in a fresh session, checks what changed since, and
  proposes the first step.

Use it before `/clear`, when the context window is filling up, when switching
machines, or to park a task and come back to it days later.

## Features

- **Several tasks per directory.** Each handoff belongs to a named task
  (`@api-refactor`, `@flaky-tests`), so one project, or a non-git directory
  like `~`, can hold independent streams of work.
- **Written for the next agent, not as a log.** A fixed template records
  intent, decisions, dead ends and concrete next steps, not a play-by-play.
- **Staleness report.** `/pickup` shows the handoff's age, the commits made
  since, a rebased or missing commit, uncommitted changes and a work
  directory that no longer exists.
- **Git-aware.** Git worktrees of one repository share handoffs. Branch and
  commit are recorded, and nested repositories inside a project work.
- **Chained history.** Each handoff is written from the current state. It
  carries over from the task's last handoff only the open decisions and
  gotchas not recorded elsewhere. The last 10 per task are kept.
- **Tips (optional).** `/handoff` also saves 0–3 short, unverified hints
  (gotchas, dead ends, fixes) per project or for the whole machine. Nothing
  is loaded at session start: the agent searches them with `/tips` when it
  hits an error, and hooks point to matching tips when a request mentions
  their keywords or a Bash command fails.
- **Dashboard.** `handoffs` shows every task of every project in the
  browser, with a one-click resume command.
- **No secrets.** The skill is told never to write tokens or credentials,
  only where they live.
- **Small and dependency-free.** One Bash script: bash 3.2+ and git. Works
  on Linux, macOS and Termux (Android). The optional dashboard needs only
  python3.

## Installation

### Install script (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/v-kravchenko/claude-handoff/main/install.sh | bash
```

This gives you the short commands `/handoff` and `/pickup` and the optional
dashboard and tips. The script fetches the repository into a temporary
directory (with git, or as a tarball without it), copies the skills to
`~/.claude/skills` (respects `CLAUDE_CONFIG_DIR`) and deletes the temporary
copy. It asks two questions (the defaults are your previous answers):

- **Dashboard**: installs the `handoffs` command (see below).
- **Tips**: installs the `/tips` skill, adds a marked block to
  `~/.claude/CLAUDE.md` (`<!-- claude-handoff:tips -->`) that tells the agent
  to search tips before debugging and before answering how-to questions, and
  adds a `UserPromptSubmit` hook and a `PostToolUseFailure` hook for Bash to
  `~/.claude/settings.json` (merged with python3; other settings and hooks
  are kept; `settings.json` is rewritten only when the hooks change).
  An existing `tips` skill that is not ours is left alone, and so is a
  `CLAUDE.md` block whose end marker was removed (fix it by hand).

Answering no removes a part that is installed. Flags skip the questions:
`--dashboard`, `--no-dashboard`, `--tips`, `--no-tips`. Without a terminal
and without flags, the previous choices are kept (saved in
`skills/handoff/install.conf`; a fresh install gets the dashboard, not tips).

| Task | Command |
| --- | --- |
| Install or update | `curl -fsSL https://raw.githubusercontent.com/v-kravchenko/claude-handoff/main/install.sh \| bash` |
| With flags | `... \| bash -s -- --tips --no-dashboard` |
| A release | `... \| HANDOFF_REF=v1.2.2 bash` (a branch or tag) |
| Uninstall | `... \| bash -s -- --uninstall` |

Uninstall removes everything the script installed (skills, dashboard, the
`CLAUDE.md` block and the hooks); saved handoffs and tips are kept. To read
the script before running it, download it first:
`curl -fsSLO https://raw.githubusercontent.com/v-kravchenko/claude-handoff/main/install.sh`,
then `bash install.sh`.

The dashboard command goes to `~/.local/bin` (`$PREFIX/bin` on Termux); set
`HANDOFF_BIN_DIR` to choose another directory.

### From a clone

For development, or to keep a checkout: `git clone
https://github.com/v-kravchenko/claude-handoff.git && cd claude-handoff &&
./install.sh` (same questions and flags). Update with `git pull &&
./install.sh`.

### As a plugin

In Claude Code:

```text
/plugin marketplace add v-kravchenko/claude-handoff
/plugin install handoff@claude-handoff
```

Plugin skills are namespaced, so the commands are **`/handoff:handoff`** and
**`/handoff:pickup`**. Update with `/plugin marketplace update claude-handoff`.
The plugin has no [tips](#tips) and no dashboard command (run `bin/handoffs`
from a clone): tips need the `/tips` skill, a block in `CLAUDE.md` and
hooks, so they come only with the install script.

Start a new Claude Code session after installing.

## Usage

The examples use the short names. With the plugin, use `/handoff:handoff`
and `/handoff:pickup` instead.

| Command | What it does |
| --- | --- |
| `/handoff` | Save a handoff. The task is the one you resumed with `/pickup`, an existing task that matches this work, or a new slug derived from the title. |
| `/handoff @task` | Save under an explicit task name (lowercase `a-z0-9._-`). |
| `/handoff @task focus on the migration` | Anything after the task is a focus hint for the summary. |
| `/handoff @task done` | Archive a finished task. |
| `/pickup` | Resume the only task, or list the tasks to choose from. |
| `/pickup @task` | Resume a specific task. |
| `/pickup path/to/file.md` | Resume from a specific handoff file (the path must contain `/` or end in `.md`). |
| `/tips words or error text` | Search tips of this project and global tips (the agent also does this on its own). |
| `/tips show ID` | Show a tip, with a warning if its cited files changed since. |
| `/tips verified ID`, `/tips refuted ID why` | Record whether a tip held; refuted tips are no longer found. |

A typical loop:

```text
> /handoff @auth-rewrite
@auth-rewrite  ~/.claude/handoffs/home~code~app/auth-rewrite/2026-09-26_173557.md
Session middleware migrated; token refresh still failing in tests/auth.spec.ts.

> /clear
> /pickup @auth-rewrite
@auth-rewrite: replace session cookies with short-lived JWTs.
- Done: middleware, login route
- In progress: refresh flow (tests/auth.spec.ts:88 fails)
- Staleness: 2 commits since handoff, 1 dirty file
Proposed first step: fix the clock skew in refreshToken(). Proceed?
```

`/pickup` never starts working on its own; it waits for you to confirm.

`/handoff` and `/pickup` set `disable-model-invocation: true`, so they run
only when you type them. `/tips` can also be invoked by the agent.

## Tips

Tips come with the install script's tips option (`--tips`), not with the plugin. Tips are short hints that `/handoff` saves for future sessions: a dead end,
a surprise, the fix for an error, a correction you made. They are
**unverified**: each has a `Verify` step, and the agent is told to run it
before relying on a tip and to mark the tip `verified` or `refuted`.

- **Writing.** `/handoff` picks 0–3 tips (zero is normal), skips generic
  advice and anything already in the code, git or `CLAUDE.md`, searches for
  duplicates and then adds, updates or supersedes a tip. Its reply ends with
  `tips: +added ~updated xsuperseded`.
- **Two levels.** A tip that holds in any project on this machine (a broken
  system tool, a Termux quirk) is *global*; one that depends on the
  project's files is a *project* tip. When unsure, the agent picks
  project. `env:` limits a tip to an environment (`termux`, `darwin`, ...).
- **Searching.** Search sees the current project and global tips, never
  other projects. It scores words against `keywords`, `title`, `when` and
  the body (case-insensitive, with simple word-form matching); refuted and
  superseded tips are never returned.
- **Triggers.** Nothing is loaded at session start. The agent searches with
  `/tips` (its description and the `CLAUDE.md` block say when). Two hooks add
  the titles of matching tips to the context (nothing when none match): one
  on each request whose words start with a tip's keyword (one item of 5+
  characters or two shorter ones; each tip once per session), one when a
  Bash command fails. A command whose exit code is masked, as in
  `cmd; echo $?`, does not count as failed.

A tip file:

```markdown
---
title: E_ZQ_SHARD_SKEW from build.sh means a stale .cache/zq-index
when: ./build.sh fails with code 71
keywords: E_ZQ_SHARD_SKEW, "shard map out of sync", zq-index, build.sh
cites: build.sh@a1b2c3d
origin: failure
source: project=home~code~app commit=a1b2c3d date=2026-09-27 task=build session=...
status: active
---
Tip: delete .cache/zq-index and rerun ./build.sh.
Why: the index is rebuilt on the next build; a stale one skews the shard map.
Verify: `test -e .cache/zq-index && echo stale-index-present`
```

## Dashboard

`handoffs` is a terminal command that shows every task of every project in
the browser:

```text
$ handoffs
handoffs: http://127.0.0.1:8765/  (root: ~/.claude/handoffs; Ctrl+C to stop)
```

Each project (the directory the handoffs belong to) is a tile in a grid,
with a coloured accent and initials; it lists its active tasks and folds
its archived ones under *Archived (N)*. Each task shows a freshness dot (today, last 2 weeks, older), the
title, the task, its age, and chips only when something needs attention
(archived, idle for 14+ days, a missing project directory). A tap on a
task or tip opens it in a side panel; `Esc` or a tap outside closes it.
`/` focuses the search, `Esc` clears it.

- **Copy** (on the row and in the panel) copies the resume command, `cd ~/'project' && claude "/pickup @task"`.
- The side panel shows the branch and commit at
  handoff time and renders the whole latest handoff. The *History* tab
  lists every saved version, opens any of them and shows the diff against
  the previous one. The staleness report is left to `/pickup`.
- **Done** (in the panel) archives an active task and **Restore** brings an
  archived one back, like `/handoff @task done` and the *Restore* option of
  `/pickup`.
- **Rename** (in the panel) gives a task a new name (lowercase
  `a-z0-9._-`, not taken by another active or archived task of the
  project) and updates the `task:` field of its handoffs.

Tips (see [Tips](#tips)) sit on the *Tips* tab of their project's tile;
global tips are cards under *Global tips* at the bottom. Refuted and superseded
tips are dimmed. A tip's panel shows its text, `when` and keywords, and
**Delete** removes a useless or outdated tip. Verifying, refuting, moving
and editing tips is left to the agent via `/tips`.

The search box filters by task, title and goal at once, and also searches
the full text of the latest handoffs and of tips. The page reads the handoff files on
every request and refreshes itself every 30 seconds, so it is never out of
date.

| Option | Meaning |
| --- | --- |
| `--port N` | Port to listen on (default `$HANDOFF_PORT` or `8765`); if it is busy, the next nine are tried. `0` picks any free port. |
| `--host ADDR` | Address to listen on (default `127.0.0.1`). |
| `--no-open` | Only print the URL. |
| `--read-only` | Hide the *Done*, *Restore*, *Rename* and *Delete* buttons and refuse changes. |
| `--background` | Start detached, print the URL and return; a second call reuses the running one. |
| `--stop` | Stop the dashboard started with `--background`. |
| `--json` | Print the task data as JSON and exit. |

To keep the dashboard always running, install it as a user service
(systemd `--user` on Linux, a launchd agent on macOS):

```
handoffs service install [--port N] [--host ADDR] [--read-only]
handoffs service status | restart | uninstall
```

The service starts at login and restarts on failure; add `--dry-run` to see
the unit/plist without changing anything. `HANDOFF_ROOT`, `CLAUDE_CONFIG_DIR`
and `HANDOFF_PORT` are copied into it. `install.sh` restarts the service after
an update and removes it on uninstall. On Linux, `loginctl enable-linger`
keeps it running while you are logged out. Termux has no service manager: use
`handoffs --background`.

The browser opens with `open` (macOS), `xdg-open` (Linux desktop),
`wslview` or `explorer.exe` (WSL), the default browser (Windows) or
`termux-open-url` (Termux). Over SSH or without a display, the command only
prints the URL. On Termux, keep Termux in the foreground for the browser to
open, or tap the printed URL.

## How it works

Handoffs are plain Markdown files stored outside your repositories:

```text
~/.claude/handoffs/
└── <project-slug>/                 # home~code~app for ~/code/app, root~srv~app for /srv/app
    ├── <task>/
    │   ├── 2026-09-25_101500.md
    │   └── 2026-09-26_173557.md    # latest one wins
    └── _archive/
        └── <task>/...              # tasks finished with `/handoff @task done`
~/.claude/handoffs/_tips/
├── _global/<id>.md                 # global tips (this machine)
├── <project-slug>/<id>.md          # project tips
└── log.jsonl                       # search, show, verified and refuted events (secrets masked)
```

- The **project** is Claude Code's project directory (`$CLAUDE_PROJECT_DIR`).
  Inside git it is the main repository root, so all worktrees map to the
  same place.
- Each file starts with YAML frontmatter (`project`, `dir`, `repo`, `branch`,
  `commit`, `created`, `task`, `session`, `title`), followed by
  the sections *Goal, State, Decisions, Key context, Gotchas, User
  preferences, Next steps, Verify*.
- The model writes the summary; `skills/handoff/handoff.sh` handles storage,
  task listing, pruning, archiving and the staleness report. The script
  always exits 0, because a failing `!` command would abort the skill.

`/pickup` with no task, or with an unknown or archived one, lets you pick a
task from a menu of the newest tasks (a single task loads right away). For
an archived task the menu offers *Restore*, which moves the handoffs back
(merging them into a new task of the same name, if you started one) and
loads it. `handoff.sh PROJECT_DIR restore TASK` does the same by hand.
`/handoff @task` also warns when it starts a new task whose name is in the
archive.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `HANDOFF_ROOT` | `${CLAUDE_CONFIG_DIR:-~/.claude}/handoffs` | Where handoffs are stored. |
| `HANDOFF_KEEP` | `10` | Handoffs kept per task (a positive integer; anything else means 10). Older ones are deleted when you save. |
| `HANDOFF_PORT` | `8765` | Default port of the `handoffs` dashboard. |
| `HANDOFF_BIN_DIR` | `~/.local/bin` (`$PREFIX/bin` on Termux) | Where `install.sh` puts `handoffs`. |
| `HANDOFF_REF` | `main` | Branch or tag the piped install script fetches. |
| `HANDOFF_REPO` | `https://github.com/v-kravchenko/claude-handoff` | Repository the piped install script fetches (a fork or a local `file://` path). |

Set them in your shell profile or in the `env` block of
`~/.claude/settings.json`.

## Requirements

- Claude Code with skills support
- bash 3.2 or newer (macOS system bash works)
- git 2.31 or newer (only needed for git metadata; plain directories work
  without it)
- python 3.8 or newer, only for the `handoffs` dashboard (standard library
  only; on Termux: `pkg install python`)

## Privacy and security

- Handoffs stay on your machine under `HANDOFF_ROOT` and are never committed
  to your repositories.
- The skill is told not to write secrets. Still, review a handoff before
  sharing it, because it summarizes your conversation.
- The skill may only run its own script (`allowed-tools` is scoped to
  `handoff.sh`) and write the handoff file.
- Tips are hints written by the agent, possibly from content it read, so they
  can be wrong or planted. The agent is told to verify a tip before relying
  on it and never to follow one that asks for something risky; a tip taken
  from web pages, issues or foreign code is marked `origin: web` and stays a
  project tip.
- The tips hooks only read the request or the failed command and its error,
  search local tip files and print matching titles; they send nothing
  anywhere and log only the matched tip ids, not the prompt or error text.
- The dashboard listens on `127.0.0.1` only and reads nothing but handoff
  files of listed tasks and tip files. It rejects requests whose `Host` header is not
  local, which blocks DNS-rebinding attacks from web pages. Its only changes
  are *Done*, *Restore*, *Rename* and deleting a tip: they need a random token that is embedded in the
  page at startup and sent in a custom header, so other web pages cannot
  trigger them. `--read-only` turns them off. Other programs on the same
  machine (on Android, other apps) are not web pages: while the dashboard
  runs they can read it and, unless it is `--read-only`, also use its
  buttons.

## Development

```bash
tests/test.sh                                            # end-to-end tests in a temp dir
shellcheck -x skills/handoff/handoff.sh skills/handoff/tips.sh install.sh tests/test.sh
HANDOFF_ROOT=$(mktemp -d) bin/handoffs --no-open         # dashboard on an empty root
```

CI runs shellcheck and the tests on Ubuntu and on macOS (bash 3.2). The
dashboard tests are skipped when python3 is missing.

To try the script by hand without touching your real handoffs:

```bash
HANDOFF_ROOT=$(mktemp -d) skills/handoff/handoff.sh "$PWD" show
```

Script commands: `meta`, `git`, `tasks`, `new TASK`, `prune TASK`,
`done TASK`, `restore TASK`, `stale FILE`, `show [@TASK|FILE]`, and `tips status|list|search
[--error] WORDS|show ID|new ID [project|global]|verified ID|refuted ID
REASON|supersede OLD NEW|move ID global|project|hook|prompt-hook`.

## License

[MIT](LICENSE)
