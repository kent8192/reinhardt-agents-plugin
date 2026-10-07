#!/usr/bin/env python3
"""Run read-only anti-pattern checks on files reported by edit hook events."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def edited_paths(raw: str, legacy: str = "") -> list[Path]:
    """Prefer stdin events; retain the legacy flat TOOL_INPUT contract."""
    value = raw if raw.strip() else legacy
    try:
        payload = json.loads(value)
    except (json.JSONDecodeError, ValueError):
        return []
    if not isinstance(payload, dict):
        return []
    tool_input = payload.get("tool_input", payload)
    candidates = []
    if isinstance(tool_input, dict):
        for key in ("file_path", "path"):
            if isinstance(tool_input.get(key), str):
                candidates.append(tool_input[key])
        patch = tool_input.get("patch", tool_input.get("input"))
    else:
        patch = tool_input
    if isinstance(patch, str) and patch.startswith("*** Begin Patch"):
        candidates.extend(
            re.findall(r"^\*\*\* (?:Add File|Update File|Move to): (.+)$", patch, re.M)
        )
    cwd = payload.get("cwd")
    base = Path(cwd) if isinstance(cwd, str) and Path(cwd).is_absolute() else Path.cwd()
    paths = []
    for candidate in candidates:
        if not candidate or "\x00" in candidate:
            continue
        path = Path(candidate)
        if not path.is_absolute():
            path = base / path
        if path.suffix != ".rs" and path.name != "Cargo.toml":
            continue
        if path not in paths and path.is_file():
            paths.append(path)
    return paths


def scan(path: Path, rules: Path) -> None:
    if path.name == "mod.rs":
        print(
            f"ERROR [reinhardt-no-mod-rs]: {path}: Reinhardt requires "
            "'module.rs' plus a 'module/' directory.",
            file=sys.stderr,
        )
    semgrep = shutil.which("semgrep")
    docker = shutil.which("docker")
    if semgrep:
        command = [
            semgrep, "scan", "--config", str(rules),
            "--no-git-ignore", "--metrics", "off", "--quiet", str(path),
        ]
    elif docker:
        absolute = path.resolve()
        command = [
            docker, "run", "--rm",
            "-v", f"{absolute.parent}:/target:ro",
            "-v", f"{rules.parent.resolve()}:/rules:ro",
            "semgrep/semgrep", "semgrep", "scan",
            "--config", f"/rules/{rules.name}",
            "--no-git-ignore", "--metrics", "off", "--quiet",
            f"/target/{absolute.name}",
        ]
    else:
        print("WARNING: semgrep not found (local or docker); skipping check.", file=sys.stderr)
        return
    try:
        subprocess.run(command, stdout=sys.stderr, stderr=sys.stderr, check=False)
    except OSError as error:
        print(f"WARNING: anti-pattern scanner could not start: {error}", file=sys.stderr)


def main() -> int:
    paths = edited_paths(sys.stdin.read(), os.environ.get("TOOL_INPUT", ""))
    root = Path(
        os.environ.get("CLAUDE_PLUGIN_ROOT")
        or os.environ.get("PLUGIN_ROOT")
        or Path(__file__).resolve().parents[2]
    )
    rules = root / "hooks/semgrep/reinhardt-antipatterns.yml"
    for path in paths:
        scan(path, rules)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
