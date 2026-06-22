#!/usr/bin/env python3
"""Validate the packaged Claude plugin and Codex skill layout."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = [
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    ".claude/commands/code-index-md.md",
    "hooks/reindex.sh",
    "hooks/session-start.sh",
    "skills/code-index-md/SKILL.md",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: str) -> dict:
    try:
        return json.loads((ROOT / path).read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{path} is invalid JSON: {exc}")


def require_file(path: str) -> None:
    if not (ROOT / path).is_file():
        fail(f"missing {path}")


def path_from_plugin_ref(ref: str) -> str | None:
    match = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^"]+)', ref)
    return match.group(1) if match else None


def main() -> None:
    for path in REQUIRED_FILES:
        require_file(path)

    plugin = load_json(".claude-plugin/plugin.json")
    marketplace = load_json(".claude-plugin/marketplace.json")

    if plugin.get("name") != "code-index-md":
        fail(".claude-plugin/plugin.json name must be code-index-md")
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(plugin.get("version", ""))):
        fail(".claude-plugin/plugin.json version must be semver")
    if plugin.get("commands") != "./.claude/commands":
        fail(".claude-plugin/plugin.json commands must point to ./.claude/commands")

    hooks = plugin.get("hooks")
    if not isinstance(hooks, dict):
        fail(".claude-plugin/plugin.json hooks must be an object")

    session_hooks = hooks.get("SessionStart", [])
    post_hooks = hooks.get("PostToolUse", [])
    if not session_hooks or not post_hooks:
        fail("plugin must define SessionStart and PostToolUse hooks")

    post_matchers = [entry.get("matcher") for entry in post_hooks if isinstance(entry, dict)]
    if "Edit|Write" not in post_matchers:
        fail("PostToolUse hook must match Edit|Write")

    commands = []
    for group in [*session_hooks, *post_hooks]:
        for hook in group.get("hooks", []):
            command = hook.get("command", "")
            commands.append(command)
            ref = path_from_plugin_ref(command)
            if ref:
                require_file(ref)

    if not any("hooks/session-start.sh" in command for command in commands):
        fail("SessionStart must run hooks/session-start.sh")
    if not any("hooks/reindex.sh" in command for command in commands):
        fail("PostToolUse must run hooks/reindex.sh")

    plugins = marketplace.get("plugins", [])
    if not any(item.get("name") == "code-index-md" for item in plugins if isinstance(item, dict)):
        fail(".claude-plugin/marketplace.json must list code-index-md")

    skill = (ROOT / "skills/code-index-md/SKILL.md").read_text(encoding="utf-8")
    if not skill.startswith("---\n") or "\n---\n" not in skill[4:]:
        fail("skills/code-index-md/SKILL.md must have YAML frontmatter")
    if "CODE_INDEX.md" not in skill:
        fail("skills/code-index-md/SKILL.md must mention CODE_INDEX.md")

    print("Package validation OK.")


if __name__ == "__main__":
    main()
