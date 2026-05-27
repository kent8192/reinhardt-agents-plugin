# Reinhardt Settings System

The reinhardt settings system is composable and fragment-based. Settings are assembled from independent fragments, each owning a TOML section, merged through a priority-ordered source chain.

## Architecture

| Component | Role |
|-----------|------|
| `ProjectSettings` | Project-level composed settings struct, defined via `#[settings]` macro |
| `SettingsFragment` trait | Each configuration section (core, i18n, static_files, etc.) is a fragment |
| `CoreSettings` | Built-in fragment with base_dir, secret_key, debug, allowed_hosts, databases, security |
| `ComposedSettings` trait | Auto-derived by `#[settings]` macro; validates all fragments on build |
| `SettingsBuilder` | Merges multiple sources with priority ordering |
| `Profile` | Environment selection (local, ci, staging, production) |

## The `#[settings]` Macro

The `#[settings]` macro on a struct derives `ComposedSettings`, wiring up all fragment sections automatically.

**Syntax:** `#[settings(section_name: FragmentType | FragmentType | ...)]`

- **Named sections:** `core: CoreSettings` maps to `[core]` in TOML
- **Unnamed sections:** `I18nSettings` uses the fragment's `section()` method for the TOML section name

### Example (from reinhardt-cloud dashboard)

```rust
use reinhardt::settings;

#[settings(core: CoreSettings | I18nSettings | static_files: StaticSettings | MediaSettings)]
pub struct ProjectSettings;
```

This creates a `ProjectSettings` struct with four fragment fields:
- `core` (`CoreSettings`) — maps to `[core]` in TOML
- i18n (`I18nSettings`) — maps to `[i18n]` (from fragment's `section()`)
- `static_files` (`StaticSettings`) — maps to `[static_files]` in TOML
- media (`MediaSettings`) — maps to `[media]` (from fragment's `section()`)

## Configuration Sources

Sources are added to `SettingsBuilder` in priority order. Later sources override earlier ones for the same key.

| Source | Type | Priority | Usage |
|--------|------|----------|-------|
| Default values | Built-in | Lowest | `#[serde(default)]` on fragment fields |
| Environment variables | `LowPriorityEnvSource` | Low | `REINHARDT_` prefix, container/CI overrides |
| Base TOML | `TomlFileSource` | Medium | `settings/base.toml` |
| Env-specific TOML | `TomlFileSource` | Highest | `settings/local.toml`, `production.toml`, etc. |

## SettingsBuilder Example (from dashboard)

```rust
use reinhardt::conf::settings::builder::SettingsBuilder;
use reinhardt::conf::settings::profile::Profile;
use reinhardt::conf::settings::sources::{LowPriorityEnvSource, TomlFileSource};

fn build_settings() -> ProjectSettings {
    let profile_str = std::env::var("REINHARDT_ENV").unwrap_or_else(|_| "local".to_string());
    let settings_dir = resolve_settings_dir();

    SettingsBuilder::new()
        .profile(Profile::parse(&profile_str))
        .add_source(LowPriorityEnvSource::new().with_prefix("REINHARDT_"))
        .add_source(TomlFileSource::new(settings_dir.join("base.toml")))
        .add_source(TomlFileSource::new(settings_dir.join(format!("{}.toml", profile_str))))
        .build_composed()
        .expect("Failed to build settings")
}
```

### Key Points

- `Profile::parse()` converts a string to a `Profile` enum variant
- `LowPriorityEnvSource` reads environment variables with a prefix (e.g., `REINHARDT_CORE__DEBUG=true`)
- `TomlFileSource` reads a TOML file; non-existent files are silently skipped
- `.build_composed()` deserializes, validates all fragments, and returns `ProjectSettings`

## TOML File Structure

```
settings/
├── base.toml         # Common settings (all environments)
├── local.toml        # Local development
├── ci.toml           # CI/GitHub Actions
├── staging.toml      # Staging
└── production.toml   # Production
```

### Example `base.toml`

```toml
[core]
debug = false
allowed_hosts = ["localhost"]

[core.databases.default]
engine = "postgresql"
name = "myapp"
host = "localhost"
port = 5432

[core.security]
csrf_enabled = true

[i18n]
language_code = "en"
```

### Example `local.toml` (overrides for development)

```toml
[core]
debug = true
secret_key = "dev-secret-key-not-for-production"
allowed_hosts = ["localhost", "127.0.0.1"]

[core.databases.default]
host = "localhost"
port = 5432
user = "dev"
password = "dev"
```

### Example `production.toml`

```toml
[core]
debug = false
# secret_key loaded from env: REINHARDT_CORE__SECRET_KEY

[core.security]
csrf_enabled = true
secure_ssl_redirect = true
```

## CoreSettings Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `base_dir` | `PathBuf` | cwd | Project base directory |
| `secret_key` | `String` | (required) | Cryptographic signing key |
| `debug` | `bool` | `false` | Debug mode |
| `allowed_hosts` | `Vec<String>` | `[]` | Allowed host/domain names |
| `databases` | `HashMap<String, DatabaseConfig>` | default SQLite | Database configurations |
| `security` | nested | — | Security sub-settings (CSRF, HTTPS, etc.) |

## Accessing Settings in Code

Settings are registered in the DI container and injected into handlers:

```rust
#[get("/info/", name = "app_info")]
pub async fn app_info(
    #[inject] settings: Depends<ProjectSettings>,
) -> ViewResult<Response> {
    let debug = settings.core.debug;
    // ...
}
```

### Accessing Specific Fragments

```rust
// Access core settings
let secret = &settings.core.secret_key;
let debug = settings.core.debug;

// Access database config
let db_config = settings.core.databases.get("default").unwrap();

// Access i18n settings (field name from fragment's section())
let lang = &settings.i18n.language_code;
```

## Profile Selection

The `Profile` enum determines which environment-specific TOML file to load:

```rust
pub enum Profile {
    Local,
    Ci,
    Staging,
    Production,
    Custom(String),
}
```

Set via the `REINHARDT_ENV` environment variable:

```bash
REINHARDT_ENV=local cargo run       # loads settings/local.toml
REINHARDT_ENV=production cargo run  # loads settings/production.toml
REINHARDT_ENV=ci cargo test         # loads settings/ci.toml
```

## TOML Interpolation (rc.26+)

`TomlFileSource` can opt in to `${VAR}` interpolation, letting a single TOML file resolve differently across environments without duplicating profile files. (#4092)

### Enabling Interpolation

```rust
use reinhardt::conf::settings::sources::TomlFileSource;

SettingsBuilder::new()
    .add_source(TomlFileSource::new(path).with_interpolation(true))
    .build_composed()
```

### Syntax

| Form | Behavior |
|------|----------|
| `${VAR}` | Substitute env var `VAR`; error if unset or empty |
| `${VAR:-default}` | Use `default` when `VAR` is unset or empty |
| `${VAR:-}` | Use empty string when `VAR` is unset or empty |
| `${VAR:?message}` | Error with `message` when `VAR` is unset or empty |
| `$$` | Literal `$` |

### Scope

- Strings only. Numeric, boolean, datetime, and array (of non-string) values pass through untouched.
- Strict-empty semantics: an env var that is set but empty is treated identically to unset.

### Example

```toml
# local.toml — same file works on host and inside a devcontainer
[core.databases.default]
host = "${DB_HOST:-localhost}"
port = 5432
user = "${DB_USER:-dev}"
password = "${DB_PASSWORD:?DB_PASSWORD must be set}"
```

### Composition with Env Sources

`HighPriorityEnvSource` (priority 60) still wins over interpolated TOML (priority 50), so flat-key env overrides continue to work alongside interpolation.

## MergeStrategy::Deep (rc.28+)

`SettingsBuilder` now exposes `MergeStrategy { Shallow, Deep }` to control how multiple sources combine. (#4264)

### Defaults

| Method | Default Strategy |
|--------|------------------|
| `SettingsBuilder::build()` | `Shallow` (unchanged; preserves env-source / flat-key composition) |
| `SettingsBuilder::build_composed::<T>()` | `Deep` (changed in rc.28) |

### Shallow vs. Deep

With `Shallow`, defining `[core]` in `local.toml` **replaces** the entire `[core]` block from `base.toml`, discarding sibling sub-sections such as `[core.security]` and `[core.databases.default]`.

With `Deep`, nested objects merge recursively. Top-level scalars (e.g., `redis_url`) still replace; only objects-on-both-sides recurse.

### Use Case

Without `Deep`, every environment-specific TOML had to redeclare entire sections just to flip a single value. With `Deep` as the `build_composed()` default, profiles can override only what changes:

```toml
# base.toml
[core]
debug = false
[core.security]
csrf_enabled = true
[core.databases.default]
engine = "postgresql"
host = "localhost"

# local.toml — with Deep, [core.security] and [core.databases.default] are preserved
[core]
debug = true
```

### Opting Out

To restore the previous `build_composed()` behavior:

```rust
use reinhardt::conf::settings::{MergeStrategy, SettingsBuilder};

SettingsBuilder::new()
    .with_merge_strategy(MergeStrategy::Shallow)
    .build_composed()
```

`MergeStrategy` is re-exported from `settings::` and the prelude.

---

## Version Differences (0.2.x)

### SecurityConfig Removed

In 0.2.x, the `SecurityConfig` struct is removed. Its configuration fields are moved directly into `SecurityMiddleware` with builder methods:

```rust
// 0.1.x
let config = SecurityConfig {
    hsts_seconds: 31536000,
    ssl_redirect: true,
    // ...
};
SecurityMiddleware::new(config)

// 0.2.x — builder methods on SecurityMiddleware directly
SecurityMiddleware::new()
    .with_hsts_seconds(31536000)
    .with_ssl_redirect(true)
    .with_hsts(true)
```

`SecurityMiddleware::from_security_settings()` remains available in both versions.

### ModelMetadata Constraints

In 0.2.x, `ModelMetadata` has a private `constraints` field. Access via public accessor methods instead of direct field access.
