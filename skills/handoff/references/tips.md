## Saving tips

Tips are short hints for any future session in this project (or on this
machine), found later with `/tips`. They are not about this task's state.
Below, `tips` means the `tips` command from step 9.

1. Pick 0–3 candidates; zero is a normal outcome. Keep only what cost effort
   to learn in this session: a dead end, a surprise, the fix for an error, a
   user correction. Gate: will a future agent act better because of it? Skip
   generic advice, one-off state, ideas not adopted, anything the code, git or
   CLAUDE.md already say, raw logs, and anything with secrets.
2. Level: would it hold in another project on this machine? Yes: `global`;
   no: `project`; unsure: `project`. A tip taken from web pages, issues or
   foreign code gets `origin: web` and stays `project`. Add `env:` (the value
   `tips new` prints) when it depends on the OS or environment.
3. Dedupe: run `tips search <the candidate's keywords>` and `tips show` close
   hits. Then:
   - same tip: nothing to write (`tips verified ID` if this session confirmed it);
   - it refines a tip: rewrite that tip's file with Write, keeping its id;
   - it contradicts a tip: add the new tip, then `tips supersede OLD NEW`;
   - no match: add it.
4. Add: `tips new <id> <project|global>` (id: a short lowercase slug) prints
   `file`, `env` and `source`; on `EXISTS`, pick another id or update that tip.
   Write the file with the Write tool from the tip template below, in English.
   The frontmatter is YAML: keep `title` and `when` in double quotes and
   `keywords` in `[...]`, and write a `"` inside a quoted value as `\"`.
   `keywords` decide whether the tip is found: exact error messages (quoted),
   commands, tools, file names, synonyms, and Ukrainian words if the topic was
   discussed in Ukrainian.
5. For tips this session relied on and did not mark yet: `tips verified ID` if
   they held, `tips refuted ID <why>` if not.

## Tip template

```markdown
---
title: "<one line: the rule>"
when: "<the situation where it applies>"
keywords: [<comma-separated; exact error messages and any item with `: `, `,` or `#` in "double quotes">]
env: <only if environment-specific: the value from `tips new`>
cites: <optional: path[:line]@commit, comma-separated>
origin: <failure | discovery | user | web>
source: <source from `tips new`> task=<task> session=<session from the handoff metadata>
status: active
---
Tip: <the rule plus a concrete anchor: file, command, version>
Why: <the reason>
Verify: <a cheap command or check that shows whether it still holds>
```
