---
name: code-index-md
description: Maintains CODE_INDEX.md — a pyramid index mapping every function name and heading to its line number. Tier-1 compact map → tier-2 per-directory symbols → tier-3 deep index for hot files. Use when starting work on a project to navigate without loading full files.
---

# code-index-md

## Overview

`CODE_INDEX.md` is a tier-1 map (≤100 lines) pointing to per-directory `.code-index/<dir>.md` files (tier-2) and deep `.code-index/<dir>/<file>.md` indexes for large files (tier-3). Navigate to exact line numbers without loading full source files.

## When to Use

- Session start: read `CODE_INDEX.md` to orient without loading source files
- Before reading any indexed file: look up the function line number in the index first
- After the index seems stale: manually regenerate it

**NOT for:** files not covered by the index (CSS, minified JS, node_modules)

## Workflow

### 1. Read tier-1

```
Read CODE_INDEX.md
```

Find the SUBTREES or HOT FILES row for the file you need. Note the `.code-index/` path.

### 2. Read tier-2

```
Read .code-index/scripts.md
```

Find the function or heading. If marked HOT, note the tier-3 path.

### 3. Read tier-3 (hot files only)

```
Read .code-index/scripts/basket.md
```

Get the exact line number and limit for the symbol.

### 4. Read the fragment

```
Read scripts/basket.py offset=127 limit=45
```

`offset` = line number from index (1-based), `limit` = lines until next symbol.

### Small projects (flat mode)

Projects with ≤10 files, no directory with ≥2 files, and <300 total lines: index stays flat in a single `CODE_INDEX.md` (identical to v1 behavior). Navigate directly from that file.

## Regenerating the Index

The PostToolUse hook regenerates the index automatically after every `Edit` or `Write` tool call.

To regenerate manually:

```bash
bash hooks/reindex.sh          # from plugin root
# With wiki-root exclusions:
CLAUDE_PROJECT_ROOT=/path/to/wiki REINDEX_EXCLUDE="state archive raw" bash hooks/reindex.sh
```

## What Gets Indexed

| File type | What is extracted |
|-----------|-------------------|
| `*.js` | Named functions, const/let arrow functions and function expressions |
| `*.java` | Classes, interfaces, public/protected methods |
| `*.md` | Headings `#` through `####` |
| `*.py` | Classes and functions (def/async def) |

Excluded: `*.min.js`, files starting with `d3`, `node_modules/`, `.git/`, common Python environment dirs (`venv/`, `.venv/`, `.tox/`, `.nox/`), `migrations/`, `__pycache__/`

Internal files (do not edit): `.code-index/.manifest` (5-field TSV: path/lines/symbols/hot/lang), `.code-index/.dirmap` (dir→encoding map)

## Adding to CLAUDE.md

```markdown
## Code Navigation
CODE_INDEX.md exists in project root. ALWAYS read it first before opening any source file.
Tier-1 → .code-index/<dir>.md → .code-index/<dir>/<file>.md → Read offset=N limit=L.
Never load a full file when CODE_INDEX.md covers it.
```

## Verification

- [ ] `CODE_INDEX.md` exists and lists SUBTREES rows for each directory with ≥2 files
- [ ] `.code-index/<dir>.md` exists for each SUBTREES row
- [ ] Edit any indexed file → `CODE_INDEX.md` timestamp updates within seconds
- [ ] Look up a function in tier-2 → `Read file offset=N limit=L` returns the correct body
