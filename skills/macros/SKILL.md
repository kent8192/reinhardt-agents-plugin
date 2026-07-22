---
name: macros
description: Use when working with reinhardt procedural macros - covers attribute macros (#[model], #[user], #[inject], HTTP decorators), derive macros, and function-like macros (guard!, installed_apps!, path!)
versions: ["0.1.x", "0.2.x", "0.3.x", "0.4.0"]
---

# Reinhardt Macros

Guide developers through the use of reinhardt's procedural macros for models, views, DI, authentication, configuration, and more.

## When to Use

- User uses or asks about any `#[attribute]` or `derive()` macro
- User defines models, views, routes, or injectable services
- User mentions: "macro", "#[model]", "#[dto]", "#[user]", "#[inject]", "#[get]", "#[post]", "#[routes]", "#[component]", "#[settings]", "#[admin]", "#[app_config]", "#[hook]", "guard!", "installed_apps!", "path!", "#[derive(Schema)]", "#[derive(Model)]", "#[derive(Validate)]", "#[server_fn]", "#[wasm_server_api]", "#[permission_required]", "#[injectable]", "#[injectable_key]", "#[use_inject]"

## Workflow

### Choosing the Right Macro

1. Read `references/attribute-macros.md` for `#[attribute]` macros
2. Read `references/derive-macros.md` for `#[derive()]` macros
3. Read `references/proc-macros.md` for function-like macros (`guard!`, `installed_apps!`, `path!`)

### Model Definition

1. Use `#[model(app_label = "...")]` to define a database model
2. Use `#[field(...)]` attributes on every scalar field, including unconstrained fields
3. Use `#[rel(...)]` attributes for relationships
4. Optionally use `#[user(...)]` for user model with auth traits

> **0.3.x note:** `#[model]` still auto-generates `{Model}Info`; relation fields now use `RelationInfo<T>` / `ManyToManyInfo<Source, Target>` payloads.

### View/Handler Definition

1. Use HTTP decorators: `#[get]`, `#[post]`, `#[put]`, `#[patch]`, `#[delete]`
2. Use `#[api_view]` for function-based API views
3. Use `#[action]` for custom ViewSet actions
4. Use `#[routes]` for URL pattern registration
5. Use `#[component]` for 0.3 route-backed Pages components

> **0.2.x note:** `#[url_patterns]` is removed in 0.2.x — use `#[routes]` for all URL registration.

### Validation DTOs

1. **(0.4.0; #5543)** Use `#[dto]` with unconditional `#[validate(...)]` field attributes for named-field request or form DTOs shared by native and WASM builds
2. Keep `Debug`, `Clone`, `serde::Serialize`, `serde::Deserialize`, and any OpenAPI `Schema` derive explicit: `#[dto]` supplies only Reinhardt's shared `Validate` derive
3. For native-only input types and versions through 0.3.x, use `#[derive(Validate)]` with `#[validate(...)]` attributes
4. Prefer generated `{Model}Info` types for model-shaped response DTOs; only hand-write serializer structs when the API shape intentionally differs from the model

### DI Integration

1. Use `#[inject]` on handler parameters to receive dependencies
2. Use `#[injectable]` on structs for auto-registration (auto-derives `Clone`)
3. Use `#[injectable]` on async provider functions for factory-based registration
4. Use `#[injectable_key]` with `FactoryOutput<K, T>` when the provider output type is not a unique dependency identity
5. Use `#[use_inject]` to enable `#[inject]` in non-handler async functions

### Server Hooks

1. Use `#[hook(on = runserver)]` on a unit struct
2. Implement `RunserverHook` trait with `validate()` and/or `on_server_start()`
3. Hook is auto-registered via `inventory::collect!`

## Important Rules

- ALL macros are re-exported through the `reinhardt` facade crate
- `#[model]` auto-derives `Model`, `Serialize`, `Deserialize`, `Clone`, `Debug`
- Every scalar field inside `#[model]` should have `#[field]` or `#[field(...)]`; relationship fields should have `#[rel(...)]`
- For native-only request validation and 0.1.x–0.3.x code, use `#[derive(Validate)]` / `#[validate(...)]` instead of duplicating validation logic in services
- **(0.4.0; #5543)** Shared native/WASM DTOs use `#[dto]` above explicit derives; it adds `reinhardt::Validate`, accepts named-field structs only, and does not add serde or `Schema` derives
- **(0.4.0; #5543)** Keep shared DTO rules limited to `email`, `url`, `length`, and `range`; client validation improves UX but handlers and `#[server_fn]` endpoints must revalidate before applying business rules
- `#[user]` auto-implements `BaseUser` and `AuthIdentity` traits on native targets and is inert on WASM in 0.3.x
- HTTP decorators (`#[get]`, etc.) accept `name` and `use_inject` options
- Register 0.3 endpoint-macro handlers with `ServerRouter::endpoint(...)`; do not use removed raw `ServerRouter::function` / `.route` registration
- `guard!` precedence: `!` > `&` > `|` — use parentheses for clarity
- `installed_apps!` validates app names at compile time
- `path!` validates URL patterns at compile time (must start with `/`, snake_case params)
- `#[injectable]` covers structs and provider functions in 0.3.x; `#[injectable_factory]` is a deprecated compatibility alias
- `#[injectable]` auto-derives `Clone` on structs (no need to manually derive) and emits inert WASM stubs for shared provider functions
- `#[inject(cache = false)]` creates a fresh instance per injection (no caching)
- `#[hook(on = runserver)]` requires a unit struct (no fields, no generics) implementing `RunserverHook`
- `#[model]` uses UUID v7 (`Uuid::now_v7()`) for `Option<Uuid>` primary keys — better index performance

## Cross-Domain References

- For model field types: `../modeling/references/model-patterns.md`
- For DI patterns: `../dependency-injection/references/di-patterns.md`
- For permission guards: `../authorization/references/guards.md`
- For auth user model: `../authentication/references/user-models.md`
- For view patterns: `../api-development/references/view-patterns.md`
- For pages frontend: `../pages/references/page-macro.md`
- For shared DTO validation: `references/attribute-macros.md`

## Dynamic References

For the latest macro definitions:

1. Read `reinhardt/crates/reinhardt-core/macros/src/lib.rs` for core macros (#[model], #[user], #[get], etc.)
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for DI macros (#[injectable], #[injectable_key])
3. Read `reinhardt/crates/reinhardt-auth/macros/src/lib.rs` for guard! macro
4. Read `reinhardt/crates/reinhardt-db-macros/src/lib.rs` for #[document] macro
5. Read `reinhardt/crates/reinhardt-pages/macros/src/lib.rs` for #[server_fn], page!, head!, form!
6. Read `reinhardt/crates/reinhardt-query/macros/src/lib.rs` for #[derive(Iden)]
7. Read `reinhardt/crates/reinhardt-rest/openapi-macros/src/lib.rs` for #[derive(Schema)]
8. Read `reinhardt/crates/reinhardt-urls/routers-macros/src/lib.rs` for path! macro
9. Read `reinhardt/crates/reinhardt-grpc/macros/src/lib.rs` for #[grpc_handler]
10. Read `reinhardt/crates/reinhardt-graphql/macros/src/lib.rs` for #[graphql_handler]
11. Read `reinhardt/crates/reinhardt-core/macros/src/dto.rs` for the 0.4.0 shared DTO validation contract
