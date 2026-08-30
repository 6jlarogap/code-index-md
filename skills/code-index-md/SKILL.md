---
name: code-index-md
description: Use CODE_INDEX.md and .code-index/ tiered symbol indexes to navigate repositories without loading full files. Use when the user mentions code index, CODE_INDEX.md, line-number index, offset/limit source reads, navigating a repo with compact indexes, rebuilding a code index, or installing/maintaining the code-index-md Claude plugin or Codex skill.
---

# code-index-md

Use the generated index before opening indexed source files. The goal is to read the smallest exact fragment that answers the task.

## Navigation Workflow

1. Read `CODE_INDEX.md` first.
2. If it has `SUBTREES`, open the referenced `.code-index/<dir>.md` for the directory you need.
3. If a file is marked `HOT`, open the referenced `.code-index/<dir>/<file>.md`.
4. Read source with the indexed line and size, for example `Read path/to/file.py offset=127 limit=45`. Treat `rows=L` examples as equivalent to `limit=L`.
5. If the project is small and `CODE_INDEX.md` is flat, read line numbers directly from it.

## After Edits

Regenerate the index after changing indexed docs or source:

```bash
bash hooks/reindex.sh
```

For copied/manual installs, pick the project root explicitly when needed:

```bash
CODE_INDEX_ROOT=/path/to/project bash /path/to/code-index-md/hooks/reindex.sh
CODEX_PROJECT_ROOT=/path/to/project bash /path/to/code-index-md/hooks/reindex.sh
CLAUDE_PROJECT_ROOT=/path/to/project bash /path/to/code-index-md/hooks/reindex.sh
```

Root discovery order is `CODE_INDEX_ROOT`, `CODEX_PROJECT_ROOT`, `CLAUDE_PROJECT_ROOT`, then `pwd`.

## Indexed Content

The generator indexes JavaScript (`*.js`, `*.mjs`, `*.cjs`), shell (`*.sh`), Python (`*.py`), Java (`*.java`), and Markdown headings through `####`. It skips generated/vendor paths such as `.git/`, `.code-index/`, `node_modules/`, Python virtualenv/cache directories, Java build/test dirs, minified JS, and user exclusions from `REINDEX_EXCLUDE`.

Never edit generated `.code-index/` files or temporary `.code-index.tmp.*` / `.code-index.old.*` directories. Update source files and regenerate instead.

## Claude Plugin Note

Claude installs call the same `hooks/reindex.sh` through `.claude-plugin/plugin.json`. Preserve that contract when changing the skill or hook scripts.

Suggested Claude project instruction:

```markdown
## Code Navigation
CODE_INDEX.md exists in project root. Always read it before opening indexed source files.
Follow tier-1 -> .code-index/<dir>.md -> .code-index/<dir>/<file>.md, then read exact fragments with offset=N limit=L.
Regenerate with bash hooks/reindex.sh after indexed files change.
```
