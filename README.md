# reinhardt-cc

AI coding assistant plugin for [reinhardt-web](https://github.com/kent8192/reinhardt-web) development. Provides skills, hooks, agents, and commands that enforce reinhardt conventions and accelerate application development.

Supports **Claude Code** and **Codex** (via `AGENTS.md` mirror).

## Installation

### Claude Code

```bash
# From the Claude Code plugin marketplace
/plugin marketplace add kent8192/reinhardt-cc

# Or install directly
/plugin install reinhardt-cc@kent8192
```

### Codex

The repository includes `AGENTS.md` (a mirror of `CLAUDE.md`) for Codex compatibility. Clone the repo and point Codex to it:

```bash
git clone https://github.com/kent8192/reinhardt-cc.git
# AGENTS.md is automatically picked up by Codex
```

## Supported Versions

This plugin documents both active reinhardt-web version families:

| Version | Status | Branch |
|---------|--------|--------|
| **0.1.2** | Stable | `main` |
| **0.2.0-rc.2** | Development | `develop/0.2.0` |

Skills use inline version markers — `**(0.1.x)**` / `**(0.2.x)**` — where APIs diverge between versions. Check your project's `Cargo.toml` to determine which version family applies.

## Features

### Skills

| Skill | Trigger | Description |
|-------|---------|-------------|
| `scaffolding` | "create a new reinhardt project", "start a new app" | Project and app scaffolding with `reinhardt-admin`, feature flag presets, and post-scaffolding configuration |
| `modeling` | "create a model", "add a field", "define relations" | Model definition with `#[model]`, field types, relations (ForeignKey, ManyToMany, OneToOne), `CustomManager`, and migration generation |
| `api-development` | "create an API", "add a view", "configure routes" | Serializers, views, URL routing, authentication, and pagination following reinhardt REST conventions; `ModelViewSet`, `VersionedRouter` |
| `authentication` | "JWT", "session auth", "OAuth", "OIDC", "GenericOidcProvider", "social login" | Auth backends, JWT/session setup, social providers (Google/GitHub/Apple/Microsoft) and `GenericOidcProvider` for arbitrary OIDC IdPs |
| `authorization` | "permissions", "guards", "extractors", "access control" | Permission system, guard middleware, and extractor patterns |
| `pages` | "page", "head", "form", "server_fn", "Signal", "useState", "SSR", "hydration", "WASM", "frontend", "ClientLauncher" | WASM frontend with `page!` / `head!` / `form!` macros, reactive hooks, `ClientLauncher` lifecycle, SPA routing, and SSR |
| `macros` | "#[model]", "#[api]", "#[inject]", "#[admin]", "#[settings]" | Attribute, derive, and function-like procedural macros — semantics, options, and recommended patterns |
| `testing` | "write tests", "add test coverage", "test this endpoint", "DI override" | rstest-based test generation with AAA pattern, reinhardt-test fixtures, TestContainers, and `with_di_overrides!` DI testing kit |
| `dependency-injection` | "configure DI", "inject a service", "add a provider" | DI container configuration, provider scoping, `#[inject]` handler patterns, and database/auth integration |
| `signals` | "signal", "signal handler", "lifecycle event", "background task" | Async side-effects via `pre_save` / `post_save` / etc., transaction signals, and task queue integration |
| `configuration` | "settings", "configuration", "config", "TOML", "environment", "profile", "ProjectSettings", "fragment" | Composable settings system using fragments, TOML sources with interpolation, `MergeStrategy::Deep`, environment profiles, and the `#[settings]` macro |
| `admin` | "admin", "admin panel", "ModelAdmin", "AdminSite", "admin interface" | Admin panel setup with `AdminSite` configuration, `#[admin]` macro, ModelAdmin registration, and route mounting |
| `architecture` | "feature design", "cross-layer", "where does this go" | Cross-layer feature development workflow tying scaffolding, modeling, API, and pages together |
| `lint` | "lint", "fix warnings", "clippy", "static analysis" | Static analysis workflow with the fix-iterate pattern |
| `migration` | "upgrade reinhardt", "migrate", "deprecated", "breaking change", "rc.XX" | Version upgrade analysis via CHANGELOG, deprecated API detection, and guided code migration |

### Commands

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

### Hooks

| Event | Matcher | Description |
|-------|---------|-------------|
| `PostToolUse` | `Write\|Edit` | Runs semgrep anti-pattern detection on modified Rust files and `Cargo.toml` |
| `SessionStart` | (all) | Injects reinhardt project context (crate structure, feature flags, conventions) into the session |

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
- **reinhardt-web** `0.1.2` (stable) / `0.2.0-rc.2` (development) — this plugin documents both version families
- **reinhardt-admin-cli** -- `cargo install reinhardt-admin-cli --version "0.1.2"` (for 0.2.x: `--version "0.2.0-rc.2"`)
- **Docker Desktop** -- required for TestContainers-based database tests
- **semgrep** (optional) -- enables automatic anti-pattern detection via PostToolUse hook

## Platform Compatibility

| Platform | Config File | Status |
|----------|-------------|--------|
| **Claude Code** | `CLAUDE.md` + `.claude-plugin/` | Full support (skills, hooks, agents, commands) |
| **Codex** | `AGENTS.md` | Instructions mirror (same content as `CLAUDE.md` with name substitutions) |

`CLAUDE.md` and `AGENTS.md` are kept in sync — edits to one must be mirrored to the other in the same commit. Only documented substitutions (title, attribution footer references) differ between the two files.

## License

MIT
