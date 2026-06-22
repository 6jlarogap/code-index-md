# code-index-skill-upgrade Chain

Status: planned
Repo: /home/vdrzd/src/code-index-md
Branch: main
Remote: origin https://github.com/6jlarogap/code-index-md.git

## Objective

Upgrade code-index-md from a Claude-only plugin into a reusable code-index navigation package that works cleanly for Codex skill usage while preserving the existing Claude plugin flow.

The implementation must keep `hooks/reindex.sh` usable by current plugin installs, make the skill instructions portable for other repositories, add validation that catches packaging regressions, and push the completed source state to GitHub.

## Worker Rules

- Use one serial worker for this full queue.
- Before edits, inspect `git status --short`, `README.md`, `CODE_INDEX.md`, `.claude-plugin/plugin.json`, `.github/workflows/test-plugin-install.yml`, `hooks/reindex.sh`, `hooks/session-start.sh`, and `skills/code-index-md/SKILL.md`.
- If local agent instructions are added later, read them before continuing.
- Do not revert unrelated user changes.
- Keep Claude plugin compatibility unless a slice explicitly changes the plugin contract.
- Preserve generated `.code-index/` behavior; do not commit temporary `.code-index.tmp.*` or `.code-index.old.*` directories.
- Each completed slice must run its local checks, update `CODE_INDEX.md` through `bash hooks/reindex.sh` when indexed docs/scripts changed, commit with the slice slug in the message, and record a handoff note in this chain file.
- If a check, commit, or push is blocked, record the exact command and failure under the slice handoff, then stop unless the next slice is explicitly independent.

## Ordered Slug Queue

1. `index-baseline-validation`
2. `index-portable-reindex`
3. `index-codex-skill`
4. `index-docs-install`
5. `index-ci-release`

Stop rule: stop at the first failed slice unless the failure is only documentation wording and the next slice does not depend on it.

## Slice: index-baseline-validation

Status: completed
Scope:
- Audit the current packaging contract and CI workflow.
- Fix the existing validation mismatch where `.github/workflows/test-plugin-install.yml` expects `hooks/hooks.json` but the repo does not contain it, either by adding the missing manifest if it is genuinely part of the plugin contract or by updating CI to validate the actual `.claude-plugin/plugin.json` hook definitions.
- Add a small local validation script only if it reduces duplication with CI.

Out of scope:
- No generator rewrite.
- No Codex skill content beyond baseline notes.

Completion criteria:
- `bash hooks/reindex.sh` succeeds from the repo root.
- The CI validation logic can run locally, or equivalent commands are documented in the handoff.
- `git status --short` shows only intentional files before commit.
- Commit message includes `index-baseline-validation`.

Next slug to print: `index-portable-reindex`

Handoff:
- status: completed
- commit: `6b3c6df`
- durable ledger decision: commit `chains/code-index-skill-upgrade.md` as project state because all later slices depend on durable per-slice handoffs; it is not kept local-only.
- files changed: `.github/workflows/test-plugin-install.yml`, `.gitignore`, `CODE_INDEX.md`, `chains/code-index-skill-upgrade.md`, `scripts/validate-package.py`
- migrations/deploy: not applicable
- checks run:
  - `python3 scripts/validate-package.py` - passed
  - `bash hooks/reindex.sh` - passed
- failures: none
- assumptions carried forward: `.code-index/`, `.code-index.tmp.*`, and `.code-index.old.*` are generated runtime state and must stay uncommitted; validation should follow `.claude-plugin/plugin.json`, not a nonexistent `hooks/hooks.json`.
- next slug: `index-portable-reindex`

## Slice: index-portable-reindex

Status: completed
Depends on: `index-baseline-validation`
Scope:
- Make the reindex flow more portable across Claude and Codex contexts.
- Support project-root discovery through `CODE_INDEX_ROOT`, `CODEX_PROJECT_ROOT`, `CLAUDE_PROJECT_ROOT`, then `pwd`, without breaking existing `CLAUDE_PROJECT_ROOT` installs.
- Review whether the Blagodarie `scripts/code_index.py` offset/rows style should be ported, whether the current Bash pyramid should remain canonical, or whether both formats need a compatibility bridge. Choose the smallest change that improves Codex usability without destabilizing current users.
- Keep configurable exclusions (`REINDEX_EXCLUDE`, defaults, max subtree depth) working.
- Add or update smoke tests/examples that cover JS, Python, Java, and Markdown indexing.

Out of scope:
- No marketplace/publishing docs except notes needed for validation.
- No push unless all later slices finish.

Completion criteria:
- Existing plugin reindex path still works: `CLAUDE_PROJECT_ROOT=. bash hooks/reindex.sh`.
- Generic path works: `CODE_INDEX_ROOT=. bash hooks/reindex.sh`.
- Generated `CODE_INDEX.md` remains useful for `offset=N limit=L` source reads.
- Commit message includes `index-portable-reindex`.

Next slug to print: `index-codex-skill`

Handoff:
- status: completed
- commit: `5b12a78`
- files changed: `CODE_INDEX.md`, `chains/code-index-skill-upgrade.md`, `hooks/reindex.sh`, `hooks/session-start.sh`, `scripts/smoke-reindex.sh`
- migrations/deploy: not applicable
- checks run:
  - `CLAUDE_PROJECT_ROOT=. bash hooks/reindex.sh` - passed
  - `CODE_INDEX_ROOT=. bash hooks/reindex.sh` - passed
  - `bash scripts/smoke-reindex.sh` - passed
  - `python3 scripts/validate-package.py` - passed
- failures: none
- assumptions carried forward: root discovery order is `CODE_INDEX_ROOT`, `CODEX_PROJECT_ROOT`, `CLAUDE_PROJECT_ROOT`, then `pwd`; Bash pyramid output remains canonical; the Blagodarie-style offset/rows compatibility improvement is limited to documenting `rows=L` as equivalent to `limit=L` in the generated navigation header so existing `offset=N limit=L` readers are not destabilized.
- next slug: `index-codex-skill`

## Slice: index-codex-skill

Status: completed
Depends on: `index-portable-reindex`
Scope:
- Use the `skill-creator` guidance before editing skill files.
- Update `skills/code-index-md/SKILL.md` so it is a valid, concise Codex skill and still usable as Claude-facing guidance.
- Add `skills/code-index-md/agents/openai.yaml` if appropriate for Codex skill discovery.
- Ensure the skill teaches the agent to read `CODE_INDEX.md`, follow tier-1/tier-2/tier-3 indexes, read exact fragments, regenerate the index after edits, and avoid unsupported/generated paths.
- Keep the frontmatter trigger broad enough for "code index", "CODE_INDEX.md", "line-number index", "navigate repo without loading full files", and "rebuild code index".

Out of scope:
- No large README rewrite unless required to make install instructions correct.

Completion criteria:
- Skill frontmatter has only required fields unless the active skill format requires more.
- Any generated `agents/openai.yaml` matches the final skill body.
- Run available skill validation if present in the environment; otherwise record that it was unavailable.
- Commit message includes `index-codex-skill`.

Next slug to print: `index-docs-install`

Handoff:
- status: completed
- commit: `2745194`
- files changed: `CODE_INDEX.md`, `chains/code-index-skill-upgrade.md`, `skills/code-index-md/SKILL.md`, `skills/code-index-md/agents/openai.yaml`
- migrations/deploy: not applicable
- checks run:
  - `python3 /home/vdrzd/.codex/skills/.system/skill-creator/scripts/generate_openai_yaml.py skills/code-index-md --interface 'display_name=Code Index MD' --interface 'short_description=Navigate repositories with CODE_INDEX.md' --interface 'default_prompt=Use $code-index-md to inspect this repository with CODE_INDEX.md before opening full source files.'` - passed
  - `python3 /home/vdrzd/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/code-index-md` - passed
  - `python3 scripts/validate-package.py` - passed
  - `bash hooks/reindex.sh` - passed
- failures: initial direct execution of `/home/vdrzd/.codex/skills/.system/skill-creator/scripts/generate_openai_yaml.py ...` failed with `Permission denied`; reran successfully through `python3`.
- assumptions carried forward: Codex skill frontmatter should remain limited to `name` and `description`; `agents/openai.yaml` is appropriate because this repo distributes the skill, and it contains only UI metadata.
- next slug: `index-docs-install`

## Slice: index-docs-install

Status: completed
Depends on: `index-codex-skill`
Scope:
- Update `README.md` with separate Claude plugin, Codex skill, and manual install paths.
- Document root variables and exclusions: `CODE_INDEX_ROOT`, `CODEX_PROJECT_ROOT`, `CLAUDE_PROJECT_ROOT`, `REINDEX_EXCLUDE`, `MAX_SUBTREE_DEPTH`.
- Show a minimal Codex instruction snippet for project `AGENTS.md`.
- Make examples match the actual output format after previous slices.

Out of scope:
- No CI expansion beyond docs validation unless required.

Completion criteria:
- README install commands are copy-pasteable.
- `CODE_INDEX.md` is regenerated after README edits.
- Commit message includes `index-docs-install`.

Next slug to print: `index-ci-release`

Handoff:
- status: completed
- commit: `1ba4d68`
- files changed: `README.md`, `CODE_INDEX.md`, `chains/code-index-skill-upgrade.md`
- migrations/deploy: not applicable
- checks run:
  - `python3 scripts/validate-package.py` - passed
  - `bash scripts/smoke-reindex.sh` - passed
  - `bash hooks/reindex.sh` - passed
- failures: none
- assumptions carried forward: the requested Codex `AGENTS.md` instruction is documented as a copyable README snippet rather than adding a repo-local `AGENTS.md`, because this repository does not need new local agent rules for itself.
- next slug: `index-ci-release`

## Slice: index-ci-release

Status: completed
Depends on: `index-docs-install`
Scope:
- Update GitHub Actions validation to check the Claude plugin files, Codex skill files, and representative reindex runs.
- Run the local equivalent of CI.
- Review versioning in `.claude-plugin/plugin.json`; bump patch/minor if the packaging contract changed.
- Push commits to `origin main` if the full queue passes and the user has not requested a branch/PR-only flow.
- If a PR is still wanted despite direct ownership, create a branch and push it instead, then record the branch name.

Out of scope:
- No production deployment.

Completion criteria:
- `git status --short` is clean after commit.
- `git log --oneline -5` shows the slice commits.
- Push succeeds, or exact push blocker is recorded.
- Final handoff lists completed slugs, commit hashes, checks, changed files, push status, and any follow-up.

Next slug to print: complete

Handoff:
- status: completed
- commit: pending
- files changed: `.github/workflows/test-plugin-install.yml`, `CODE_INDEX.md`, `chains/code-index-skill-upgrade.md`, `scripts/validate-package.py`
- migrations/deploy: not applicable
- checks run:
  - `python3 scripts/validate-package.py` - passed
  - `bash scripts/smoke-reindex.sh` - passed
  - `CLAUDE_PROJECT_ROOT=. bash hooks/reindex.sh` - passed
  - `CODEX_PROJECT_ROOT=. bash hooks/reindex.sh` - passed
  - `CODE_INDEX_ROOT=. bash hooks/reindex.sh` - passed
- failures: none
- version review: `.claude-plugin/plugin.json` remains at `2.0.0`; no patch/minor bump because the Claude plugin command and hook contract stayed compatible.
- push status: pending until this slice is committed.
- assumptions carried forward: GitHub Actions can use local `scripts/validate-package.py` and `scripts/smoke-reindex.sh` as the same checks run locally.
- next slug: complete
