---
name: dependency-injection
description: Use when configuring dependency injection in reinhardt-web applications - covers injectable services, scoping, and integration with database and auth
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Dependency Injection

Guide developers through DI configuration using reinhardt-di, including service registration, scoping, and integration with database and authentication.

## When to Use

- User configures or creates injectable services
- User designs service-layer boundaries for Pages `#[server_fn]` business logic
- User asks about DI patterns or scoping
- User mentions: "DI", "dependency injection", "inject", "Provider", "scope", "singleton", "request-scoped", "Injectable"

## Workflow

### Adding a New Injectable Service

1. Read `references/di-patterns.md` for injection patterns
2. Determine scope (request-scoped vs singleton)
3. Use `#[injectable(scope = "...")]` on async provider functions returning `FactoryOutput<K, T>`
4. Use `#[inject] service: T` or `#[inject] service: Depends<K, T>` in handlers, providers, or `#[server_fn]` functions

### Designing a Pages Service Layer

1. Keep app-local `services/` focused on the DI surface: injectable keys, provider functions, service structs, and service functions
2. Prefer a keyed injectable service over a cluster of utility functions when behavior represents application business logic
3. Move pure helpers, prompt builders, parsing/conversion logic, provider implementations, and repository/database internals into app-local `server/` modules
4. Expose business operations called by `#[server_fn]` through keyed injectable services
5. Avoid direct settings construction plus free-function calls inside `#[server_fn]` when the behavior is application business logic

### Integrating with Database/Auth

1. Read `references/di-with-db.md` for database pool and auth injection
2. Use built-in types: `DatabaseConnection`, `CurrentUser<T>`, `Session`
3. These are already injectable — just use `#[inject]` in handlers

## Important Rules

- All injectable types MUST be explicitly registered (`#[injectable]` or manual `impl Injectable`) — there is no auto-injection for `Default` types
- Custom injection logic requires `#[async_trait] impl Injectable` (method is `inject`, not `resolve`)
- Prefer `#[injectable]` for registering provider functions (async, explicit scope, auto-registered)
- `#[injectable_factory]` is a deprecated 0.2 compatibility alias in 0.3.x — do not use it in new code
- Use `#[injectable_key]` plus `FactoryOutput<K, T>` for provider functions, especially when a produced value type can have multiple meanings
- Consume keyed provider outputs with `Depends<K, T>`; remove old `DependsResult` / `DependsOption` sugar aliases
- In 0.3.x, inject direct `T` values for normal dependencies and use `Depends<K, T>` only for keyed `FactoryOutput<K, T>` provider output
- Reinhardt DI checks: global registry → scope cache → pre-seeded values → `DependencyNotRegistered` error
- Circular dependencies are detected at runtime and return `Err(DiError::CircularDependency)` — they do NOT panic
- `#[use_inject]` enables `#[inject]` in general async functions (not just handlers)
- Test overrides use `ctx.dependency(factory_fn).override_with(value)` for `#[injectable]` functions
- `#[injectable]` auto-derives `Clone` on structs — no need to manually add `#[derive(Clone)]`
- Direct type-based injection is fine only when the type is the unique dependency identity; otherwise use explicit keys instead of relying on duplicate value `TypeId`s
- Stateful providers and fakes that must survive across operations should be singleton-scoped or backed by shared storage; do not rebuild an empty provider registry for each request
- Prefer DI services over utility-function clusters for business operations, especially when the logic needs settings, providers, repositories, external I/O, lifecycle scoping, or test overrides
- In Pages apps, `services/` is the DI surface only; keep provider adapters, prompt builders, parsers, converters, repository/database helpers, and pure state-transition functions outside it
- `#[server_fn]` functions should inject keyed services for application business logic instead of constructing settings directly and calling free functions
- Users CANNOT register injectables for framework-managed types (`reinhardt::*`, `reinhardt_*::*` namespaces) — wrap in newtypes (pseudo orphan rule)
- In 0.3.x, `#[injectable]` emits inert WASM stubs for shared app modules; avoid broad call-site `#[cfg]` workarounds around provider symbols
- Run `cargo run --bin check-di -- --validate` to verify missing deps, scope violations, circular deps, and orphan rule compliance

## Dynamic References

For the latest DI API:

1. Read `reinhardt/crates/reinhardt-di/src/lib.rs` for types and traits
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for macro documentation
3. Grep for `#[inject]` in `reinhardt/tests/` for real usage examples
