# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- The config file `${XDG_CONFIG_HOME:-~/.config}/claude-handoff/config`
  (or `HANDOFF_CONFIG`): `root=` sets the handoff root for every script and
  the dashboard, instead of `HANDOFF_ROOT` in several places.
  `HANDOFF_ROOT` still overrides it. `install.sh` does not write the file.
- `handoffs service install` no longer copies `HANDOFF_ROOT` into the
  unit/plist: the service reads `root=` from the config file. If you set
  the root only with `HANDOFF_ROOT`, put `root=` in the config file and run
  `handoffs service install` again.

### Changed

- `HANDOFF_ROOT` holds only the `.md` files of handoffs and tips, so several
  machines can share one root. Files of each machine are kept in
  `HANDOFF_STATE` (default `${XDG_STATE_HOME:-~/.local/state}/claude-handoff`):
  the tips log (`tips.jsonl`, was `_tips/log.jsonl`) and the `--background`
  dashboard's `handoffs.pid` and `handoffs.log` (were `.handoffs.pid` and
  `.handoffs.log` in the root). The next tips event moves the old log there;
  the dashboard still reads it until then. The old PID file and log are
  removed when the dashboard starts or stops, and the old PID is not used.

## [1.5.0] - 2026-09-29

### Breaking

- Handoffs and tips are stored in `${XDG_DATA_HOME:-~/.local/share}/claude-handoff`
  (or `HANDOFF_ROOT`), not in `${CLAUDE_CONFIG_DIR:-~/.claude}/handoffs`.
  Nothing is moved and the old directory is not read. To keep your
  handoffs, move them by hand:
  `mkdir -p ~/.local/share && mv ~/.claude/handoffs ~/.local/share/claude-handoff`.
- A project is the name of the directory the session was opened in
  (lowercased, `a-z0-9._-`), not its full path: `~/code/app` is `app`, not
  `home~code~app`. Git worktrees no longer share the main repository's
  project: each is named after its directory. To keep a project's handoffs,
  rename its directory in the handoff root, and its tips in `_tips/`:
  `mv home~code~app app`, `mv _tips/home~code~app _tips/app`. Tip statistics
  in the dashboard start over for a renamed project.

### Added

- `handoff.sh PROJECT_DIR describe [TEXT]`: a description of the project,
  stored as `_project.md` and shown by `/pickup`, `/handoff` and the
  dashboard.
- `describe --parent`: a directory's project becomes `<parent>~<name>`
  (`work~api`), so same-named directories can keep separate handoffs;
  `describe --no-parent` renames it back.
- The handoff frontmatter has `host:`.

### Changed

- `dir` and `repo` in the frontmatter are relative to the project directory,
  and `/handoff` writes paths inside the project relative to it. `/pickup`
  resolves them against the current project directory, so they survive a
  moved project; an older absolute path under the handoff's `project:` is
  moved along with it.
- Dashboard: the tasks of one project are grouped by its name, whatever path
  they were saved from; the project's path is one that exists here.

### Fixed

- Frontmatter is valid YAML, so Markdown editors that read it (Obsidian)
  no longer report invalid properties: `/handoff` writes `title` in double
  quotes, tips have `title` and `when` in double quotes and `keywords` as a
  `[list]`, and `tips refuted` quotes a reason with `: `. The scripts and the
  dashboard read quoted values and the older unquoted form alike.

## [1.4.3] - 2026-09-28

### Fixed

- Tips on Termux: search and the hooks found nothing, because Termux gawk
  in the C locale aborts on UTF-8 bytes in a regex group (`unbalanced (`)
  and its `.` does not match them, which broke front matter lines with
  Cyrillic. The stop words and the front matter no longer use such regexes.

## [1.4.2] - 2026-09-28

### Changed

- Dashboard: a sidebar with the search, All, the projects (active-task counts,
  or matches while searching) and Global tips replaces the grid of project
  tiles. A picked project takes the full width; All shows the projects in one
  column. The pick is kept in the URL hash, so a reload keeps it. On a narrow
  screen the sidebar turns into a dropdown.

## [1.4.1] - 2026-09-28

### Fixed

- Dashboard: Global tips start collapsed on every load; the open state is
  no longer kept in the browser (once opened, they used to stay open).

## [1.4.0] - 2026-09-28

### Added

- Task forks: `/handoff fork [@task] <text>` in a session resumed with
  `/pickup` saves the parent (waiting for the fork) and a new task with
  `from: <parent>`. `/pickup` shows `fork of @parent (status)` and a
  `## forks` list with each fork's status and first line of State.
- Dashboard: forks hang under their parent as a tree, done forks stay there
  dimmed with a check; `↑ @parent` / `↓ @fork` chips open the linked task.
  Rename updates `from:` in the forks.
- `handoff.sh tasks` lists archived tasks too (marked `archived`); `show` of
  an archived task prints its last handoff's `file:`.

### Changed

- `/handoff @task done` in a session resumed with `/pickup @task` saves a
  final handoff before archiving.
- Dashboard: the node icon shows the task's state (open ◉, done ✓) instead of
  a freshness dot.
- `/handoff` writes the handoff in the language of the conversation (headings
  and frontmatter keys stay English), instead of drifting to the template's
  English.
- Dashboard footer: version and root on the left, GitHub and Changelog links
  on the right; it sits at the bottom of the window even with a short list.

### Fixed

- `install.sh --uninstall` / `--no-dashboard` no longer abort where there is
  no systemd or launchd (Termux).
- `tests/test.sh` no longer restarts and uninstalls the real dashboard service.
- `/handoff` and `/pickup` run each `handoff.sh` command in its own Bash call,
  without `cd`, `;`, `&&` or pipes, so it matches `allowed-tools` instead of
  going to the auto mode classifier (which could fail with "no verdict").

## [1.3.1] - 2026-09-28

### Added

- `handoffs --background` / `--stop`: run the dashboard detached, without
  holding the terminal.
- `handoffs service install|uninstall|restart|status`: optional user service
  (systemd `--user` or launchd) that keeps the dashboard running;
  `install.sh` restarts it after an update and removes it on uninstall.
- Tip usage on the dashboard: each tip shows how often it was offered (by a
  hook or search), opened, verified and refuted; "opened N×" or "never
  opened" (offered 5+ times) chips help to find useless tips.
- Dashboard theme button next to Reload: auto (system), light or dark,
  remembered in the browser.

### Changed

- The tips log (`_tips/log.jsonl`) keeps found ids instead of the search text,
  so nothing needs masking (`tips_redact` is gone), and rotates to
  `log.1.jsonl` past 256 KB (`TIPS_LOG_MAX`).
- Dashboard: *Projects* and *Global tips* sections with matching headings and
  counts; *Global tips* is collapsed by default (a search opens it). Tab and
  History counts are badges. All icons are now [Lucide](https://lucide.dev).
- `/pickup` shows the age of an older handoff in days (`age: 30d`, not `720h`).

### Fixed

- The prompt hook removes its week-old per-session seen-files from `$TMPDIR`.

## [1.3.0] - 2026-09-28

### Changed

- `/handoff` loads the tip-saving instructions only with tips on: they moved
  to `skills/handoff/references/tips.md`, which `tips status` prints; with
  tips off the skill prompt is a third smaller.
- Dashboard: projects are equal-height tiles in a responsive grid, each
  with a colour accent, initials, the last handoff's age and *Tasks*/*Tips*
  tabs; a task or tip opens in a side panel (Esc closes it) instead of
  expanding in place; global tips are cards; a freshness dot per task;
  project sections no longer collapse. Compact rows (title, `@task`,
  age, Copy and an arrow; no Details button), the search in the header,
  neutral section headings, bold tip labels, one button style in the
  panel, an inline favicon (no CSP error in the console).

### Added

- Dashboard: search matches are highlighted, `/` focuses the search and
  `Esc` clears it, *Clear search* when nothing matches.

## [1.2.2] - 2026-09-28

### Added

- One-line install: `curl -fsSL .../install.sh | bash` fetches the
  repository into a temp dir (git, or a tarball without git), runs its
  `install.sh` and deletes the copy; `| bash -s -- FLAGS` passes flags,
  `HANDOFF_REF` picks a branch or tag, `--uninstall` needs no copy. The
  README recommends it over the plugin.

### Changed

- `install.sh` questions default to the previous answers.
- `/pickup` and `/handoff @task` no longer print a raw `mv` command to
  restore an archived task; they point to `/pickup @task` and its Restore
  option.
- `handoff.sh` computes the project key once per run: listing 30 tasks
  takes 2 git calls instead of 122, so `/pickup` and `/handoff` start faster.

### Fixed

- Project keys are one-to-one: `/a~b` and `/a/b`, or `~/x` and `/home/x`,
  no longer share handoffs and tips. Paths outside `$HOME` now start with
  `root~` (`/srv/app` -> `root~srv~app`), and `~` and `%` in names are
  escaped; handoffs saved for such paths are not found under the new key
  (move the directory by hand to keep them).
- Tips search and hooks match Cyrillic the same way with any awk and
  locale: mawk (Debian, Ubuntu) and macOS awk without a UTF-8 locale did
  not lowercase `Реліз`, matched `реліз` inside `перереліз` and counted
  bytes as characters; macOS awk could abort on UTF-8 text.
- Tips without a `status:` line count as active (as in the dashboard), and
  tips with CRLF line ends are found and can be marked.
- An interrupted `install.sh` no longer leaves the skills (and
  `install.conf`) deleted: each skill is copied first, then swapped in.
- `tests/test.sh` no longer hangs on the install questions when run from a
  terminal.

## [1.2.1] - 2026-09-27

### Added

- A `UserPromptSubmit` tips hook: when the request contains a tip's keyword
  (at a word start; one item of 5+ characters or two shorter ones), the
  titles of up to 3 matching tips are added to the context, each tip once
  per session. Our own `/tips`, `/handoff` and `/pickup` are skipped; only
  matched ids are logged, never the prompt. `install.sh --tips` adds it next
  to the failure hook.

### Changed

- The `CLAUDE.md` tips block also asks to search tips before answering
  how-to or procedure questions ("how do we release?") and to check tips a
  hook lists.

## [1.2.0] - 2026-09-27

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

[1.5.0]: https://github.com/v-kravchenko/claude-handoff/compare/v1.4.3...v1.5.0
[1.4.3]: https://github.com/v-kravchenko/claude-handoff/compare/v1.4.2...v1.4.3
[1.4.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/v-kravchenko/claude-handoff/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/v-kravchenko/claude-handoff/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/v-kravchenko/claude-handoff/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/v-kravchenko/claude-handoff/releases/tag/v1.0.0
