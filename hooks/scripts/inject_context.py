#!/usr/bin/env python3
"""Inject concise Reinhardt application context into agent hook events."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11: hooks must fail open.
    raise SystemExit(0)


DEFAULT_FEATURES = {
    "standard",
    "minimal",
    "core",
    "routing",
    "di",
    "server",
    "database",
    "db-postgres",
    "rest",
    "auth",
    "middleware",
    "sessions",
    "pages",
}
TOKEN_CHARACTER = r"A-Za-z0-9_-"
TOOL_PREFIX_CHARACTER = r"A-Za-z0-9_.\-/\\"


def load_toml(path: Path) -> dict | None:
    try:
        with path.open("rb") as manifest:
            return tomllib.load(manifest)
    except (OSError, tomllib.TOMLDecodeError):
        return None


def find_workspace(start: Path) -> dict:
    for directory in (start, *start.parents):
        manifest = load_toml(directory / "Cargo.toml")
        if manifest is not None and "workspace" in manifest:
            return manifest
    return {}


def runtime_dependencies(manifest: dict):
    yield from manifest.get("dependencies", {}).items()
    for target in manifest.get("target", {}).values():
        if isinstance(target, dict):
            yield from target.get("dependencies", {}).items()


def dependency_table(value) -> dict:
    if isinstance(value, str):
        return {"version": value}
    return value if isinstance(value, dict) else {}


def inherited_dependency(
    name: str, dependency: dict, workspace: dict
) -> dict | None:
    if dependency.get("workspace") is not True:
        return dependency

    inherited = workspace.get("workspace", {}).get("dependencies", {}).get(name)
    if inherited is None:
        return None

    inherited = dependency_table(inherited)
    effective = inherited | dependency
    effective["features"] = [
        *inherited.get("features", []),
        *dependency.get("features", []),
    ]
    inherited_default = inherited.get(
        "default-features", inherited.get("default_features")
    )
    member_default = dependency.get(
        "default-features", dependency.get("default_features")
    )
    if inherited_default is True or member_default is True:
        effective["default-features"] = True
    elif inherited_default is False or member_default is False:
        effective["default-features"] = False
    return effective


def dependency_metadata(manifest: dict, workspace: dict) -> dict | None:
    version = None
    saw_path = False
    saw_git = False
    default_features = True
    features: set[str] = set()
    found = False

    for name, raw_dependency in runtime_dependencies(manifest):
        dependency = inherited_dependency(
            name, dependency_table(raw_dependency), workspace
        )
        if dependency is None:
            continue
        if dependency.get("package", name) not in {"reinhardt", "reinhardt-web"}:
            continue

        found = True
        if version is None and isinstance(dependency.get("version"), str):
            version = dependency["version"]
        saw_path |= "path" in dependency
        saw_git |= "git" in dependency

        declared_default = dependency.get(
            "default-features", dependency.get("default_features")
        )
        if declared_default is not None:
            default_features = bool(declared_default)
        features.update(
            feature
            for feature in dependency.get("features", [])
            if isinstance(feature, str)
        )

    if not found:
        return None
    if default_features or "standard" in features:
        features.update(DEFAULT_FEATURES)
    source = "path" if saw_path else "git" if saw_git else "unknown"
    return {
        "version": version or source,
        "default_features": default_features,
        "features": features,
    }


def first_value_object(pairs):
    result = {}
    for key, value in pairs:
        result.setdefault(key, value)
    return result


def parse_hook_input(raw: str) -> dict | None:
    if not raw.strip():
        return {}
    try:
        value = json.loads(raw, object_pairs_hook=first_value_object)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    return value if isinstance(value, dict) else None


def string_field(payload: dict, name: str) -> str:
    value = payload.get(name)
    return value if isinstance(value, str) else ""


def number_field(payload: dict, name: str, parent: str | None = None):
    owner = payload.get(parent, {}) if parent else payload
    if not isinstance(owner, dict):
        return None
    value = owner.get(name)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value
    return None


def sanitized_pieces(value: str):
    for character in value:
        if ord(character) < 32 or ord(character) == 127:
            continue
        yield f"\\{character}" if character in {'\\', '"'} else character


def sanitize(value: str) -> str:
    return "".join(sanitized_pieces(value))


def sanitize_bounded(value: str, max_bytes: int) -> str:
    pieces = list(sanitized_pieces(value))
    if sum(len(piece.encode()) for piece in pieces) <= max_bytes:
        return "".join(pieces)

    output = []
    used = 0
    for piece in pieces:
        size = len(piece.encode())
        if used + size > max_bytes - 3:
            break
        output.append(piece)
        used += size
    return "".join(output) + "..."


def bounded_features(features: set[str], max_items=20, max_bytes=512) -> str:
    values = sorted(features)
    output: list[str] = []
    for index, value in enumerate(values):
        remaining = len(values) - index - 1
        if index >= max_items:
            return f"{', '.join(output)}, ... (+{len(values) - index} more)"

        candidate = ", ".join((*output, value))
        suffix = f", ... (+{remaining} more)" if remaining else ""
        if len(sanitize(candidate + suffix).encode()) > max_bytes:
            truncated = f"{', '.join(output)}, ... (+{len(values) - index} more)"
            return truncated.lstrip(", ")
        output.append(value)
    return ", ".join(output)


def application_metadata() -> dict | None:
    manifest_path = Path("Cargo.toml")
    if not manifest_path.is_file() or not Path("src/bin/manage.rs").is_file():
        return None
    manifest = load_toml(manifest_path)
    if manifest is None:
        return None
    try:
        metadata = dependency_metadata(manifest, find_workspace(Path.cwd()))
    except (AttributeError, TypeError):
        return None
    if metadata is None:
        return None

    features = metadata["features"]
    metadata["feature_text"] = bounded_features(features)
    metadata["database"] = next(
        (
            value
            for feature, value in (
                ("db-postgres", "postgres"),
                ("db-mysql", "mysql"),
                ("db-sqlite", "sqlite"),
                ("db-cockroachdb", "cockroachdb"),
                ("database", "configured (check settings)"),
            )
            if feature in features
        ),
        "none",
    )
    auth = [
        label
        for feature, label in (
            ("auth-jwt", "jwt"),
            ("auth-session", "session"),
            ("auth-oauth", "oauth"),
            ("auth-token", "token"),
            ("auth", "auth (default)"),
        )
        if feature in features
    ]
    metadata["auth"] = ", ".join(auth) or "none"
    apps = Path("src/apps")
    metadata["app_count"] = (
        sum(path.is_dir() for path in apps.iterdir()) if apps.is_dir() else 0
    )
    return metadata


def render_baseline(metadata: dict) -> str:
    default_features = str(metadata["default_features"]).lower()
    return "\n".join(
        (
            "(reinhardt-application-context",
            '  :kind "baseline"',
            '  :project-type "reinhardt-web application"',
            f'  :reinhardt-version "{sanitize_bounded(metadata["version"], 128)}"',
            f"  :default-features {default_features}",
            f'  :features "{sanitize(metadata["feature_text"])}"',
            f'  :db-backend "{sanitize(metadata["database"])}"',
            f'  :auth-method "{sanitize(metadata["auth"])}"',
            f'  :app-count {metadata["app_count"]}',
            '  :skills "scaffolding, architecture, modeling, api-development, pages, testing, dependency-injection, authentication, authorization, admin, migration, configuration, lint, macros, signals"',
            '  :guidance "Inspect Cargo.toml and the application structure before editing. Use the bundled Reinhardt skills that apply, follow guidance for the detected Reinhardt version, and run relevant validation.")',
        )
    )


def list_apps() -> list[str]:
    root = Path("src/apps")
    if not root.is_dir():
        return []
    return sorted(path.name for path in root.iterdir() if path.is_dir())


def ascii_lower(value: str) -> str:
    return value.translate(
        str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")
    )


def matching_apps(text: str, mode: str) -> list[str]:
    if mode == "prompt":
        text = ascii_lower(text)
    else:
        logical_cwd = os.environ.get("PWD", str(Path.cwd())).rstrip("/")
        text = text.replace(f"{logical_cwd}/src/apps/", "src/apps/")
        text = text.replace("./src/apps/", "src/apps/")

    matches = []
    for app in list_apps():
        token = ascii_lower(app) if mode == "prompt" else f"src/apps/{app}"
        leading = TOKEN_CHARACTER if mode == "prompt" else TOOL_PREFIX_CHARACTER
        pattern = rf"(?<![{leading}]){re.escape(token)}(?![{TOKEN_CHARACTER}])"
        if re.search(pattern, text):
            matches.append(app)
    return matches


def state_root() -> Path | None:
    candidates = (
        os.environ.get("CLAUDE_PLUGIN_DATA"),
        os.environ.get("PLUGIN_DATA"),
        str(Path(os.environ.get("TMPDIR", "/tmp")) / "reinhardt-agents-plugin"),
    )
    for value in candidates:
        if not value:
            continue
        root = Path(value)
        probe = root / f".reinhardt-context-probe-{os.getpid()}"
        try:
            root.mkdir(parents=True, exist_ok=True, mode=0o700)
            probe.mkdir(mode=0o700)
            probe.rmdir()
            return root
        except OSError:
            continue
    return None


def valid_session_id(session_id: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9._-]+", session_id)) and session_id not in {
        ".",
        "..",
    }


def claim_app(session_id: str, app: str) -> bool:
    if not valid_session_id(session_id):
        return True
    root = state_root()
    if root is None:
        return True
    marker = root / session_id / hashlib.sha256(app.encode()).hexdigest()
    try:
        marker.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        marker.mkdir(mode=0o700)
        return True
    except FileExistsError:
        return not marker.is_dir()
    except OSError:
        return True


def clear_session(session_id: str) -> None:
    if not valid_session_id(session_id):
        return
    root = state_root()
    if root is None:
        return
    try:
        shutil.rmtree(root / session_id)
    except OSError:
        pass


def app_categories(directory: Path) -> str:
    categories = []
    for name in ("models", "api", "pages", "admin"):
        if (directory / f"{name}.rs").is_file() or (directory / name).is_dir():
            categories.append(name)
    if (directory / "migrations").is_dir():
        categories.append("migrations")
    if any(
        path.exists()
        for path in (
            directory / "config.rs",
            directory / "config",
            directory / "settings.rs",
            directory / "settings",
        )
    ):
        categories.append("configuration")
    return ", ".join(categories)


def render_app(app: str) -> str | None:
    directory = Path("src/apps") / app
    summary = "\n".join(
        (
            "(reinhardt-application-context",
            '  :kind "app"',
            f'  :app "{sanitize_bounded(app, 96)}"',
            f'  :path "{sanitize(directory.as_posix())}"',
            f'  :categories "{app_categories(directory)}"',
            '  :guidance "Inspect this app before editing and use the applicable bundled Reinhardt skills."',
            ")",
        )
    )
    return summary if len(summary.encode()) <= 512 else None


def render_matching_apps(text: str, session_id: str, mode: str) -> None:
    summaries = []
    for app in matching_apps(text, mode):
        if len(summaries) == 5:
            break
        if not claim_app(session_id, app):
            continue
        summary = render_app(app)
        if summary is not None:
            summaries.append(summary)

    if not summaries:
        return
    context = "\n".join(summaries)
    if mode == "tool":
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PostToolUse",
                        "additionalContext": context,
                    }
                },
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
    else:
        print(context)


def main() -> None:
    os.umask(0o077)
    mode = sys.argv[1] if len(sys.argv) > 1 else "session-start"
    raw_input = sys.stdin.read()
    payload = parse_hook_input(raw_input)
    if payload is None:
        return

    session_id = string_field(payload, "session_id")
    if mode == "session-start":
        if string_field(payload, "source") in {"startup", "clear", "compact"}:
            clear_session(session_id)
        metadata = application_metadata()
        if metadata is not None:
            print(render_baseline(metadata))
    elif mode == "prompt" and raw_input.strip():
        if application_metadata() is not None:
            render_matching_apps(
                string_field(payload, "prompt"), session_id, "prompt"
            )
    elif mode == "tool" and raw_input.strip():
        exit_code = number_field(payload, "exit_code")
        if exit_code is None:
            exit_code = number_field(payload, "exit_code", "tool_response")
        if exit_code in {None, 0} and application_metadata() is not None:
            render_matching_apps(raw_input, session_id, "tool")
    elif mode == "subagent-start":
        metadata = application_metadata()
        if metadata is not None:
            print(render_baseline(metadata))
    elif mode == "session-end":
        clear_session(session_id)


if __name__ == "__main__":
    main()
