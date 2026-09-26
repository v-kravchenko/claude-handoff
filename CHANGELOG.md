# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

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

[1.0.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/v-kravchenko/claude-handoff/releases/tag/v1.0.0
