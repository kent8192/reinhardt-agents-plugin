# reinhardt-agent-plugin

Codex and Claude Code plugin for [reinhardt-web](https://github.com/kent8192/reinhardt-web) development. Provides skills, hooks, agents, and commands that enforce reinhardt conventions and accelerate application development.

## Installation

### Codex

This repository ships a Codex plugin manifest at `.codex-plugin/plugin.json`.
For local development, the repository also includes `.agents/plugins/marketplace.json`
with a local `reinhardt-agent-plugin` entry pointing at the repository root.

Enable Codex plugin hooks in `~/.codex/config.toml` before relying on the hook
integration:

```toml
[features]
hooks = true
plugin_hooks = true
```

### Claude Code

```bash
# From the Claude Code plugin marketplace
/plugin marketplace add kent8192/reinhardt-agent-plugin

# Or install directly
/plugin install reinhardt-agent-plugin@kent8192
```

## Features

### Skills

| Skill | Trigger | Description |
|-------|---------|-------------|
| `scaffolding` | "create a new reinhardt project", "start a new app" | Project and app scaffolding with `reinhardt-admin`, feature flag presets, and post-scaffolding configuration |
| `modeling` | "create a model", "add a field", "define relations" | Model definition with `#[model]`, field types, relations (ForeignKey, ManyToMany, OneToOne), and migration generation |
| `api-development` | "create an API", "add a view", "configure routes" | Serializers, views, URL routing, authentication, and pagination following reinhardt REST conventions |
| `testing` | "write tests", "add test coverage", "test this endpoint" | rstest-based test generation with AAA pattern, reinhardt-test fixtures, and TestContainers integration |
| `dependency-injection` | "configure DI", "inject a service", "add a provider" | DI container configuration, provider scoping, `#[inject]` handler patterns, and database/auth integration |
| `configuration` | "settings", "configuration", "config", "TOML", "environment", "profile", "ProjectSettings", "fragment" | Composable settings system using fragments, TOML sources, environment profiles, and the `#[settings]` macro |
| `admin` | "admin", "admin panel", "ModelAdmin", "AdminSite", "admin interface" | Admin panel setup with `AdminSite` configuration, `#[admin]` macro, ModelAdmin registration, and route mounting |
| `migration` | "upgrade reinhardt", "migrate", "deprecated", "breaking change", "rc.XX" | Version upgrade analysis via CHANGELOG, deprecated API detection, and guided code migration |

### Command

| Command | Description |
|---------|-------------|
| `/reinhardt-new` | Interactive guided workflow for creating a new reinhardt-web project with feature flag selection, database backend, and authentication setup |
| `/reinhardt-upgrade` | Guided reinhardt-web version upgrade with breaking change detection, deprecated API migration, and verification |

### Agents

| Agent | Description |
|-------|-------------|
| `test-generator` | Generates reinhardt-compliant tests using rstest, AAA pattern, and reinhardt-test fixtures. Specialized in TestContainers integration and API testing. |
| `code-reviewer` | Reviews Rust code for reinhardt-specific anti-patterns, convention violations, and best practice adherence across module system, DI, ORM, API design, testing, and documentation. |
| `migration-analyzer` | Analyzes reinhardt version upgrade impact by cross-referencing CHANGELOG entries, GitHub PR/Issue descriptions, deprecated API annotations, and application code usage. |

Codex primarily consumes the `skills/` and hook manifest from this plugin.
The `agents/` and `commands/` directories remain Claude Code components, but
their referenced plugin files use relative paths so the instructions are still
usable when read from Codex.

### Hooks

| Event | Matcher | Description |
|-------|---------|-------------|
| `PostToolUse` | `Write\|Edit` | Runs semgrep anti-pattern detection on modified Rust files and `Cargo.toml` |
| `SessionStart` | (all) | Injects reinhardt project context (crate structure, feature flags, conventions) into the session |

Hook commands support both plugin-root variables:

- Claude Code: `CLAUDE_PLUGIN_ROOT`
- Codex native plugin hooks: `PLUGIN_ROOT`

## Anti-Pattern Detection

The PostToolUse hook automatically scans code changes for these reinhardt-specific anti-patterns:

| Rule ID | Severity | Description |
|---------|----------|-------------|
| `reinhardt-no-glob-reexport` | ERROR | Detects `pub use module::*` glob re-exports (explicit re-exports required) |
| `reinhardt-no-workspace-test-dep` | ERROR | Detects `reinhardt-test = { workspace = true }` in functional crate dev-dependencies |
| `reinhardt-no-plain-test-attr` | WARNING | Detects plain `#[test]` without rstest (`#[rstest]` required) |
| `reinhardt-non-english-comments` | WARNING | Detects non-English characters in code comments |
| `reinhardt-no-raw-sql` | WARNING | Detects raw SQL queries (use `reinhardt-query` instead) |
| `reinhardt-aaa-labels` | WARNING | Detects non-standard test phase labels (only `// Arrange`, `// Act`, `// Assert` allowed) |

## Requirements

- **Rust** >= 1.94.0 (2024 Edition)
- **reinhardt-web** == `0.1.0-rc.22` (current target version of this plugin)
- **reinhardt-admin-cli** -- `cargo install reinhardt-admin-cli --version "0.1.0-rc.22"` (the `--version` flag is required during the RC phase because Cargo does not select pre-release versions by default)
- **Docker Desktop** -- required for TestContainers-based database tests
- **semgrep** (optional) -- enables automatic anti-pattern detection via PostToolUse hook

## License

MIT
