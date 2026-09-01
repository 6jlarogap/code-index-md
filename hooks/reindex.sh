#!/usr/bin/env bash
# Regenerates CODE_INDEX.md for the current project.
# v2: pyramid output (tier-1 map / tier-2 per-dir / tier-3 hot files).
# Run by PostToolUse hook after Edit/Write, or manually.
set -euo pipefail

resolve_root() {
  local candidate="${CODE_INDEX_ROOT:-${CODEX_PROJECT_ROOT:-${CLAUDE_PROJECT_ROOT:-$(pwd)}}}"
  cd "$candidate" && pwd -P
}

ROOT="$(resolve_root)"
HOME_ROOT="$(cd "${HOME:?HOME must be set}" && pwd -P)"
if [[ "$ROOT" == "$HOME_ROOT" ]]; then
  echo "Refusing to index HOME: $ROOT" >&2
  exit 1
fi
OUTPUT="$ROOT/CODE_INDEX.md"
INDEX_DIR="$ROOT/.code-index"
MANIFEST="$INDEX_DIR/.manifest"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOT_LINES=${HOT_LINES:-500}
HOT_SYMBOLS=${HOT_SYMBOLS:-20}
MIN_DIR_FILES=${MIN_DIR_FILES:-2}
FLAT_LINES_THRESHOLD=${FLAT_LINES_THRESHOLD:-300}
REINDEX_VERBOSE=${REINDEX_VERBOSE:-0}
REINDEX_EXCLUDE="${REINDEX_EXCLUDE:-}"
REINDEX_DEFAULT_EXCLUDE="${REINDEX_DEFAULT_EXCLUDE-venv .venv .tox .nox}"
REINDEX_ALL_EXCLUDES="$REINDEX_DEFAULT_EXCLUDE $REINDEX_EXCLUDE"
MAX_SUBTREE_DEPTH=${MAX_SUBTREE_DEPTH:-}   # empty = disabled; e.g. 2 collapses depth>2 dirs into ancestor

PLUGIN_VERSION="unknown"
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]]; then
  PLUGIN_VERSION=$(grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep -o '[0-9][0-9.]*')
elif [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/.claude-plugin/plugin.json" ]]; then
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  PLUGIN_VERSION=$(grep -m1 '"version"' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep -o '[0-9][0-9.]*')
fi

# ── awk extractors (unchanged from v1) ──────────────────────────────────────

index_js() {
  local f="$1"
  local lines
  lines=$(wc -l < "$f")
  echo "## $(basename "$f") ($lines lines)"
  awk '
    BEGIN { cnt = 0 }
    /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\(/ {
      n = split($0, a, /function[[:space:]]+/)
      name = a[2]
      sub(/[[:space:]]*\(.*/, "", name)
      if (name != "") { names[cnt] = name; lnums[cnt] = NR; cnt++ }
    }
    /^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*(async[[:space:]]*)?(function[[:space:]]*\(|\()/ {
      n = split($0, a, /(const|let|var)[[:space:]]+/)
      name = a[2]
      sub(/[[:space:]]*=.*/, "", name)
      if (name != "") { names[cnt] = name; lnums[cnt] = NR; cnt++ }
    }
    END {
      for (i = 0; i < cnt; i++) {
        lim = (i+1 < cnt) ? lnums[i+1] - lnums[i] : NR - lnums[i] + 1
        printf "- `%s` \xe2\x86\x92 L%d limit=%d\n", names[i], lnums[i], lim
      }
    }
  ' "$f"
  echo ""
}

index_sh() {
  local f="$1"
  local rel="${f#$ROOT/}"
  local lines
  lines=$(wc -l < "$f")
  echo "## $rel ($lines lines)"
  awk '
    BEGIN { cnt = 0 }
    /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\(\))?[[:space:]]*\{/ {
      name = $0; sub(/^[[:space:]]*function[[:space:]]+/, "", name); sub(/[[:space:]]*\(.*/, "", name)
      names[cnt] = name; lnums[cnt] = NR; cnt++
    }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/ {
      name = $0; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*\(.*/, "", name)
      names[cnt] = name; lnums[cnt] = NR; cnt++
    }
    END {
      for (i = 0; i < cnt; i++) {
        lim = (i+1 < cnt) ? lnums[i+1] - lnums[i] : NR - lnums[i] + 1
        printf "- `%s` \xe2\x86\x92 L%d limit=%d\n", names[i], lnums[i], lim
      }
    }
  ' "$f"
  echo ""
}

index_java() {
  local f="$1"
  local rel="${f#$ROOT/}"
  local lines
  lines=$(wc -l < "$f")
  echo "## $rel ($lines lines)"
  awk '
    BEGIN { cnt = 0 }
    /^[[:space:]]*(public[[:space:]]+)?(abstract[[:space:]]+|final[[:space:]]+)?(class|interface|enum)[[:space:]]+[A-Za-z_$]/ {
      name = $0
      sub(/^[[:space:]]*/, "", name)
      sub(/[[:space:]]*\{.*$/, "", name)
      names[cnt] = name; lnums[cnt] = NR; cnt++
    }
    /^[[:space:]]*(public|protected)[[:space:]]/ && /\(/ && !/^[[:space:]]*@/ && !/=[[:space:]]*/ {
      name = $0
      sub(/^[[:space:]]*/, "", name)
      sub(/[[:space:]]*\{.*$/, "", name)
      sub(/[[:space:]]*throws[[:space:]].*$/, "", name)
      names[cnt] = name; lnums[cnt] = NR; cnt++
    }
    END {
      for (i = 0; i < cnt; i++) {
        lim = (i+1 < cnt) ? lnums[i+1] - lnums[i] : NR - lnums[i] + 1
        printf "- `%s` \xe2\x86\x92 L%d limit=%d\n", names[i], lnums[i], lim
      }
    }
  ' "$f"
  echo ""
}

index_md() {
  local f="$1"
  local rel="${f#$ROOT/}"
  local lines
  lines=$(wc -l < "$f")
  echo "## $rel ($lines lines)"
  awk '/^#{1,4}[[:space:]]/ { printf "- `%s` \xe2\x86\x92 L%d\n", $0, NR }' "$f"
  echo ""
}

index_py() {
  local f="$1"
  local rel="${f#$ROOT/}"
  local lines
  lines=$(wc -l < "$f")
  echo "## $rel ($lines lines)"
  awk '
    BEGIN { cnt = 0 }
    /^[[:space:]]*(class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/ {
      name = $0; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*[:(].*$/, "", name)
      names[cnt] = name; lnums[cnt] = NR; cnt++
    }
    /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/ {
      name = $0; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*\(.*$/, "", name)
      if (name != "") { names[cnt] = name; lnums[cnt] = NR; cnt++ }
    }
    END {
      for (i = 0; i < cnt; i++) {
        lim = (i+1 < cnt) ? lnums[i+1] - lnums[i] : NR - lnums[i] + 1
        printf "- `%s` \xe2\x86\x92 L%d limit=%d\n", names[i], lnums[i], lim
      }
    }
  ' "$f"
  echo ""
}

# ── pyramid helpers ──────────────────────────────────────────────────────────

detect_lang() {
  case "${1##*.}" in py) echo py;; js|mjs|cjs) echo js;; sh) echo sh;; java) echo java;; md) echo md;; esac
}

compute_hot() {
  local lang="$1" lines="$2" syms="$3"
  if [[ "$lang" == "md" ]]; then
    [[ $lines -gt $((HOT_LINES * 4)) ]] && echo 1 || echo 0
  elif [[ $lines -gt $HOT_LINES || $syms -gt $HOT_SYMBOLS ]]; then
    echo 1
  else
    echo 0
  fi
}

# encode_dir: maps dir path → safe filename. Uses $TMP/.dirmap for persistence.
encode_dir() {
  local dir="$1" enc base_enc n=2
  local existing
  existing=$(awk -F'\t' -v d="$dir" '$2==d{print $1; exit}' "$TMP/.dirmap" 2>/dev/null || true)
  [[ -n "$existing" ]] && { echo "$existing"; return; }
  if [[ "$dir" == "." ]]; then enc=$(basename "$ROOT"); else enc="${dir//\//-}"; fi
  base_enc="$enc"
  while awk -F'\t' -v e="$enc" '$1==e{found=1} END{exit !found}' "$TMP/.dirmap" 2>/dev/null; do
    enc="${base_enc}_${n}"; n=$(( n + 1 ))
  done
  printf '%s\t%s\n' "$enc" "$dir" >> "$TMP/.dirmap"
  echo "$enc"
}

# emit_tier1: writes CODE_INDEX.md from in-memory file_* + bucket arrays.
emit_tier1() {
  local t1_sub="" t1_hot="" t1_inline=""
  local dir dir_enc files count rel lang lines syms hot base dir_syms dir_display dir_lang

  for dir in $(printf '%s\n' "${!bucket[@]}" | sort); do
    IFS=' ' read -ra files <<< "${bucket[$dir]:-}"
    count=0
    for rel in "${files[@]}"; do [[ -n "$rel" ]] && count=$(( count + 1 )); done
    if [[ $count -lt $MIN_DIR_FILES ]]; then
      for rel in "${files[@]}"; do
        [[ -z "$rel" ]] && continue
        t1_inline+=$(index_${file_lang[$rel]} "$ROOT/$rel")$'\n'
      done
    else
      dir_enc=$(encode_dir "$dir")
      dir_syms=0
      dir_lang="${file_lang[${files[0]}]}"
      for rel in "${files[@]}"; do
        [[ -z "$rel" ]] && continue
        dir_syms=$(( dir_syms + ${file_symbols[$rel]:-0} ))
        [[ "${file_lang[$rel]}" == "$dir_lang" ]] || dir_lang="mixed"
      done
      [[ "$dir" == "." ]] && dir_display="." || dir_display="${dir}/"
      t1_sub+="| $dir_display | $dir_lang | $count | $dir_syms | [[.code-index/$dir_enc.md]] |\n"
      for rel in $(printf '%s\n' "${files[@]}" | sort); do
        [[ -z "$rel" ]] && continue
        hot=${file_hot[$rel]}
        if [[ $hot == 1 ]]; then
          base=$(basename "$rel")
          lines=${file_lines[$rel]}; syms=${file_symbols[$rel]}
          t1_hot+="| $rel | $lines | $syms | [[.code-index/$dir_enc/$base.md]] |\n"
        fi
      done
    fi
  done

  # ORGANS: excluded dirs that have their own CODE_INDEX.md (sub-pyramids)
  local t1_organs="" _od
  for _od in $REINDEX_EXCLUDE; do
    [[ -f "$ROOT/$_od/CODE_INDEX.md" ]] && \
      t1_organs+="| ${_od}/ | [[${_od}/CODE_INDEX.md]] |\n"
  done

  {
    printf '# CODE_INDEX.md\n'
    printf '> Auto-generated by code-index-md v2. Do not edit manually.\n'
    printf '> Updated: %s\n' "$TIMESTAMP"
    printf '> Plugin-Version: %s\n' "$PLUGIN_VERSION"
    printf '> Navigation: tier-1 \xe2\x86\x92 .code-index/<dir>.md \xe2\x86\x92 .code-index/<dir>/<file>.md \xe2\x86\x92 Read offset=N limit=L (rows=L compatible)\n\n'
    [[ -n "$t1_sub" ]] && {
      printf '## SUBTREES\n| Path | Lang | Files | Symbols | Index |\n|------|------|-------|---------|-------|\n'
      printf '%b' "$t1_sub"; printf '\n'
    }
    [[ -n "$t1_organs" ]] && {
      printf '## ORGANS\n| Path | Sub-pyramid |\n|------|-------------|\n'
      printf '%b' "$t1_organs"; printf '\n'
    }
    [[ -n "$t1_hot" ]] && {
      printf '## HOT FILES\n| File | Lines | Symbols | Index |\n|------|-------|---------|-------|\n'
      printf '%b' "$t1_hot"; printf '\n'
    }
    [[ -n "$t1_inline" ]] && {
      printf '## SINGLE-FILE / ROOT\n%s' "$t1_inline"
    }
  } > "$OUTPUT.tmp"
  mv "$OUTPUT.tmp" "$OUTPUT"
  [[ $REINDEX_VERBOSE == 1 ]] && echo "REINDEX: tier-1 $OUTPUT" >&2
  return 0
}

# emit_tier2: writes .code-index/<dir_enc>.md for one directory bucket.
emit_tier2() {
  local dir="$1" dir_enc="$2" dest_root="${3:-$INDEX_DIR}"
  local rel base lines syms hot

  {
    printf '# .code-index/%s.md\n> Full symbols for: %s\n\n' "$dir_enc" "$dir"
    for rel in $(printf '%s\n' ${bucket[$dir]:-} | sort); do
      [[ -z "$rel" ]] && continue
      base=$(basename "$rel")
      lines=${file_lines[$rel]}; syms=${file_symbols[$rel]}; hot=${file_hot[$rel]}
      if [[ $hot == 1 ]]; then
        printf '## %s (%s lines) \xe2\x86\x92 HOT [[.code-index/%s/%s.md]]\n\n' \
          "$base" "$lines" "$dir_enc" "$base"
      else
        index_${file_lang[$rel]} "$ROOT/$rel"
      fi
    done
  } > "$dest_root/$dir_enc.md"
  [[ $REINDEX_VERBOSE == 1 ]] && echo "REINDEX: tier-2 $dest_root/$dir_enc.md" >&2
  return 0
}

# ── incremental path ─────────────────────────────────────────────────────────

do_incremental() {
  local rel="${FILE_PATH#$ROOT/}"
  [[ -z "${old_mlines[$rel]+x}" ]] && return 1
  [[ -f "$ROOT/$rel" ]] || return 1

  local lang lines syms hot
  lang=$(detect_lang "$rel")
  [[ -z "$lang" ]] && return 1
  lines=$(wc -l < "$ROOT/$rel")
  syms=$(index_${lang} "$ROOT/$rel" | grep -c "^- " || true)
  hot=$(compute_hot "$lang" "$lines" "$syms")

  # Load all file stats from manifest into local arrays (no find walk)
  local -A file_lines file_symbols file_lang file_hot bucket
  local mrel mdir
  for mrel in "${!old_mlines[@]}"; do
    file_lines[$mrel]="${old_mlines[$mrel]}"
    file_symbols[$mrel]="${old_msyms[$mrel]}"
    file_hot[$mrel]="${old_mhot[$mrel]}"
    file_lang[$mrel]="${old_mlang[$mrel]}"
    mdir=$(dirname "$mrel")
    case " ${bucket[$mdir]:-} " in *" $mrel "*) ;; *) bucket[$mdir]+="$mrel " ;; esac
  done
  # Override changed file entry
  file_lines[$rel]=$lines
  file_symbols[$rel]=$syms
  file_lang[$rel]=$lang
  file_hot[$rel]=$hot

  local dir dir_enc
  dir=$(dirname "$rel")
  # Ensure dirmap exists (TMP=INDEX_DIR for incremental path)
  [[ -f "$TMP/.dirmap" ]] || : > "$TMP/.dirmap"
  dir_enc=$(encode_dir "$dir")
  emit_tier2 "$dir" "$dir_enc" "$INDEX_DIR"

  if [[ $hot == 1 ]]; then
    local base
    base=$(basename "$rel")
    mkdir -p "$INDEX_DIR/$dir_enc"
    index_${lang} "$ROOT/$rel" > "$INDEX_DIR/$dir_enc/$base.md"
    [[ $REINDEX_VERBOSE == 1 ]] && echo "REINDEX: tier-3 $INDEX_DIR/$dir_enc/$base.md" >&2
  elif [[ ${old_mhot[$rel]} == 1 ]]; then
    local base
    base=$(basename "$rel")
    rm -f "$INDEX_DIR/$dir_enc/$base.md"
  fi

  awk -F'\t' -v r="$rel" -v l="$lines" -v s="$syms" -v h="$hot" -v g="$lang" \
    'BEGIN{OFS="\t"} $1==r{$2=l;$3=s;$4=h;$5=g} {print}' \
    "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

  emit_tier1
  [[ $REINDEX_VERBOSE == 1 ]] && echo "REINDEX: incremental $rel" >&2
  return 0
}

# ── full regen ───────────────────────────────────────────────────────────────

do_full_regen() {
  local TMP="$ROOT/.code-index.tmp.$$"
  trap "rm -rf '$TMP' 2>/dev/null" EXIT
  mkdir -p "$TMP"
  printf '# version: 2\npath\tlines\tsymbols\thot\tlang\n' > "$TMP/.manifest.tmp"
  : > "$TMP/.dirmap"

  local -A file_lines file_symbols file_lang file_hot bucket
  local total_files=0 total_lines=0 max_bucket=0

  # Build find exclude args from default Python environment skips plus REINDEX_EXCLUDE.
  local exclude_args=()
  local d
  for d in $REINDEX_ALL_EXCLUDES; do exclude_args+=(-not -path "*/$d/*"); done
  # Prune nested Git repositories; the selected ROOT itself remains indexable.
  local git_repo_prune=(-mindepth 1 \( -type d -exec test -e '{}/.git' \; -prune \) -o)
  local gitlink_prune=() gitlink
  while IFS= read -r gitlink; do
    [[ -n "$gitlink" ]] && gitlink_prune+=(-path "$ROOT/$gitlink" -prune -o)
  done < <(git -C "$ROOT" ls-files -s 2>/dev/null | awk '$1 == "160000" {sub(/^[^\t]*\t/, ""); print}')

  local f rel dir lang lines syms hot

  # JavaScript — recursive, skip minified and vendor
  while IFS= read -r -d '' f; do
    [[ "$f" == *.min.js || "$f" == *.min.mjs || "$f" == *.min.cjs ]] && continue
    basename "$f" | grep -qiE '^d3' && continue
    rel="${f#$ROOT/}"; dir=$(dirname "$rel"); lang=js
    lines=$(wc -l < "$f"); syms=$(index_js "$f" | grep -c "^- " || true)
    hot=$(compute_hot "$lang" "$lines" "$syms")
    file_lines[$rel]=$lines; file_symbols[$rel]=$syms; file_lang[$rel]=$lang; file_hot[$rel]=$hot
    bucket[$dir]+="$rel "
    total_files=$(( total_files + 1 )); total_lines=$(( total_lines + lines ))
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$lines" "$syms" "$hot" "$lang" >> "$TMP/.manifest.tmp"
  done < <(find "$ROOT" "${git_repo_prune[@]}" "${gitlink_prune[@]}" \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/d3js/*" \
    -not -path "*/.code-index*" "${exclude_args[@]}" -print0 | sort -z)

  # Java — recursive, skip test/generated
  while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"; dir=$(dirname "$rel"); lang=java
    lines=$(wc -l < "$f"); syms=$(index_java "$f" | grep -c "^- " || true)
    hot=$(compute_hot "$lang" "$lines" "$syms")
    file_lines[$rel]=$lines; file_symbols[$rel]=$syms; file_lang[$rel]=$lang; file_hot[$rel]=$hot
    bucket[$dir]+="$rel "
    total_files=$(( total_files + 1 )); total_lines=$(( total_lines + lines ))
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$lines" "$syms" "$hot" "$lang" >> "$TMP/.manifest.tmp"
  done < <(find "$ROOT" "${git_repo_prune[@]}" "${gitlink_prune[@]}" -name "*.java" \
    -not -path "*/test/*" -not -path "*/androidTest/*" \
    -not -path "*/.git/*" -not -path "*/build/*" -not -path "*/.code-index*" \
    "${exclude_args[@]}" -print0 | sort -z)

  # MD — maxdepth 3, skip self and vendor
  while IFS= read -r -d '' f; do
    [[ "$f" == "$OUTPUT" ]] && continue
    rel="${f#$ROOT/}"; dir=$(dirname "$rel"); lang=md
    lines=$(wc -l < "$f"); syms=$(index_md "$f" | grep -c "^- " || true)
    hot=$(compute_hot "$lang" "$lines" "$syms")
    file_lines[$rel]=$lines; file_symbols[$rel]=$syms; file_lang[$rel]=$lang; file_hot[$rel]=$hot
    bucket[$dir]+="$rel "
    total_files=$(( total_files + 1 )); total_lines=$(( total_lines + lines ))
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$lines" "$syms" "$hot" "$lang" >> "$TMP/.manifest.tmp"
  done < <(find "$ROOT" "${git_repo_prune[@]}" "${gitlink_prune[@]}" -maxdepth 3 -name "*.md" \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/d3js/*" \
    -not -path "*/.code-index*" -not -path "*/.pytest_cache/*" \
    "${exclude_args[@]}" -print0 | sort -z)

  # Python — recursive, skip migrations and cache
  while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"; dir=$(dirname "$rel"); lang=py
    lines=$(wc -l < "$f"); syms=$(index_py "$f" | grep -c "^- " || true)
    hot=$(compute_hot "$lang" "$lines" "$syms")
    file_lines[$rel]=$lines; file_symbols[$rel]=$syms; file_lang[$rel]=$lang; file_hot[$rel]=$hot
    bucket[$dir]+="$rel "
    total_files=$(( total_files + 1 )); total_lines=$(( total_lines + lines ))
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$lines" "$syms" "$hot" "$lang" >> "$TMP/.manifest.tmp"
  done < <(find "$ROOT" "${git_repo_prune[@]}" "${gitlink_prune[@]}" -name "*.py" \
    -not -path "*/.git/*" -not -path "*/migrations/*" -not -path "*/__pycache__/*" \
    -not -path "*/.code-index*" \
    "${exclude_args[@]}" -print0 | sort -z)

  # Shell — recursive, using function declarations as symbols
  while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"; dir=$(dirname "$rel"); lang=sh
    lines=$(wc -l < "$f"); syms=$(index_sh "$f" | grep -c "^- " || true)
    hot=$(compute_hot "$lang" "$lines" "$syms")
    file_lines[$rel]=$lines; file_symbols[$rel]=$syms; file_lang[$rel]=$lang; file_hot[$rel]=$hot
    bucket[$dir]+="$rel "
    total_files=$(( total_files + 1 )); total_lines=$(( total_lines + lines ))
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$lines" "$syms" "$hot" "$lang" >> "$TMP/.manifest.tmp"
  done < <(find "$ROOT" "${git_repo_prune[@]}" "${gitlink_prune[@]}" -name "*.sh" \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.code-index*" \
    "${exclude_args[@]}" -print0 | sort -z)

  # Rebucket deep dirs into ancestor at MAX_SUBTREE_DEPTH (defense against embedded repos)
  if [[ -n "${MAX_SUBTREE_DEPTH:-}" ]] && (( MAX_SUBTREE_DEPTH > 0 )); then
    declare -A rebucket
    local _depth _ancestor
    for dir in "${!bucket[@]}"; do
      _depth=$(awk -F/ '{print NF}' <<< "$dir")
      if (( _depth > MAX_SUBTREE_DEPTH )); then
        _ancestor=$(cut -d/ -f1-$MAX_SUBTREE_DEPTH <<< "$dir")
        rebucket[$_ancestor]+="${bucket[$dir]}"
      else
        rebucket[$dir]+="${bucket[$dir]}"
      fi
    done
    for k in "${!bucket[@]}"; do unset 'bucket[$k]'; done
    for k in "${!rebucket[@]}"; do bucket[$k]="${rebucket[$k]}"; done
    unset rebucket
  fi

  # small_project check
  local cnt_
  for dir in "${!bucket[@]}"; do
    cnt_=$(wc -w <<< "${bucket[$dir]:-}")
    [[ $cnt_ -gt $max_bucket ]] && max_bucket=$cnt_
  done

  if [[ $total_files -le 10 && $max_bucket -lt $MIN_DIR_FILES && $total_lines -lt $FLAT_LINES_THRESHOLD ]]; then
    {
      printf '# CODE_INDEX.md\n'
      printf '> Auto-generated by code-index-md. Do not edit manually.\n'
      printf '> Updated: %s\n' "$TIMESTAMP"
      printf '> Plugin-Version: %s\n' "$PLUGIN_VERSION"
      printf '> Usage: find symbol \xe2\x86\x92 line number \xe2\x86\x92 `Read file offset=N limit=L` (rows=L compatible)\n'
      printf '\n'
      for rel in "${!file_lang[@]}"; do [[ "${file_lang[$rel]}" == "js" ]]   && index_js   "$ROOT/$rel"; done
      for rel in "${!file_lang[@]}"; do [[ "${file_lang[$rel]}" == "sh" ]]   && index_sh   "$ROOT/$rel"; done
      for rel in "${!file_lang[@]}"; do [[ "${file_lang[$rel]}" == "java" ]] && index_java "$ROOT/$rel"; done
      for rel in "${!file_lang[@]}"; do [[ "${file_lang[$rel]}" == "md" ]]   && index_md   "$ROOT/$rel"; done
      for rel in "${!file_lang[@]}"; do [[ "${file_lang[$rel]}" == "py" ]]   && index_py   "$ROOT/$rel"; done
    } > "$OUTPUT"
    mv "$TMP/.manifest.tmp" "$TMP/.manifest"
    local OLD="$ROOT/.code-index.old.$$"
    [[ -e "$INDEX_DIR" ]] && mv "$INDEX_DIR" "$OLD"
    mv "$TMP" "$INDEX_DIR"
    rm -rf "$OLD"
    printf 'CODE_INDEX.md updated flat (%s)\n' "$TIMESTAMP" >&2
    trap - EXIT
    return 0
  fi

  # Pyramid emit: tier-2 + tier-3 into TMP
  for dir in $(printf '%s\n' "${!bucket[@]}" | sort); do
    local files=()
    IFS=' ' read -ra files <<< "${bucket[$dir]:-}"
    local count=0
    for rel in "${files[@]}"; do [[ -n "$rel" ]] && count=$(( count + 1 )); done

    if [[ $count -ge $MIN_DIR_FILES ]]; then
      local dir_enc; dir_enc=$(encode_dir "$dir")
      mkdir -p "$TMP/$dir_enc"
      emit_tier2 "$dir" "$dir_enc" "$TMP"

      for rel in "${files[@]}"; do
        [[ -z "$rel" ]] && continue
        if [[ ${file_hot[$rel]} == 1 ]]; then
          local base; base=$(basename "$rel")
          index_${file_lang[$rel]} "$ROOT/$rel" > "$TMP/$dir_enc/$base.md"
          [[ $REINDEX_VERBOSE == 1 ]] && echo "REINDEX: tier-3 $dir_enc/$base.md" >&2
        fi
      done
    fi
  done

  mv "$TMP/.manifest.tmp" "$TMP/.manifest"

  # Atomic .code-index swap then tier-1 (tier-2/3 in place before tier-1 references them)
  local OLD="$ROOT/.code-index.old.$$"
  [[ -e "$INDEX_DIR" ]] && mv "$INDEX_DIR" "$OLD"
  mv "$TMP" "$INDEX_DIR"
  TMP="$INDEX_DIR"   # encode_dir writes to $TMP/.dirmap; update after swap
  rm -rf "$OLD"

  emit_tier1
  printf 'CODE_INDEX.md updated (%s)\n' "$TIMESTAMP" >&2
  trap - EXIT
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  # Bail early if INDEX_DIR exists but is not writable (e.g. stale root-owned dir)
  if [[ -e "$INDEX_DIR" ]] && [[ ! -w "$INDEX_DIR" ]]; then
    printf 'REINDEX: skipping — %s not writable (fix: sudo chown -R %s %s)\n' \
      "$INDEX_DIR" "$(whoami)" "$ROOT/.code-index" >&2
    exit 0
  fi
  mkdir -p "$INDEX_DIR"
  local LOCK_ROOT="${TMPDIR:-/tmp}"
  local LOCK_ID
  LOCK_ID=$(printf '%s' "$ROOT" | cksum | awk '{print $1}')
  exec 9>"$LOCK_ROOT/code-index-md-$LOCK_ID.lock"
  flock 9
  rm -f "$INDEX_DIR/.lock" 2>/dev/null || true
  # Prune orphaned tmp/old dirs from prior crashes (safe under lock)
  rm -rf "$ROOT"/.code-index.tmp.* "$ROOT"/.code-index.old.* 2>/dev/null || true

  # Stdin guard: read FILE_PATH only from hook context (not terminal + jq present)
  local FILE_PATH=""
  if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
    local INPUT; INPUT=$(cat)
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
    FILE_PATH="${FILE_PATH:-}"
  fi

  # Pass 0: load prior manifest into old_m* arrays
  local -A old_mlines old_msyms old_mhot old_mlang
  local TMP="$INDEX_DIR"   # used by encode_dir in incremental path
  if [[ -f "$MANIFEST" ]] && [[ "$(head -1 "$MANIFEST")" == "# version: 2" ]]; then
    local mp ml ms mh mg
    while IFS=$'\t' read -r mp ml ms mh mg; do
      [[ "$mp" =~ ^# || "$mp" == "path" ]] && continue
      old_mlines["$mp"]="$ml"; old_msyms["$mp"]="$ms"
      old_mhot["$mp"]="$mh";   old_mlang["$mp"]="$mg"
    done < "$MANIFEST"
  fi

  # Try incremental path first
  if [[ -n "$FILE_PATH" && "${#old_mlines[@]}" -gt 0 ]]; then
    do_incremental && return 0
  fi

  # Full regen (TMP will be set as local inside do_full_regen, shadowing main's TMP)
  do_full_regen
}

main
