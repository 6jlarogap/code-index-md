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
    "skills/code-index-md/agents/openai.yaml",
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


def parse_skill_frontmatter(skill: str) -> dict[str, str]:
    match = re.match(r"^---\n(.*?)\n---\n", skill, re.DOTALL)
    if not match:
        fail("skills/code-index-md/SKILL.md must have YAML frontmatter")

    fields = {}
    for line in match.group(1).splitlines():
        if not line.strip():
            continue
        if ":" not in line:
            fail(f"invalid skill frontmatter line: {line}")
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip().strip('"')
    return fields


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
    if ((ROOT / "hooks/reindex.sh").stat().st_mode & 0o111) == 0:
        fail("hooks/reindex.sh must be executable")
    if ((ROOT / "hooks/session-start.sh").stat().st_mode & 0o111) == 0:
        fail("hooks/session-start.sh must be executable")

    plugins = marketplace.get("plugins", [])
    if not any(item.get("name") == "code-index-md" for item in plugins if isinstance(item, dict)):
        fail(".claude-plugin/marketplace.json must list code-index-md")

    skill = (ROOT / "skills/code-index-md/SKILL.md").read_text(encoding="utf-8")
    frontmatter = parse_skill_frontmatter(skill)
    if set(frontmatter) != {"name", "description"}:
        fail("skill frontmatter must contain only name and description")
    if frontmatter["name"] != "code-index-md":
        fail("skill frontmatter name must be code-index-md")
    description = frontmatter["description"]
    for trigger in ["CODE_INDEX.md", "code index", "line-number index", "rebuilding a code index"]:
        if trigger not in description:
            fail(f"skill description must include trigger: {trigger}")
    for required in ["CODE_INDEX.md", ".code-index/", "offset=127 limit=45", "bash hooks/reindex.sh"]:
        if required not in skill:
            fail(f"skills/code-index-md/SKILL.md must mention {required}")

    openai_yaml = (ROOT / "skills/code-index-md/agents/openai.yaml").read_text(encoding="utf-8")
    for required in [
        'display_name: "Code Index MD"',
        'short_description: "Navigate repositories with CODE_INDEX.md"',
        'default_prompt: "Use $code-index-md',
    ]:
        if required not in openai_yaml:
            fail(f"agents/openai.yaml must include {required}")

    if "CODE_INDEX.md" not in (ROOT / ".claude/commands/code-index-md.md").read_text(encoding="utf-8"):
        fail(".claude/commands/code-index-md.md must mention CODE_INDEX.md")

    if "CODE_INDEX.md" not in (ROOT / "README.md").read_text(encoding="utf-8"):
        fail("README.md must mention CODE_INDEX.md")

    print("Package validation OK.")


if __name__ == "__main__":
    main()
