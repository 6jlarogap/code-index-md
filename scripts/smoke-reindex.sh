#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/code-index-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

write_fixture() {
  local project="$1"
  mkdir -p "$project/src/main/java/example" "$project/docs" "$project/pkg"
  cat > "$project/app.js" <<'JS'
function alpha() {
  return 1;
}

const beta = () => {
  return 2;
};
JS
  cat > "$project/pkg/sample.py" <<'PY'
class Sample:
    pass

def gamma():
    return 3
PY
  cat > "$project/src/main/java/example/App.java" <<'JAVA'
package example;

public class App {
    public void run() {
    }
}
JAVA
  cat > "$project/docs/guide.md" <<'MD'
# Guide

## Setup
MD
}

assert_contains() {
  local path="$1" pattern="$2"
  if ! grep -Fq "$pattern" "$path"; then
    echo "Expected $path to contain: $pattern" >&2
    exit 1
  fi
}

run_case() {
  local env_name="$1"
  local project="$TMP_ROOT/$env_name"
  write_fixture "$project"

  case "$env_name" in
    claude) CLAUDE_PROJECT_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" ;;
    codex) CODEX_PROJECT_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" ;;
    generic) CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" ;;
  esac

  test -f "$project/CODE_INDEX.md"
  assert_contains "$project/CODE_INDEX.md" 'offset=N limit=L'
  assert_contains "$project/CODE_INDEX.md" 'alpha'
  assert_contains "$project/CODE_INDEX.md" 'class Sample'
  assert_contains "$project/CODE_INDEX.md" 'public class App'
  assert_contains "$project/CODE_INDEX.md" '# Guide'
}

run_case claude
run_case codex
run_case generic

echo "Reindex smoke OK."
