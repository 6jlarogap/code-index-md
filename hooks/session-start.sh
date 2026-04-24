#!/usr/bin/env bash
# Rebuilds CODE_INDEX.md if plugin version has changed since last index.
ROOT="${CLAUDE_PROJECT_ROOT:-$(pwd)}"
INDEX="$ROOT/CODE_INDEX.md"

[[ -f "$INDEX" ]] || exit 0

PLUGIN_VER=$(grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep -o '[0-9][0-9.]*')
INDEX_VER=$(grep -m1 '^> Plugin-Version:' "$INDEX" | grep -o '[0-9][0-9.]*')

if [[ "$INDEX_VER" != "$PLUGIN_VER" ]]; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/reindex.sh"
fi
