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
- **Chained history.** Each new handoff reads the previous one for its task
  and carries over what is still relevant. The last 10 per task are kept.
- **No secrets.** The skill is told never to write tokens or credentials,
  only where they live.
- **Small and dependency-free.** One Bash script: bash 3.2+ and git. Works
  on Linux, macOS and Termux (Android).

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
```

To update, run `git pull && ./install.sh`. To remove, run
`./install.sh --uninstall`; saved handoffs are kept.

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
  `commit`, `created`, `task`, `previous`, `session`, `title`), followed by
  the sections *Goal, State, Decisions, Key context, Gotchas, User
  preferences, Next steps, Verify*.
- The model writes the summary; `skills/handoff/handoff.sh` handles storage,
  task listing, pruning, archiving and the staleness report. The script
  always exits 0, because a failing `!` command would abort the skill.

To restore an archived task, run `/pickup @task`: for an archived task it
prints the exact command, which moves the handoffs back (merging them into a
new task of the same name, if you started one). `/handoff @task` also warns
when it starts a new task whose name is in the archive.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `HANDOFF_ROOT` | `${CLAUDE_CONFIG_DIR:-~/.claude}/handoffs` | Where handoffs are stored. |
| `HANDOFF_KEEP` | `10` | Handoffs kept per task (a positive integer; anything else means 10). Older ones are deleted when you save. |

Set them in your shell profile or in the `env` block of
`~/.claude/settings.json`.

## Requirements

- Claude Code with skills support
- bash 3.2 or newer (macOS system bash works)
- git 2.31 or newer (only needed for git metadata; plain directories work
  without it)

## Privacy and security

- Handoffs stay on your machine under `HANDOFF_ROOT` and are never committed
  to your repositories.
- The skill is told not to write secrets. Still, review a handoff before
  sharing it, because it summarizes your conversation.
- The skill may only run its own script (`allowed-tools` is scoped to
  `handoff.sh`) and write the handoff file.

## Development

```bash
tests/test.sh                                            # end-to-end tests in a temp dir
shellcheck skills/handoff/handoff.sh install.sh tests/test.sh
```

CI runs shellcheck and the tests on Ubuntu and on macOS (bash 3.2).

To try the script by hand without touching your real handoffs:

```bash
HANDOFF_ROOT=$(mktemp -d) skills/handoff/handoff.sh "$PWD" show
```

Script commands: `meta`, `git`, `tasks`, `new TASK`, `prune TASK`,
`done TASK`, `stale FILE`, `show [@TASK|FILE]`.

## License

[MIT](LICENSE)
