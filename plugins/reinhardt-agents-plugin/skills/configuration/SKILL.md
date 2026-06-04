---
name: configuration
description: Use when setting up or modifying reinhardt-web project configuration - covers settings fragments, TOML sources, profiles, and the composable settings system
versions: ["0.1.2", "0.2.x"]
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
- Use `LowPriorityEnvSource` for env vars, `TomlFileSource` for TOML files
- Priority order (highest to lowest): env-specific TOML > base TOML > env vars > defaults

## Dynamic References

For the latest configuration API:

1. Read `reinhardt/crates/reinhardt-conf/src/settings/` for all settings types
2. Read `reinhardt/crates/reinhardt-conf/src/settings/builder.rs` for SettingsBuilder
3. Read `reinhardt-cloud/dashboard/src/config/settings.rs` for a production example
