# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

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

[1.0.0]: https://github.com/v-kravchenko/claude-handoff/releases/tag/v1.0.0
