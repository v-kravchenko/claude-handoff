---
name: pickup
description: Resume work from the latest handoff saved by /handoff for the session's project directory, by task name.
disable-model-invocation: true
argument-hint: "[@task | handoff file path]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/../handoff/handoff.sh *) Read
---

# Resume from a handoff

```!
${CLAUDE_SKILL_DIR}/../handoff/handoff.sh "${CLAUDE_PROJECT_DIR}" show "$ARGUMENTS"
```

## Steps

1. If the output says `NO HANDOFF`: tell the user there is no handoff for this
   project directory. Stop.
2. If it says `CHOOSE TASK`, `NO TASK` or `ARCHIVED`: show the
   message and the task list, and ask which one to resume (`/pickup @task`).
   Stop.
3. Otherwise treat the handoff as your working context. `task` is the task a
   later `/handoff` continues. `work dir` is where the work happened (it may be
   a nested repo); run commands there. Check the staleness report:
   - new commits, a non-ancestor commit or dirty files mean the world moved
     on — read the relevant diffs/files before trusting the
     handoff's State and Next steps, and point out the conflicts.
   - if `previous` references an earlier handoff and something is unclear,
     read it.
4. Reply briefly:
   - `@task` and a one-line goal;
   - current state (3–5 bullets);
   - staleness warnings, if any;
   - the proposed first step from Next steps (if nothing is left, suggest
     `/handoff @task done`).
5. Don't start executing until the user confirms.
