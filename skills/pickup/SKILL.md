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

Below, `handoff.sh` means `${CLAUDE_SKILL_DIR}/../handoff/handoff.sh "${CLAUDE_PROJECT_DIR}"`.
Run each `handoff.sh` command in its own Bash call, exactly as written: no
`cd`, `;`, `&&`, pipes or other commands around it. Only then it matches
`allowed-tools` and runs without a permission prompt or an auto mode check.

1. If the output says `NO HANDOFF`: tell the user there is no handoff for this
   project directory. Stop.
2. If it says `CHOOSE TASK`, `NO TASK` or `ARCHIVED`, let the user pick with
   one AskUserQuestion call. Options come from the `## tasks` list (newest
   first); each label is `@task`, each description its title and date:
   - `CHOOSE TASK`: the 4 newest tasks.
   - `NO TASK`: say the task was not found; offer the 4 newest tasks. With a
     single task, still ask ("Did you mean @x?").
   - `ARCHIVED`: first option `Restore @x`, then up to 3 newest active tasks.
   If that leaves fewer than 2 options, add `Cancel` (it stops). The user can
   type another `@task` via "Other". Then:
   - a task: run `handoff.sh show @task` and go on with step 3;
   - `Restore @x`: run `handoff.sh restore x`, then `handoff.sh show @x`, and
     go on with step 3.
3. Otherwise treat the handoff as your working context. `task` is the task a
   later `/handoff` continues. `work dir` is where the work happened (it may be
   a nested repo); run commands there. Paths in the handoff are relative to
   the project directory unless they start with `/` or `~`. Check the staleness report: new
   commits, a non-ancestor commit or dirty files mean the world moved on —
   read the relevant diffs/files before trusting the handoff's State and Next
   steps, and point out the conflicts.
4. Reply briefly:
   - `@task` and a one-line goal; for a fork, `fork of @parent (status)`;
   - forks from the `## forks` list (`@task | title | status | first line
     of State`), if any;
   - current state (3–5 bullets);
   - staleness warnings, if any;
   - with `path: conflict` in the output: the project already has another
     path on this machine; ask whether this directory replaces it (if yes,
     run `handoff.sh link`);
   - the proposed first step from Next steps (if nothing is left, suggest
     `/handoff @task done`). If a fork is `done` and the handoff does not
     account for its result yet, the first step is to take that result into
     account: `handoff.sh show @fork` prints its last handoff's `file:`; read it.
5. Don't start executing until the user confirms.
