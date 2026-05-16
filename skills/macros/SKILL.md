---
name: macros
description: Use when working with reinhardt procedural macros - covers attribute macros (#[model], #[user], #[inject], HTTP decorators), derive macros, and function-like macros (guard!, installed_apps!, path!)
---

# Reinhardt Macros

Guide developers through the use of reinhardt's procedural macros for models, views, DI, authentication, configuration, and more.

## When to Use

- User uses or asks about any `#[attribute]` or `derive()` macro
- User defines models, views, routes, or injectable services
- User mentions: "macro", "#[model]", "#[user]", "#[inject]", "#[get]", "#[post]", "#[routes]", "#[settings]", "#[admin]", "#[app_config]", "#[hook]", "guard!", "installed_apps!", "path!", "#[derive(Schema)]", "#[derive(Model)]", "#[derive(Validate)]", "#[server_fn]", "#[permission_required]", "#[injectable]", "#[use_inject]"

## Workflow

### Choosing the Right Macro

1. Read `references/attribute-macros.md` for `#[attribute]` macros
2. Read `references/derive-macros.md` for `#[derive()]` macros
3. Read `references/proc-macros.md` for function-like macros (`guard!`, `installed_apps!`, `path!`)

### Model Definition

1. Use `#[model(app_label = "...")]` to define a database model
2. Use `#[field(...)]` attributes on fields for constraints
3. Use `#[rel(...)]` attributes for relationships
4. Optionally use `#[user(...)]` for user model with auth traits

### View/Handler Definition

1. Use HTTP decorators: `#[get]`, `#[post]`, `#[put]`, `#[patch]`, `#[delete]`
2. Use `#[api_view]` for function-based API views
3. Use `#[action]` for custom ViewSet actions
4. Use `#[routes]` for URL pattern registration

### DI Integration

1. Use `#[inject]` on handler parameters to receive dependencies
2. Use `#[injectable]` on structs for auto-registration (auto-derives `Clone`)
3. Use `#[injectable_factory]` on async functions for factory-based registration
4. Use `#[use_inject]` to enable `#[inject]` in non-handler async functions

### Server Hooks

1. Use `#[hook(on = runserver)]` on a unit struct
2. Implement `RunserverHook` trait with `validate()` and/or `on_server_start()`
3. Hook is auto-registered via `inventory::collect!`

## Important Rules

- ALL macros are re-exported through the `reinhardt` facade crate
- `#[model]` auto-derives `Model`, `Serialize`, `Deserialize`, `Clone`, `Debug`
- `#[user]` auto-implements `BaseUser` and `AuthIdentity` traits
- HTTP decorators (`#[get]`, etc.) accept `name` and `use_inject` options
- `guard!` precedence: `!` > `&` > `|` — use parentheses for clarity
- `installed_apps!` validates app names at compile time
- `path!` validates URL patterns at compile time (must start with `/`, snake_case params)
- `#[injectable]` and `#[injectable_factory]` are distinct: struct vs function registration
- `#[injectable]` auto-derives `Clone` on structs (no need to manually derive)
- `#[inject(cache = false)]` creates a fresh instance per injection (no caching)
- `#[hook(on = runserver)]` requires a unit struct (no fields, no generics) implementing `RunserverHook`
- `#[model]` uses UUID v7 (`Uuid::now_v7()`) for `Option<Uuid>` primary keys — better index performance

## Cross-Domain References

- For model field types: `${CLAUDE_PLUGIN_ROOT}/skills/modeling/references/model-patterns.md`
- For DI patterns: `${CLAUDE_PLUGIN_ROOT}/skills/dependency-injection/references/di-patterns.md`
- For permission guards: `${CLAUDE_PLUGIN_ROOT}/skills/authorization/references/guards.md`
- For auth user model: `${CLAUDE_PLUGIN_ROOT}/skills/authentication/references/user-models.md`
- For view patterns: `${CLAUDE_PLUGIN_ROOT}/skills/api-development/references/view-patterns.md`
- For pages frontend: `${CLAUDE_PLUGIN_ROOT}/skills/pages/references/page-macro.md`

## Dynamic References

For the latest macro definitions:
1. Read `reinhardt/crates/reinhardt-core/macros/src/lib.rs` for core macros (#[model], #[user], #[get], etc.)
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for DI macros (#[injectable], #[injectable_factory])
3. Read `reinhardt/crates/reinhardt-auth/macros/src/lib.rs` for guard! macro
4. Read `reinhardt/crates/reinhardt-db-macros/src/lib.rs` for #[document] macro
5. Read `reinhardt/crates/reinhardt-pages/macros/src/lib.rs` for #[server_fn], page!, head!, form!
6. Read `reinhardt/crates/reinhardt-query/macros/src/lib.rs` for #[derive(Iden)]
7. Read `reinhardt/crates/reinhardt-rest/openapi-macros/src/lib.rs` for #[derive(Schema)]
8. Read `reinhardt/crates/reinhardt-urls/routers-macros/src/lib.rs` for path! macro
9. Read `reinhardt/crates/reinhardt-grpc/macros/src/lib.rs` for #[grpc_handler]
10. Read `reinhardt/crates/reinhardt-graphql/macros/src/lib.rs` for #[graphql_handler]
