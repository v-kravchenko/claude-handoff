# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Tips: `/handoff` saves 0–3 short, unverified hints per session (project
  or global level, with a `Verify` step); `/tips` searches the current
  project and global tips; `handoff.sh tips ...` manages them
  (`search`, `show`, `verified`, `refuted`, `supersede`, `move`).
- A `PostToolUseFailure` hook for Bash that adds matching tip titles to the
  context when a command fails.
- `install.sh` asks whether to install the dashboard and tips (or takes
  `--dashboard`, `--no-dashboard`, `--tips`, `--no-tips`). Tips add a marked
  block to `~/.claude/CLAUDE.md` and the hook to `~/.claude/settings.json`;
  `--uninstall` removes both. It never touches a `tips` skill that is not
  ours and remembers the choices in `skills/handoff/install.conf` for
  installs without a terminal. The `tips` skill lives in `extras/`, so the
  plugin keeps only `handoff` and `pickup`.
- `handoffs`: tips fold under *Tips (N)* in their project's section (global
  ones under *Global tips (N)*), are searched with the tasks and can be
  deleted.

### Changed

- `handoffs` ignores the `_tips` store when listing projects.

## [1.1.3] - 2026-09-26

### Added

- `handoffs`: a *Rename* button in *Details* renames a task (active or
  archived) and updates the `task:` field of its handoffs. Names taken by
  another task of the project are refused.

## [1.1.2] - 2026-09-26

### Changed

- `/handoff` writes from the current state instead of appending to the last
  handoff. It reads the last handoff only when it is not already in the
  conversation, and carries over only open decisions, rejected alternatives
  and gotchas that git, the code, the changelog and CLAUDE.md don't record.
  It aims for under ~600 words, skips what CLAUDE.md or memory already says
  and one-off details, and writes nothing when nothing changed.

### Removed

- The `previous` frontmatter field. It always pointed to the task's latest
  handoff and broke when a task was archived. `handoff.sh new` now prints
  `latest:` instead.

## [1.1.1] - 2026-09-26

### Removed

- `handoffs`: the staleness chips (new commits, dirty files) and the
  `/api/stale` endpoint. A commit count said little on its own, and
  `/pickup` already reports staleness with the actual diffs. The dashboard
  no longer runs git.

## [1.1.0] - 2026-09-26

### Added

- `handoffs`: a local web dashboard with the tasks of every project, grouped
  by project with archived tasks folded away. Each card shows the task,
  title, age and warning chips (archived, idle, new commits), with a button
  that copies
  `cd <project> && claude "/pickup @task"`. *Details* shows the branch,
  commit, staleness report and the whole latest handoff, plus a history of
  versions with diffs. *Done* and *Restore* archive and restore tasks (off with
  `--read-only`). A search box filters the cards and searches the full
  handoff text. Run it in a terminal; it serves
  `http://127.0.0.1:8765/`, opens a browser where it can, and stops with
  Ctrl+C. It needs python3 (standard library only). `install.sh` installs it
  into `~/.local/bin` (`$PREFIX/bin` on Termux, or `HANDOFF_BIN_DIR`).

## [1.0.2] - 2026-09-26

### Added

- `/pickup` with no task, or with an unknown or archived one, shows a menu of
  the newest tasks, so you pick one with a click instead of typing
  `/pickup @task`. For an archived task the menu offers *Restore*, which moves
  the handoffs back and loads the task.
- `handoff.sh PROJECT_DIR restore TASK` restores an archived task.

## [1.0.1] - 2026-09-26

### Fixed

- Both skills failed when the project path contained a space: the project
  directory and `/pickup` arguments are now quoted.
- `HANDOFF_KEEP=0` deleted every handoff of the task, including the one just
  saved; a non-numeric value made the script exit with an error. Anything but
  a positive integer now means the default, 10.
- Two saves of the same task within one second got the same file name, so the
  second overwrote the first.
- The restore command for an archived task failed if a new task with the same
  name had been started. It now merges the handoffs back.
- `/handoff @task done` on a task with no saved handoffs created an empty
  archive entry.
- `/pickup word` opened a file named `word` in the current directory instead
  of the task. A file argument must now contain `/` or end in `.md`.
- A project directory that starts with the path of `$HOME` (such as
  `/home/bob2` for `/home/bob`) was keyed as if it were inside `$HOME`, and
  the filesystem root got an empty key.

### Changed

- `/handoff` warns when it starts a new task whose name is in the archive.
- `/pickup @task notes` ignores the words after the task.
- Tests run the skills' `!` commands the way Claude Code does and check the
  skill frontmatter.

## [1.0.0] - 2026-09-26

### Added

- `/handoff` skill: saves a session handoff per project directory and task
  (`@task`), chains to the previous handoff, prunes old ones, archives
  finished tasks with `@task done`.
- `/pickup` skill: resumes the latest handoff for a task, with a staleness
  report (age, new commits, rebased or missing commit, dirty files, missing
  work directory).
- Claude Code plugin and marketplace manifests.
- `install.sh` for installing as personal skills.
- End-to-end tests and CI (shellcheck, Ubuntu and macOS).

[1.1.3]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/v-kravchenko/claude-handoff/releases/tag/v1.0.0
