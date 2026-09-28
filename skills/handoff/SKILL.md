---
name: handoff
description: Save the essence of the current session as a handoff keyed by the session's project directory and a task name, so a new session can resume with /pickup.
disable-model-invocation: true
argument-hint: "[@task] [focus or extra notes] | @task done"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/handoff.sh *) Write
---

# Save a session handoff

Write a handoff that lets a fresh session with zero context continue this work.
It is for the next agent, not a history log: finished work is recoverable from
git, so spend words on intent, decisions, dead ends and what to do next.

## Context

Metadata (copy verbatim into the frontmatter; `dir` comes from the shell cwd,
so if the work clearly happened elsewhere, replace it with the real work dir):

```!
${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" meta
```

Git state:

```!
${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" git
```

Existing tasks in this project (`@task | title | last saved`):

```!
${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" tasks
```

Tips:

```!
${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" tips status
```

Arguments: $ARGUMENTS

## Steps

1. If the arguments are exactly `@<task> done`: run
   `${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" done <task>`, reply
   with its output and stop.
2. Pick the task (a lowercase slug, `a-z0-9._-`), first match wins:
   - `@<task>` at the start of the arguments; the rest are focus/notes;
   - the task this session resumed with `/pickup` (its output has `task: ...`);
   - an existing task above that is clearly this same work;
   - otherwise a new short slug derived from the title (not one already taken).
3. Run `${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" new <task>`. It
   prints the target `file`, the `task` for the frontmatter and the task's
   `latest` handoff. If it prints a `note:` about an archived task, mention it
   (with how to restore it) in your final reply.
4. If `latest` is not empty and that handoff is not in this conversation (the
   session did not start with `/pickup` of this task, or the context was
   compacted), read it. Carry over only open decisions, rejected alternatives
   and gotchas that git, the code, the changelog and CLAUDE.md don't already
   record; don't re-litigate settled points.
5. If nothing happened since `latest` (no changes, decisions or new facts),
   don't write a new file: do step 9 (tips) only, then reply that `latest` is
   still current (plus the tips line) and stop.
6. Write from the current state, not by appending to the old handoff. Review
   the whole conversation and fill the template below. Be specific: exact
   file paths (backticked, `path:line` where useful), commands, error
   messages, numbers, names. Prefer bullets. Omit a section only if it would be
   empty. If the user gave a focus, weight the handoff toward it. Keep it lean
   (aim for under ~600 words):
   - finished work already in git: one line with the commit hash, no details;
   - don't repeat what CLAUDE.md or memory already says (environment facts,
     user preferences);
   - nothing one-off: usage limits, CI run IDs, "this session only resumed";
   - other tasks: refer to them as `@task`, without describing their state;
   - environment facts from an earlier handoff: keep only those confirmed in
     this session.
7. Never include secrets (tokens, passwords, keys, credentials) — reference
   where they live instead.
8. Write the file with the Write tool to the `file` path from step 3.
9. Save tips, only if the Context says `tips: on`: follow "Saving tips" there,
   where `tips` means `${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" tips`.
10. Run `${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" prune <task>` to keep only recent handoffs.
11. Reply with `@<task>`, the file path and a 2–3 line summary; with tips on,
    add a line `tips: +<added> ~<updated> x<superseded or refuted>`. Nothing else.

## Template

```markdown
---
<metadata lines from above>
task: <task from step 3>
session: ${CLAUDE_SESSION_ID}
title: <short task name>
---

# <title>

## Goal
What we're trying to achieve and why; definition of done.

## State
- Done: ...
- In progress: ... (exactly where it stopped, uncommitted changes)
- Open / blocked: ...

## Decisions
- <decision> — <why>; rejected alternatives and why.

## Key context
Files, commands, URLs, data, environment facts the next session relies on.

## Gotchas
Traps, non-obvious constraints, approaches that failed and why.

## User preferences
How the user wants things done, corrections they made during the session.

## Next steps
1. <first concrete action — specific enough to start without asking>
2. ...

## Verify
How to check the current state works (tests, commands, expected output).
```
