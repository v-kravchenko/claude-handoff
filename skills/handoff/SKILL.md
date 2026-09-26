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
   prints the target `file`, plus `task` and `previous` for the frontmatter.
   If `previous` is not empty, read that file and carry over anything still
   relevant (open questions, decisions, gotchas) — don't re-litigate settled
   points, and drop what's done or obsolete. If it prints a `note:` about an
   archived task, mention it (with the restore command) in your final reply.
4. Review the whole conversation and fill the template below. Be specific:
   exact file paths (backticked, `path:line` where useful), commands, error
   messages, numbers, names. Prefer bullets. Omit a section only if it would be
   empty. If the user gave a focus, weight the handoff toward it.
5. Never include secrets (tokens, passwords, keys, credentials) — reference
   where they live instead.
6. Write the file with the Write tool to the `file` path from step 3.
7. Run `${CLAUDE_SKILL_DIR}/handoff.sh "${CLAUDE_PROJECT_DIR}" prune <task>` to keep only recent handoffs.
8. Reply with `@<task>`, the file path and a 2–3 line summary. Nothing else.

## Template

```markdown
---
<metadata lines from above>
task: <task from step 3>
previous: <previous from step 3>
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
