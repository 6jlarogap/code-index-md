#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/code-index-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

write_fixture() {
  local project="$1"
  mkdir -p "$project/src/main/java/example" "$project/docs" "$project/pkg" \
    "$project/nested" "$project/nested-repo/.git" "$project/gitlink-repo" "$project/esm" "$project/common" "$project/scripts"
  git init -q "$project"
  git init -q "$project/gitlink-repo"
  git -C "$project/gitlink-repo" config user.name smoke
  git -C "$project/gitlink-repo" config user.email smoke@example.test
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
  cat > "$project/nested-repo/feature.js" <<'JS'
function nestedRepo() {
  return 6;
}
JS
  cat > "$project/gitlink-repo/feature.js" <<'JS'
function gitlinkRepo() {
  return 7;
}
JS
  git -C "$project/gitlink-repo" add feature.js
  git -C "$project/gitlink-repo" commit -qm initial
  git -C "$project" add gitlink-repo
  rm -rf "$project/gitlink-repo/.git"
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
  assert_not_contains "$project/CODE_INDEX.md" 'nestedRepo'
  assert_not_contains "$project/CODE_INDEX.md" 'gitlinkRepo'
  assert_not_contains "$project/.code-index/.manifest" 'gitlink-repo'
  assert_contains "$project/CODE_INDEX.md" 'moduleFn'
  assert_contains "$project/CODE_INDEX.md" 'commonFn'
  assert_contains "$project/CODE_INDEX.md" 'run_task'
  assert_contains "$project/CODE_INDEX.md" 'cleanup'
  assert_contains "$project/CODE_INDEX.md" 'class Sample'
  assert_contains "$project/CODE_INDEX.md" 'public class App'
  assert_contains "$project/CODE_INDEX.md" '# Guide'

  CODE_INDEX_ROOT="$project/nested-repo" bash "$ROOT_DIR/hooks/reindex.sh"
  assert_contains "$project/nested-repo/CODE_INDEX.md" 'nestedRepo'
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

run_bounded_pyramid_case() {
  local project="$TMP_ROOT/bounded" i
  mkdir -p "$project/root"
  for i in $(seq 1 80); do
    mkdir -p "$project/single-$i"
    printf 'function singleton_%s() { return %s; }\n' "$i" "$i" > "$project/single-$i/file.js"
  done
  printf 'function singleton_hot_one() { return 1; }\n\n\n' > "$project/single-1/file.js"
  printf 'function singleton_hot_two() { return 2; }\n\n\n' > "$project/single-2/file.js"
  for i in $(seq 1 20); do
    printf 'function dense_%s() { return %s; }\n' "$i" "$i" > "$project/root/file-$i.js"
  done
  for i in $(seq 1 700); do printf 'function symbol_%s() {}\n' "$i" >> "$project/root/hot.js"; done
  TIER2_MAX_FILES=10 TIER3_MAX_LINES=40 CODE_INDEX_ROOT="$project" HOT_LINES=1 bash "$ROOT_DIR/hooks/reindex.sh"
  test "$(wc -l < "$project/CODE_INDEX.md")" -le 100
  while IFS= read -r path; do test "$(wc -l < "$path")" -le 40; done < <(find "$project/.code-index" -type f -name '*.md' -print)
  test -f "$project/.code-index/root#1.md"
  test -f "$(find "$project/.code-index" -name 'single-80-file.js.md' -print -quit)"
  test -f "$(find "$project/.code-index" -name 'single-1-file.js.md' -print -quit)"
  test -f "$(find "$project/.code-index" -name 'single-2-file.js.md' -print -quit)"
  assert_contains "$project/.code-index/root.md" 'hot.js'
  test "$(rg -F -c 'symbol_' "$project/.code-index" | awk -F: '{sum += $2} END {print sum+0}')" -ge 700
  test "$(rg -F -l 'single-' "$project/CODE_INDEX.md" "$project/.code-index" | wc -l)" -ge 1
  hash_generated() {
    find "$project" -path '*/.code-index*' -type f -name '*.md' -o -name 'CODE_INDEX.md' | sort |
      while IFS= read -r path; do
        printf '%s\n' "$path"
        sed -E 's/^> Updated: .*/> Updated: normalized/' "$path"
      done | sha256sum
  }
  local first second
  first=$(hash_generated)
  CODE_INDEX_ROOT="$project" HOT_LINES=1 TIER2_MAX_FILES=10 TIER3_MAX_LINES=40 bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  second=$(hash_generated)
  test "$first" = "$second"
}

run_stale_page_case() {
  local project="$TMP_ROOT/stale-pages"
  mkdir -p "$project/group"
  printf 'function steady() { return 1; }\n' > "$project/group/steady.js"
  for i in $(seq 1 100); do printf 'function hot_symbol_%s() {}\n' "$i" >> "$project/group/hot.js"; done
  CODE_INDEX_ROOT="$project" HOT_LINES=1 TIER3_MAX_LINES=10 bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  test -f "$project/.code-index/group/hot.js.md.2.md"
  printf 'function cooled() { return 1; }\n' > "$project/group/hot.js"
  printf '{"tool_input":{"file_path":"%s"}}' "$project/group/hot.js" | \
    CODE_INDEX_ROOT="$project" HOT_LINES=1 TIER3_MAX_LINES=10 bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  test ! -e "$project/.code-index/group/hot.js.md"
  test ! -e "$project/.code-index/group/hot.js.md.2.md"
}

run_pyramid_root_cap_case() {
  local project="$TMP_ROOT/root-cap" i
  mkdir -p "$project/single"
  for i in $(seq 1 400); do printf 'function root_symbol_%s() {}\n' "$i" >> "$project/root-cap.js"; done
  for i in $(seq 1 400); do printf 'function single_symbol_%s() {}\n' "$i" >> "$project/single/file.js"; done
  TIER2_MAX_LINES=40 TIER3_MAX_LINES=40 HOT_LINES=1 CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  test "$(wc -l < "$project/CODE_INDEX.md")" -le 100
  assert_contains "$project/CODE_INDEX.md" '.code-index/root-cap.md'
  assert_contains "$project/CODE_INDEX.md" '.code-index/single.md'
  test -f "$project/.code-index/root-cap/root-cap.js.md"
  test -f "$project/.code-index/single/file.js.md"
  test "$(rg -F -c 'root_symbol_' "$project/.code-index" | awk -F: '{sum += $2} END {print sum+0}')" -ge 400
  test "$(rg -F -c 'single_symbol_' "$project/.code-index" | awk -F: '{sum += $2} END {print sum+0}')" -ge 400
}

run_incremental_shard_case() {
  local project="$TMP_ROOT/incremental-shard" i
  mkdir -p "$project/sharded"
  for i in $(seq 1 120); do printf 'function old_symbol_%s() {}\n' "$i" > "$project/sharded/file-$i.js"; done
  TIER2_MAX_FILES=10 CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  printf 'function new_symbol_120() {}\n' > "$project/sharded/file-120.js"
  printf '{"tool_input":{"file_path":"%s"}}' "$project/sharded/file-120.js" | \
    TIER2_MAX_FILES=10 CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  ! rg -Fq 'old_symbol_120' "$project/CODE_INDEX.md" "$project/.code-index"
  rg -Fq 'new_symbol_120' "$project/CODE_INDEX.md" "$project/.code-index"
  rg -Fq $'sharded/file-120.js\t1\t1' "$project/.code-index/.manifest"
}

run_tier1_pagination_case() {
  local project="$TMP_ROOT/tier1-pages" i path
  for i in $(seq 1 120); do
    mkdir -p "$project/dir-$i"
    printf 'function hot_%s_a() {}\n' "$i" > "$project/dir-$i/a.js"
    printf 'function hot_%s_b() {}\n' "$i" > "$project/dir-$i/b.js"
  done
  TIER1_MAX_LINES=100 HOT_LINES=1 TIER2_MAX_FILES=10 CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  while IFS= read -r path; do test "$(wc -l < "$path")" -le 100; done < <(find "$project" -maxdepth 1 -type f -name 'CODE_INDEX.md*' -print)
  test -f "$project/.code-index/__tier1.md"
  test "$(find "$project/.code-index" -maxdepth 1 -type f -name '__tier1.md.*.md' -print | wc -l)" -ge 1
  test "$(rg -F -c 'hot_' "$project"/CODE_INDEX.md* "$project/.code-index" | awk -F: '{sum += $2} END {print sum+0}')" -ge 240
}

run_tier1_migration_case() {
  local project="$TMP_ROOT/tier1-migration" i
  for i in $(seq 1 120); do
    mkdir -p "$project/dir-$i"
    printf 'function migrate_%s_a() {}\n' "$i" > "$project/dir-$i/a.js"
    printf 'function migrate_%s_b() {}\n' "$i" > "$project/dir-$i/b.js"
  done
  printf 'legacy\n' > "$project/CODE_INDEX.md.2.md"
  TIER1_MAX_LINES=100 HOT_LINES=1 CODE_INDEX_ROOT="$project" bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  test ! -e "$project/CODE_INDEX.md.2.md"
  ! rg -Fq 'CODE_INDEX.md.2.md' "$project/.code-index" "$project/CODE_INDEX.md" "$project/.code-index/.manifest"
  local flat="$TMP_ROOT/tier1-flat-migration"
  mkdir -p "$flat"
  printf 'function flat_migration() {}\n' > "$flat/file.js"
  printf 'legacy\n' > "$flat/CODE_INDEX.md.2.md"
  CODE_INDEX_ROOT="$flat" bash "$ROOT_DIR/hooks/reindex.sh" >/dev/null
  test ! -e "$flat/CODE_INDEX.md.2.md"
  ! rg -Fq 'CODE_INDEX.md.2.md' "$flat/.code-index" "$flat/CODE_INDEX.md" "$flat/.code-index/.manifest"
}

run_case claude
run_case codex
run_case generic
run_freshness_case
run_collision_case
run_home_rejection_case
run_bounded_pyramid_case
run_stale_page_case
run_pyramid_root_cap_case
run_incremental_shard_case
run_tier1_pagination_case
run_tier1_migration_case

echo "Reindex smoke OK."
