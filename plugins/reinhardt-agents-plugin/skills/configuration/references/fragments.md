# Settings Fragments

Fragments are independent configuration sections that compose into `ProjectSettings`. Each fragment owns a TOML section and can be validated independently.

## Built-in Fragments

| Fragment | TOML Section | Description |
|----------|-------------|-------------|
| `CoreSettings` | `[core]` | Base dir, secret key, debug, hosts, databases, security |
| `I18nSettings` | `[i18n]` | Language, timezone, locale |
| `StaticSettings` | `[static_files]` | Static file serving |
| `MediaSettings` | `[media]` | User-uploaded file storage |
| `CacheSettings` | `[cache]` | Caching configuration |
| `EmailSettings` | `[email]` | Email backend configuration |
| `LoggingSettings` | `[logging]` | Logging configuration |
| `CorsSettings` | `[cors]` | CORS configuration |
| `SecuritySettings` | `[core.security]` | Security (nested under core) |

## Creating Custom Fragments

Use the `#[settings]` macro on a struct to implement the `SettingsFragment` trait:

```rust
use reinhardt::conf::settings::fragment::SettingsFragment;
use reinhardt::settings;
use serde::{Deserialize, Serialize};

#[settings]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MyAppSettings {
    pub api_key: String,
    pub max_retries: u32,
    #[serde(default = "default_timeout")]
    pub timeout_secs: u64,
}

fn default_timeout() -> u64 { 30 }
```

### Registering in ProjectSettings

```rust
// In your ProjectSettings:
#[settings(core: CoreSettings | myapp: MyAppSettings)]
pub struct ProjectSettings;
```

### Corresponding TOML

```toml
[myapp]
api_key = "sk-..."
max_retries = 3
timeout_secs = 60
```

### Accessing the Fragment

```rust
#[get("/status/", name = "status")]
pub async fn status(
    #[inject] settings: ProjectSettings,
) -> ViewResult<Response> {
    let api_key = &settings.myapp.api_key;
    let timeout = settings.myapp.timeout_secs;
    // ...
}
```

## Validation

Fragments can implement `SettingsValidation` for custom validation logic. Validation runs automatically during `build_composed()`.

```rust
impl SettingsValidation for MyAppSettings {
    fn validate(&self) -> ValidationResult {
        if self.max_retries == 0 {
            return Err(ValidationError::new("max_retries must be > 0"));
        }
        Ok(())
    }
}
```

### Common Validation Patterns

```rust
impl SettingsValidation for MyAppSettings {
    fn validate(&self) -> ValidationResult {
        // Required field check
        if self.api_key.is_empty() {
            return Err(ValidationError::new("api_key must not be empty"));
        }

        // Range check
        if self.timeout_secs > 300 {
            return Err(ValidationError::new("timeout_secs must be <= 300"));
        }

        Ok(())
    }
}
```

## Profile-Specific Validation

Fragments can validate differently based on the environment profile. For example, requiring a real secret key in production but allowing a placeholder in development:

```rust
impl SettingsValidation for CoreSettings {
    fn validate_with_profile(&self, profile: &Profile) -> ValidationResult {
        match profile {
            Profile::Production => {
                if self.secret_key.starts_with("dev-") {
                    return Err(ValidationError::new(
                        "production secret_key must not use dev- prefix"
                    ));
                }
                if self.debug {
                    return Err(ValidationError::new(
                        "debug must be false in production"
                    ));
                }
            }
            _ => {}
        }
        Ok(())
    }
}
```

## Fragment Composition Patterns

### Minimal (core only)

```rust
#[settings(core: CoreSettings)]
pub struct ProjectSettings;
```

### Standard web app

```rust
#[settings(
    core: CoreSettings
    | I18nSettings
    | static_files: StaticSettings
    | MediaSettings
    | CorsSettings
)]
pub struct ProjectSettings;
```

### Full-featured with custom fragments

```rust
#[settings(
    core: CoreSettings
    | I18nSettings
    | static_files: StaticSettings
    | MediaSettings
    | CacheSettings
    | EmailSettings
    | LoggingSettings
    | CorsSettings
    | myapp: MyAppSettings
    | billing: BillingSettings
)]
pub struct ProjectSettings;
```

## Fragment Design Guidelines

- Keep fragments focused on a single concern (e.g., email, caching, billing)
- Use `#[serde(default)]` for optional fields with sensible defaults
- Implement `SettingsValidation` for any fragment with constraints
- Use nested structs for sub-sections (e.g., `SecuritySettings` under `CoreSettings`)
- Prefer typed enums over string fields for fixed choices (e.g., database engine)

## VersioningSettings Fragment (rc.29+)

The `reinhardt-rest` crate provides a `VersioningSettings` fragment for REST API versioning configuration. Configure it under `[rest_versioning]` in your TOML files. (#4285)

### Section Naming

The section uses an underscore (`rest_versioning`) rather than a dotted path (`rest.versioning`) because the `#[settings]` macro generates a method identifier from the section string, and Rust identifiers cannot contain dots.

### Registering in ProjectSettings

```rust
use reinhardt::settings;
use reinhardt_rest::settings::VersioningSettings;

#[settings(core: CoreSettings | rest_versioning: VersioningSettings)]
pub struct ProjectSettings;
```

### TOML Configuration

```toml
[rest_versioning]
default_version = "v1"
allowed_versions = ["v1", "v2"]
strategy = "accept_header"
strict_mode = false
```

### Converting to VersioningConfig

A `From<VersioningSettings> for VersioningConfig` conversion is provided for ergonomic use with REST framework internals:

```rust
let config = VersioningConfig::from(settings.rest_versioning.clone());
```

### Breaking Change: Env Vars Retired

The following environment variables are **no longer recognized**:

- `REINHARDT_VERSIONING_DEFAULT_VERSION`
- `REINHARDT_VERSIONING_ALLOWED_VERSIONS`
- `REINHARDT_VERSIONING_STRATEGY`
- `REINHARDT_VERSIONING_STRICT_MODE`

`VersioningConfig::from_env()` has also been removed. Configure versioning through the project settings system instead.

## Settings Injection Pattern (rc.29+)

Middleware and other components that historically read configuration from `std::env::var("REINHARDT_SETTINGS")` per request should now accept settings at construction time via a `from_settings(&Settings)` constructor, mirroring the `SessionMiddleware` pattern. (#4284)

### Example: BrokenLinkEmailsMiddleware

```rust
use reinhardt_middleware::broken_link::{BrokenLinkConfig, BrokenLinkEmailsMiddleware};

// Construct the middleware once from settings
let middleware = BrokenLinkEmailsMiddleware::from_settings(&settings);

// Or build the config directly
let config = BrokenLinkConfig::from_settings(&settings);
```

The `[core.managers]` section is now read once at middleware construction; behavior is unchanged but per-request env-var deserialization overhead is eliminated.

### Guideline for Custom Middleware

When writing middleware that depends on settings:

- Provide `pub fn from_settings(settings: &Settings) -> Self` (or `-> Result<Self, _>`)
- Capture only the fields you need, not the whole `Settings` struct
- Avoid `env::var` / `serde_json::from_str` calls in hot paths
- Construct middleware once during app wiring; do not rebuild per request
