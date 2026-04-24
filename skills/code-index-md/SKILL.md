---
name: code-index-md
description: Maintains CODE_INDEX.md — a markdown file mapping every function name and heading to its line number. Use when starting work on a project to find functions without loading full files, or when you need to read a precise code fragment with offset+limit.
---

# code-index-md

## Overview

`CODE_INDEX.md` maps every JS function and MD heading in the project to its exact line number. Instead of loading a 400-line file to find one function, read the index first and then `Read` only the lines you need.

## When to Use

- Session start: read `CODE_INDEX.md` to orient without loading source files
- Before reading any indexed file: look up the function line number first
- After the index seems stale: manually regenerate it

**NOT for:** files not covered by the index (CSS, minified JS, node_modules)

## Workflow

### 1. Read the index

```
Read CODE_INDEX.md
```

Find the function or heading. Note the line number.

### 2. Read only that fragment

```
Read display.js offset=127 limit=L
```

`offset` = line number from index (1-based), `limit` = value shown next to the function in the index (lines until next function).

### 3. Stay in index mode

Do not load full files. If the function you need is not in the index, the index may be stale — regenerate it.

## Regenerating the Index

The PostToolUse hook regenerates `CODE_INDEX.md` automatically after every `Edit` or `Write` tool call.

To regenerate manually:

```bash
bash hooks/reindex.sh          # from plugin root
# or if configured locally:
bash scripts/reindex.sh
```

## What Gets Indexed

| File type | What is extracted |
|-----------|-------------------|
| `*.js` | Named functions, const/let arrow functions and function expressions |
| `*.md` | Headings `#` through `####` |

Excluded: `*.min.js`, files starting with `d3`, `node_modules/`, `.git/`

## Adding to CLAUDE.md

For Claude to use the index automatically in every session, add this to the project's `CLAUDE.md`:

```markdown
## Code Navigation
CODE_INDEX.md exists in project root. ALWAYS read it first before opening any source file.
Find function → get line number + limit → `Read file.js offset=N limit=L`.
Never load a full file when CODE_INDEX.md covers it.
```

## Verification

- [ ] `CODE_INDEX.md` exists and lists all JS files with function names + line numbers
- [ ] Edit any JS file → `CODE_INDEX.md` timestamp updates within seconds
- [ ] Look up a function in index → `Read file offset=N limit=L` (L from index) returns the correct function body
