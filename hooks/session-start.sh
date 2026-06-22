#!/usr/bin/env bash
# Rebuilds CODE_INDEX.md if plugin version has changed since last index.
ROOT_CANDIDATE="${CODE_INDEX_ROOT:-${CODEX_PROJECT_ROOT:-${CLAUDE_PROJECT_ROOT:-$(pwd)}}}"
ROOT="$(cd "$ROOT_CANDIDATE" && pwd -P)"
INDEX="$ROOT/CODE_INDEX.md"

[[ -f "$INDEX" ]] || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
PLUGIN_VER=$(grep -m1 '"version"' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep -o '[0-9][0-9.]*')
INDEX_VER=$(grep -m1 '^> Plugin-Version:' "$INDEX" | grep -o '[0-9][0-9.]*')

if [[ "$INDEX_VER" != "$PLUGIN_VER" ]]; then
  bash "${PLUGIN_ROOT}/hooks/reindex.sh"
fi
