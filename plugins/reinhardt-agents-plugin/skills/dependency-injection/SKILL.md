---
name: dependency-injection
description: Use when configuring dependency injection in reinhardt-web applications - covers injectable services, scoping, and integration with database and auth
versions: ["0.1.x", "0.2.0", "0.3.x"]
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
3. For Reinhardt 0.3, register provider functions with `#[injectable(scope = "...")] -> FactoryOutput<Key, Service>`
4. Use `#[inject] service: Depends<Key, Service>` in handlers or `#[server_fn]` functions

### Designing a Pages Service Layer

1. Keep app-local `services/` focused on the DI surface: injectable keys, provider functions, service structs, and service functions
2. Move pure helpers, prompt builders, parsing/conversion logic, provider implementations, and repository/database internals into app-local `server/` modules
3. Expose business operations called by `#[server_fn]` through keyed injectable services
4. Avoid direct settings construction plus free-function calls inside `#[server_fn]` when the behavior is application business logic

### Integrating with Database/Auth

1. Read `references/di-with-db.md` for database pool and auth injection
2. Use built-in types: `DatabaseConnection`, `AuthUser<T>`, `Session`
3. These are already injectable — just use `#[inject]` in handlers

## Important Rules

- All injectable types MUST be explicitly registered (`#[injectable]` provider/struct or manual `impl Injectable`) — there is no auto-injection for `Default` types
- Custom injection logic requires `#[async_trait] impl Injectable` (method is `inject`, not `resolve`)
- In Reinhardt 0.3, provider functions MUST use `#[injectable(scope = "...")] -> FactoryOutput<Key, Service>` and callers inject `Depends<Key, Service>`
- `#[injectable_factory]` is a deprecated compatibility alias in 0.3; use `#[injectable]` for new provider functions
- `Injected<T>` is the wrapper type (NOT `Inject<T>` — that type does not exist)
- Reinhardt DI checks: global registry → scope cache → pre-seeded values → `DependencyNotRegistered` error
- Circular dependencies are detected at runtime and return `Err(DiError::CircularDependency)` — they do NOT panic
- `#[use_inject]` enables `#[inject]` in general async functions (not just handlers)
- Test overrides use `ctx.dependency(factory_fn).override_with(value)` for `#[injectable]` functions
- `#[injectable]` auto-derives `Clone` on structs — no need to manually add `#[derive(Clone)]`
- `Depends<Key, T>` requires only `T: Send + Sync + 'static` (NOT `T: Clone`); `into_inner()` requires Clone, but `try_unwrap()` does not
- In Pages apps, `services/` is the DI surface only; keep provider adapters, prompt builders, parsers, converters, repository/database helpers, and pure state-transition functions outside it
- `#[server_fn]` functions should inject keyed services for application business logic instead of constructing settings directly and calling free functions
- `DependencyRegistry::register()` panics on duplicate `TypeId` — use distinct provider keys (`FactoryOutput<Key, T>`) or newtype wrappers for multiple registrations of the same value type
- Users CANNOT register injectables for framework-managed types (`reinhardt::*`, `reinhardt_*::*` namespaces) — wrap in newtypes (pseudo orphan rule)
- Run `cargo run --bin check-di -- --validate` to verify missing deps, scope violations, circular deps, and orphan rule compliance

## Dynamic References

For the latest DI API:

1. Read `reinhardt/crates/reinhardt-di/src/lib.rs` for types and traits
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for macro documentation
3. Grep for `#[inject]` in `reinhardt/tests/` for real usage examples
