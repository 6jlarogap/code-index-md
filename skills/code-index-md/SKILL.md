---
name: code-index-md
description: Use CODE_INDEX.md and .code-index/ tiered symbol indexes to navigate repositories without loading full files. Use when the user mentions code index, CODE_INDEX.md, line-number index, offset/limit source reads, navigating a repo with compact indexes, rebuilding a code index, or installing/maintaining the code-index-md Claude plugin or Codex skill.
---

# code-index-md

Use the generated index before opening indexed source files. The goal is to read the smallest exact fragment that answers the task.

## Navigation Workflow

1. Inspect the `CODE_INDEX.md` header and relevant headings first; read it whole only when the index is small. For large indexes, search the relevant heading.
2. If it has `SUBTREES`, open the referenced `.code-index/<dir>.md` for the directory you need.
3. If a file is marked `HOT`, open the referenced `.code-index/<dir>/<file>.md`.
4. Read source with the indexed line and size, for example `Read path/to/file.py offset=127 limit=45`. Treat `rows=L` examples as equivalent to `limit=L`.
5. Follow `Continue:` links in paginated tier files, including singleton-tier links.
6. If the project is small and `CODE_INDEX.md` is flat, read line numbers directly from it.

## After Edits

Use one generator per exact root: prefer its documented local wrapper; otherwise use
this shared hook. Never run the shared generator over a different owner's output.
Coalesce edits in one tool batch, then refresh before the next indexed read. Skip
the manual call only after observing successful hook output covering those edits.
Do not assume the host delivers Edit/Write events for shell or patch tools.

For a single changed file, the shared hook accepts the existing stdin JSON route
(absolute file path; `jq` required):

```bash
jq -n --arg path "$changed_file" '{tool_input:{file_path:$path}}' |
  CODE_INDEX_ROOT=/path/to/project bash /path/to/code-index-md/hooks/reindex.sh
```

An existing eligible file normally refreshes its directory and root from the
manifest. Add/delete/rename, a missing manifest, or changed bucket ownership may
require a full rebuild. Unsupported, excluded, generated, and out-of-root events
are skipped. For multiple changed files, deliver each event or intentionally run
one full refresh; do not pass only the last file and assume the batch is covered.

Intentional full refresh (including scope/configuration changes):

```bash
CODE_INDEX_ROOT=/path/to/project bash /path/to/code-index-md/hooks/reindex.sh < /dev/null
```

Root precedence: `CODE_INDEX_ROOT`, `CODEX_PROJECT_ROOT`, `CLAUDE_PROJECT_ROOT`,
then `pwd`. Resolve the nearest enclosing project first; never index a parent to
cover a nested repository. In the plugin repository, use `bash hooks/reindex.sh`.

## Indexed Content

The generator indexes JavaScript (`*.js`, `*.mjs`, `*.cjs`), shell (`*.sh`), Python (`*.py`), Java (`*.java`), and Markdown headings through `####`. It skips generated/vendor paths such as `.git/`, `.code-index/`, `node_modules/`, Python virtualenv/cache directories, Java build/test dirs, minified JS, and user exclusions from `REINDEX_EXCLUDE`.

Never edit generated `.code-index/` files or temporary `.code-index.tmp.*` / `.code-index.old.*` directories. Update source files and regenerate instead.

## Claude Plugin Note

Claude installs call the same `hooks/reindex.sh` through `.claude-plugin/plugin.json`. Preserve that contract when changing the skill or hook scripts.

Suggested Claude project instruction:

```markdown
## Code Navigation
CODE_INDEX.md exists in project root. Inspect its header and relevant headings first; read it whole only when the index is small. For large indexes, search the relevant heading, follow tier-1 -> .code-index/<dir>.md -> .code-index/<dir>/<file>.md and any `Continue:` links, then read exact fragments with offset=N limit=L.
Regenerate with bash hooks/reindex.sh after indexed files change.
```
