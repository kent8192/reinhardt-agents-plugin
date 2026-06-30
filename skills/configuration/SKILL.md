---
name: configuration
description: Use when setting up or modifying reinhardt-web project configuration - covers settings fragments, TOML sources, profiles, and the composable settings system
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Configuration

Guide developers through reinhardt-web's composable settings system using fragments, TOML sources, environment profiles, and the `#[settings]` macro.

## When to Use

- User sets up project settings or configuration
- User works with environment-specific configuration (dev/staging/production)
- User mentions: "settings", "configuration", "config", "TOML", "environment", "profile", "ProjectSettings", "CoreSettings", "fragment"

## Workflow

### Setting Up Project Configuration

1. Read `references/settings-system.md` for the composable settings architecture
2. Define a `ProjectSettings` struct with `#[settings]` macro
3. Create TOML files in `settings/` directory (base.toml + environment-specific)
4. Build settings using `SettingsBuilder`
5. Access settings via `#[inject]` in handlers

### Adding a Custom Settings Fragment

1. Read `references/fragments.md` for creating custom fragments
2. Implement `SettingsFragment` trait via `#[settings]` macro on the fragment struct
3. Add the fragment to `ProjectSettings`
4. Add the corresponding TOML section

## Important Rules

- Use `#[settings]` macro for both ProjectSettings and individual fragments
- NEVER hardcode configuration values — use TOML files or environment variables
- Provider/model/domain selections that affect runtime behavior must be represented in typed settings and, when user-facing, exposed through UI rather than only TOML comments
- External service calls must receive needed runtime configuration through settings, request payloads, HTTP, or gRPC; do not duplicate backend constants in a worker process
- Configure language and locale behavior through `I18nSettings` / `reinhardt-i18n`, not hardcoded language-specific strings, including server-side prompt templates
- Use `LowPriorityEnvSource` for env vars, `TomlFileSource` for TOML files
- Priority order (highest to lowest): env-specific TOML > base TOML > env vars > defaults
- In 0.3.x shared app/config modules should compile cfg-clean across native and WASM; avoid broad call-site `#[cfg]` workarounds around settings types
- If settings are provided through DI, use 0.3 keyed provider patterns (`#[injectable]`, optional `FactoryOutput<K, T>`) when multiple settings-like values can exist

## Dynamic References

For the latest configuration API:

1. Read `reinhardt/crates/reinhardt-conf/src/settings/` for all settings types
2. Read `reinhardt/crates/reinhardt-conf/src/settings/builder.rs` for SettingsBuilder
3. Read `reinhardt-cloud/dashboard/src/config/settings.rs` for a production example
4. Read `reinhardt/instructions/MIGRATION_0.3.md` for cfg-clean app/config expectations during 0.3.x migrations
