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
- **Dashboard.** `handoffs` shows every task of every project in the
  browser, with a one-click resume command.
- **No secrets.** The skill is told never to write tokens or credentials,
  only where they live.
- **Small and dependency-free.** One Bash script: bash 3.2+ and git. Works
  on Linux, macOS and Termux (Android). The optional dashboard needs only
  python3.

## Installation

### As a plugin (recommended)

In Claude Code:

```text
/plugin marketplace add v-kravchenko/claude-handoff
/plugin install handoff@claude-handoff
```

Plugin skills are namespaced, so the commands are **`/handoff:handoff`** and
**`/handoff:pickup`**. Update with `/plugin marketplace update claude-handoff`.

### As personal skills

This gives you the short commands `/handoff` and `/pickup`:

```bash
git clone https://github.com/v-kravchenko/claude-handoff.git
cd claude-handoff
./install.sh              # copies skills to ~/.claude/skills (respects CLAUDE_CONFIG_DIR)
                          # and the `handoffs` dashboard to ~/.local/bin
```

To update, run `git pull && ./install.sh`. To remove, run
`./install.sh --uninstall`; saved handoffs are kept.

The dashboard command goes to `~/.local/bin` (`$PREFIX/bin` on Termux); set
`HANDOFF_BIN_DIR` to choose another directory. Plugin users can run
`bin/handoffs` from a clone.

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

Both skills set `disable-model-invocation: true`, so they run only when you
type them.

## Dashboard

`handoffs` is a terminal command that shows every task of every project in
the browser:

```text
$ handoffs
handoffs: http://127.0.0.1:8765/  (root: ~/.claude/handoffs; Ctrl+C to stop)
```

Tasks are grouped by project (the directory the handoffs belong to); each
project section shows its active tasks and folds its archived ones under
*Archived (N)*. Sections collapse with a tap. Each card shows the task,
its title and age, and chips only when something needs attention
(archived, idle for 14+ days, a missing project directory). Only one card
is expanded at a time. Its buttons:

- **Copy resume** copies the resume command, `cd ~/'project' && claude "/pickup @task"`.
- **Details** (or a tap on the card) shows the branch and commit at
  handoff time and renders the whole latest handoff. The *History* tab
  lists every saved version, opens any of them and shows the diff against
  the previous one. The staleness report is left to `/pickup`.
- **Done** (in *Details*) archives an active task and **Restore** brings an
  archived one back, like `/handoff @task done` and the *Restore* option of
  `/pickup`.
- **Rename** (in *Details*) gives a task a new name (lowercase
  `a-z0-9._-`, not taken by another active or archived task of the
  project) and updates the `task:` field of its handoffs.

The search box filters by task, title and goal at once, and also searches
the full text of the latest handoffs. The page reads the handoff files on
every request and refreshes itself every 30 seconds, so it is never out of
date.

| Option | Meaning |
| --- | --- |
| `--port N` | Port to listen on (default `$HANDOFF_PORT` or `8765`); if it is busy, the next nine are tried. `0` picks any free port. |
| `--host ADDR` | Address to listen on (default `127.0.0.1`). |
| `--no-open` | Only print the URL. |
| `--read-only` | Hide the *Done*, *Restore* and *Rename* buttons and refuse changes. |
| `--json` | Print the task data as JSON and exit. |

The browser opens with `open` (macOS), `xdg-open` (Linux desktop),
`wslview` or `explorer.exe` (WSL), the default browser (Windows) or
`termux-open-url` (Termux). Over SSH or without a display, the command only
prints the URL. On Termux, keep Termux in the foreground for the browser to
open, or tap the printed URL.

## How it works

Handoffs are plain Markdown files stored outside your repositories:

```text
~/.claude/handoffs/
└── <project-slug>/                 # e.g. home~code~app for ~/code/app
    ├── <task>/
    │   ├── 2026-09-25_101500.md
    │   └── 2026-09-26_173557.md    # latest one wins
    └── _archive/
        └── <task>/...              # tasks finished with `/handoff @task done`
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
- The dashboard listens on `127.0.0.1` only and reads nothing but handoff
  files of listed tasks. It rejects requests whose `Host` header is not
  local, which blocks DNS-rebinding attacks from web pages. Its only changes
  are *Done*, *Restore* and *Rename*: they need a random token that is embedded in the
  page at startup and sent in a custom header, so other web pages cannot
  trigger them. `--read-only` turns them off. Other programs on the same
  machine (on Android, other apps) are not web pages: while the dashboard
  runs they can read it and, unless it is `--read-only`, also use *Done*,
  *Restore* and *Rename*.

## Development

```bash
tests/test.sh                                            # end-to-end tests in a temp dir
shellcheck skills/handoff/handoff.sh install.sh tests/test.sh
HANDOFF_ROOT=$(mktemp -d) bin/handoffs --no-open         # dashboard on an empty root
```

CI runs shellcheck and the tests on Ubuntu and on macOS (bash 3.2). The
dashboard tests are skipped when python3 is missing.

To try the script by hand without touching your real handoffs:

```bash
HANDOFF_ROOT=$(mktemp -d) skills/handoff/handoff.sh "$PWD" show
```

Script commands: `meta`, `git`, `tasks`, `new TASK`, `prune TASK`,
`done TASK`, `stale FILE`, `show [@TASK|FILE]`.

## License

[MIT](LICENSE)
