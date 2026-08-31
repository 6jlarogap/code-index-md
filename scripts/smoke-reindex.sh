#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/code-index-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

write_fixture() {
  local project="$1"
  mkdir -p "$project/src/main/java/example" "$project/docs" "$project/pkg" \
    "$project/nested" "$project/esm" "$project/common" "$project/scripts"
  cat > "$project/app.js" <<'JS'
function alpha() {
  return 1;
}

const beta = () => {
  return 2;
};
JS
  cat > "$project/nested/feature.js" <<'JS'
function nested() {
  return 3;
}
JS
  cat > "$project/esm/module.mjs" <<'JS'
export function moduleFn() {
  return 4;
}
JS
  cat > "$project/common/module.cjs" <<'JS'
function commonFn() {
  return 5;
}
JS
  cat > "$project/scripts/task.sh" <<'SH'
run_task() {
  :
}

function cleanup {
  :
}
SH
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

assert_not_contains() {
  local path="$1" pattern="$2"
  if grep -Fq "$pattern" "$path"; then
    echo "Expected $path not to contain: $pattern" >&2
    exit 1
  fi
}

hook_reindex() {
  local project="$1" path="$2" hot_lines="${3:-2}"
  printf '{"tool_input":{"file_path":"%s"}}' "$path" | \
    CODE_INDEX_ROOT="$project" HOT_LINES="$hot_lines" bash "$ROOT_DIR/hooks/reindex.sh"
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
  assert_contains "$project/CODE_INDEX.md" 'nested'
  assert_contains "$project/CODE_INDEX.md" 'moduleFn'
  assert_contains "$project/CODE_INDEX.md" 'commonFn'
  assert_contains "$project/CODE_INDEX.md" 'run_task'
  assert_contains "$project/CODE_INDEX.md" 'cleanup'
  assert_contains "$project/CODE_INDEX.md" 'class Sample'
  assert_contains "$project/CODE_INDEX.md" 'public class App'
  assert_contains "$project/CODE_INDEX.md" '# Guide'
}

run_freshness_case() {
  local project="$TMP_ROOT/freshness"
  write_fixture "$project"
  cat > "$project/pkg/other.py" <<'PY'
def delta():
    return 4
PY
  CODE_INDEX_ROOT="$project" HOT_LINES=2 bash "$ROOT_DIR/hooks/reindex.sh"
  test -f "$project/.code-index/pkg/sample.py.md"

  printf 'def gamma():\n    return 3\n' > "$project/pkg/sample.py"
  hook_reindex "$project" "$project/pkg/sample.py"
  test ! -e "$project/.code-index/pkg/sample.py.md"

  rm "$project/pkg/other.py"
  hook_reindex "$project" "$project/pkg/other.py"
  assert_not_contains "$project/CODE_INDEX.md" 'other.py'

  local lock_id lock_path ready release lock_pid hook_pid
  lock_id=$(printf '%s' "$project" | cksum | awk '{print $1}')
  lock_path="${TMPDIR:-/tmp}/code-index-md-$lock_id.lock"
  ready="$TMP_ROOT/lock-ready"
  release="$TMP_ROOT/lock-release"
  mkfifo "$release"
  flock "$lock_path" bash -c 'touch "$1"; read -r < "$2"' _ "$ready" "$release" &
  lock_pid=$!
  until test -f "$ready"; do sleep 0.01; done

  printf 'def updated():\n    return 4\n' > "$project/pkg/sample.py"
  hook_reindex "$project" "$project/pkg/sample.py" &
  hook_pid=$!
  sleep 0.1
  kill -0 "$hook_pid"
  printf 'release\n' > "$release"
  wait "$lock_pid"
  wait "$hook_pid"
  assert_contains "$project/CODE_INDEX.md" 'def updated'
}

run_collision_case() {
  local project="$TMP_ROOT/collision"
  mkdir -p "$project/pkg"
  printf 'function js() {\n  return 1;\n}\n' > "$project/pkg/module.js"
  printf 'export function mjs() {\n  return 2;\n}\n' > "$project/pkg/module.mjs"
  printf 'def py():\n    return 3\n' > "$project/pkg/support.py"
  CODE_INDEX_ROOT="$project" HOT_LINES=1 bash "$ROOT_DIR/hooks/reindex.sh"
  test -f "$project/.code-index/pkg/module.js.md"
  test -f "$project/.code-index/pkg/module.mjs.md"
  assert_contains "$project/CODE_INDEX.md" '| pkg/ | mixed |'

  printf 'function js() {}\n' > "$project/pkg/module.js"
  hook_reindex "$project" "$project/pkg/module.js" 1
  test ! -e "$project/.code-index/pkg/module.js.md"
  test -f "$project/.code-index/pkg/module.mjs.md"
}

run_home_rejection_case() {
  local project="$TMP_ROOT/home"
  mkdir -p "$project"
  if HOME="$project" CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh"; then
    echo "Expected reindex.sh to reject HOME" >&2
    exit 1
  fi
  test ! -e "$project/.code-index"
}

run_case claude
run_case codex
run_case generic
run_freshness_case
run_collision_case
run_home_rejection_case

echo "Reindex smoke OK."
