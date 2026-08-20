#!/usr/bin/env python3
"""Inject concise Reinhardt application context into agent hook events."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
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
FULL_FEATURES = {
    "admin",
    "api",
    "argon2-hasher",
    "auth",
    "auth-jwt",
    "auth-oauth",
    "auth-session",
    "auth-token",
    "bcrypt-hasher",
    "browsable-api",
    "cache",
    "chrono",
    "client-router",
    "commands",
    "conf",
    "core",
    "database",
    "db-cockroachdb",
    "db-mysql",
    "db-postgres",
    "db-sqlite",
    "deeplink",
    "dentdelion",
    "di",
    "dispatch",
    "forms",
    "graphql",
    "grpc",
    "i18n",
    "mail",
    "messages",
    "middleware",
    "middleware-auth-jwt",
    "middleware-compression",
    "middleware-cors",
    "middleware-rate-limit",
    "middleware-security",
    "migrations",
    "openapi",
    "openapi-router",
    "pages",
    "pages-web-sys-full",
    "redis-backend",
    "rest",
    "server",
    "server-fn-test",
    "session-redis",
    "sessions",
    "shortcuts",
    "standard",
    "static-files",
    "storage",
    "tasks",
    "tasks-durable",
    "test",
    "testcontainers",
    "uuid",
    "websockets",
    "websockets-pages",
}
PRESET_FEATURES = {
    "minimal": {"core", "di", "server"},
    "standard": DEFAULT_FEATURES,
    "api-only": {"minimal", "rest", "auth", "pages"},
    "graphql-server": {"minimal", "auth", "graphql", "database"},
    "websocket-server": {"minimal", "auth", "websockets", "cache"},
    "cli-tools": {"database", "migrations", "tasks", "mail"},
    "test-utils": {"test", "testcontainers", "database"},
    "full": FULL_FEATURES,
    "api": {"rest"},
    "openapi-router": {"openapi"},
    "session-redis": {"sessions", "middleware"},
    "tasks-durable": {"tasks"},
    "middleware-auth-jwt": {"auth-jwt"},
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


class CfgParser:
    """Evaluate Cargo cfg expressions against rustc's active cfg values."""

    def __init__(self, expression: str, flags: set[str], values: set[tuple[str, str]]):
        self.tokens = re.findall(
            r'[A-Za-z_][A-Za-z0-9_-]*|"[^"]*"|[(),=]', expression
        )
        self.position = 0
        self.flags = flags
        self.values = values

    def take(self) -> str:
        token = self.tokens[self.position]
        self.position += 1
        return token

    def expression(self) -> bool:
        name = self.take()
        if self.position < len(self.tokens) and self.tokens[self.position] == "=":
            self.take()
            return (name, self.take().strip('"')) in self.values
        if self.position >= len(self.tokens) or self.tokens[self.position] != "(":
            return name in self.flags

        self.take()
        arguments = []
        while self.tokens[self.position] != ")":
            arguments.append(self.expression())
            if self.tokens[self.position] == ",":
                self.take()
        self.take()
        if name == "all":
            return all(arguments)
        if name == "any":
            return any(arguments)
        if name == "not" and len(arguments) == 1:
            return not arguments[0]
        return False


def rust_target() -> tuple[str, set[str], set[tuple[str, str]]] | None:
    try:
        version = subprocess.run(
            ["rustc", "-vV"], check=True, capture_output=True, text=True
        ).stdout
        host = next(
            line.removeprefix("host: ")
            for line in version.splitlines()
            if line.startswith("host: ")
        )
        output = subprocess.run(
            ["rustc", "--print", "cfg"], check=True, capture_output=True, text=True
        ).stdout
    except (OSError, subprocess.CalledProcessError, StopIteration):
        return None

    flags = set()
    values = set()
    for line in output.splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            values.add((name, value.strip('"')))
        else:
            flags.add(line)
    return host, flags, values


def target_matches(target: str, platform) -> bool:
    if platform is None:
        return False
    host, flags, values = platform
    if not target.startswith("cfg("):
        return target == host
    try:
        parser = CfgParser(target[4:-1], flags, values)
        return parser.expression() and parser.position == len(parser.tokens)
    except (IndexError, ValueError):
        return False


def runtime_dependencies(manifest: dict):
    yield from manifest.get("dependencies", {}).items()
    targets = [
        (predicate, target)
        for predicate, target in manifest.get("target", {}).items()
        if isinstance(target, dict) and target.get("dependencies")
    ]
    if not targets:
        return
    platform = rust_target()
    for predicate, target in targets:
        if isinstance(target, dict) and target_matches(predicate, platform):
            yield from target.get("dependencies", {}).items()


def dependency_table(value) -> dict | None:
    if isinstance(value, str):
        return {"version": value}
    return value if isinstance(value, dict) else None


def inherited_dependency(
    name: str, dependency: dict, workspace: dict
) -> dict | None:
    if dependency.get("workspace") is not True:
        return dependency

    inherited = workspace.get("workspace", {}).get("dependencies", {}).get(name)
    if inherited is None:
        return None

    inherited = dependency_table(inherited)
    if inherited is None:
        return None
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


def default_feature_graph(
    manifest: dict, aliases: set[str]
) -> tuple[set[str], set[str]]:
    definitions = manifest.get("features", {})
    if not isinstance(definitions, dict):
        return set(), set()

    forwarded = set()
    activated_dependencies = set()
    pending = list(definitions.get("default", []))
    visited = set()
    while pending:
        feature = pending.pop()
        if not isinstance(feature, str) or feature in visited:
            continue
        visited.add(feature)
        if feature.startswith("dep:"):
            activated_dependencies.add(feature.removeprefix("dep:"))
        elif "/" in feature:
            dependency, dependency_feature = feature.split("/", 1)
            weak = dependency.endswith("?")
            dependency = dependency.removesuffix("?")
            if dependency in aliases:
                forwarded.add(dependency_feature)
                if not weak:
                    activated_dependencies.add(dependency)
        elif feature in definitions:
            nested = definitions.get(feature, [])
            if isinstance(nested, list):
                pending.extend(nested)
        elif feature in aliases:
            activated_dependencies.add(feature)
    return forwarded, activated_dependencies


def expand_features(features: set[str]) -> set[str]:
    expanded = set(features)
    pending = list(features)
    while pending:
        feature = pending.pop()
        additions = set(PRESET_FEATURES.get(feature, set()))
        for addition in additions - expanded:
            expanded.add(addition)
            pending.append(addition)
    return expanded


def dependency_metadata(manifest: dict, workspace: dict) -> dict | None:
    version = None
    saw_path = False
    saw_git = False
    default_features = False
    features: set[str] = set()
    declarations = []
    for name, raw_dependency in runtime_dependencies(manifest):
        table = dependency_table(raw_dependency)
        if table is None:
            continue
        dependency = inherited_dependency(name, table, workspace)
        if dependency is None:
            continue
        if dependency.get("package", name) not in {"reinhardt", "reinhardt-web"}:
            continue
        declarations.append((name, dependency))

    aliases = {name for name, _ in declarations}
    forwarded, activated_dependencies = default_feature_graph(manifest, aliases)
    active_declarations = [
        (name, dependency)
        for name, dependency in declarations
        if dependency.get("optional") is not True
        or name in activated_dependencies
    ]
    if not active_declarations:
        return None

    for name, dependency in active_declarations:
        if version is None and isinstance(dependency.get("version"), str):
            version = dependency["version"]
        saw_path |= "path" in dependency
        saw_git |= "git" in dependency

        declared_default = dependency.get(
            "default-features", dependency.get("default_features")
        )
        default_features |= declared_default is not False
        features.update(
            feature
            for feature in dependency.get("features", [])
            if isinstance(feature, str)
        )

    features.update(forwarded)
    if default_features or "standard" in features:
        features.update(DEFAULT_FEATURES)
    features = expand_features(features)
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


def string_values(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for nested in value.values():
            yield from string_values(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from string_values(nested)


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
    metadata["app_count"] = len(list_apps())
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
    try:
        return sorted(path.name for path in root.iterdir() if path.is_dir())
    except OSError:
        return []


def ascii_lower(value: str) -> str:
    return value.translate(
        str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")
    )


def matching_apps(text: str, mode: str) -> list[str]:
    if mode == "prompt":
        text = ascii_lower(text)
        return [
            app
            for app in list_apps()
            if re.search(
                rf"(?<![{TOKEN_CHARACTER}]){re.escape(ascii_lower(app))}"
                rf"(?![{TOKEN_CHARACTER}])",
                text,
            )
        ]

    text = text.replace("\\", "/")
    text = re.sub(
        r"(?i)(?<![A-Za-z0-9])([a-z]):/",
        lambda match: f"/{match.group(1).lower()}/",
        text,
    )
    logical_cwd = os.environ.get("PWD", str(Path.cwd())).replace("\\", "/")
    logical_cwd = re.sub(
        r"(?i)^([a-z]):/",
        lambda match: f"/{match.group(1).lower()}/",
        logical_cwd,
    ).rstrip("/")
    text = text.replace(f"{logical_cwd}/src/apps/", "src/apps/")
    text = text.replace("./src/apps/", "src/apps/")
    candidates = set(
        re.findall(
            rf"(?<![{TOOL_PREFIX_CHARACTER}])src/apps/"
            r"([^/\s\"'`;,|&:<>()\[\]{}]+)"
            r"(?=/|[\s\"'`;,|&:<>()\[\]{}]|$)",
            text,
        )
    )
    return [app for app in list_apps() if app in candidates]


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
    def build(display: str) -> str:
        return "\n".join(
            (
                "(reinhardt-application-context",
                '  :kind "app"',
                f'  :app "{display}"',
                f'  :path "{sanitize(directory.as_posix())}"',
                f'  :categories "{app_categories(directory)}"',
                '  :guidance "Inspect this app before editing and use the applicable bundled Reinhardt skills."',
                ")",
            )
        )

    empty_summary = build("")
    display_budget = min(96, 512 - len(empty_summary.encode()))
    if display_budget < 3:
        return None
    summary = build(sanitize_bounded(app, display_budget))
    return summary if len(summary.encode()) <= 512 else None


def render_matching_apps(text: str, session_id: str, mode: str) -> None:
    summaries = []
    for app in matching_apps(text, mode):
        if len(summaries) == 5:
            break
        summary = render_app(app)
        if summary is None or not claim_app(session_id, app):
            continue
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
            tool_text = "\n".join(string_values(payload))
            render_matching_apps(tool_text, session_id, "tool")
    elif mode == "subagent-start":
        metadata = application_metadata()
        if metadata is not None:
            print(render_baseline(metadata))
    elif mode == "session-end":
        clear_session(session_id)


if __name__ == "__main__":
    main()
