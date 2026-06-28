---
name: dependency-injection
description: Use when configuring dependency injection in reinhardt-web applications - covers injectable services, scoping, and integration with database and auth
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Dependency Injection

Guide developers through DI configuration using reinhardt-di, including service registration, scoping, and integration with database and authentication.

## When to Use

- User configures or creates injectable services
- User asks about DI patterns or scoping
- User mentions: "DI", "dependency injection", "inject", "Provider", "scope", "singleton", "request-scoped", "Injectable"

## Workflow

### Adding a New Injectable Service

1. Read `references/di-patterns.md` for injection patterns
2. Determine scope (request-scoped vs singleton)
3. Implement `Injectable` trait or use auto-implementation
4. Use `#[inject]` in handlers to receive the dependency

### Integrating with Database/Auth

1. Read `references/di-with-db.md` for database pool and auth injection
2. Use built-in types: `DatabaseConnection`, `CurrentUser<T>`, `Session`
3. These are already injectable — just use `#[inject]` in handlers

## Important Rules

- All injectable types MUST be explicitly registered (`#[injectable]` or manual `impl Injectable`) — there is no auto-injection for `Default` types
- Custom injection logic requires `#[async_trait] impl Injectable` (method is `inject`, not `resolve`)
- Prefer `#[injectable]` for registering provider functions and injectable structs (async, explicit scope, auto-registered)
- `#[injectable_factory]` is a deprecated 0.2 compatibility alias in 0.3.x — do not use it in new code
- Use `#[injectable_key]` plus `FactoryOutput<K, T>` when a provider function returns a value type that is not a unique dependency identity
- Consume keyed provider outputs with `Depends<K, T>`; remove old `DependsResult` / `DependsOption` sugar aliases
- `Injected<T>` is the wrapper type (NOT `Inject<T>` — that type does not exist)
- Reinhardt DI checks: global registry → scope cache → pre-seeded values → `DependencyNotRegistered` error
- Circular dependencies are detected at runtime and return `Err(DiError::CircularDependency)` — they do NOT panic
- `#[use_inject]` enables `#[inject]` in general async functions (not just handlers)
- Test overrides use `ctx.dependency(factory_fn).override_with(value)` for `#[injectable]` functions
- `#[injectable]` auto-derives `Clone` on structs — no need to manually add `#[derive(Clone)]`
- Direct type-based injection is fine only when the type is the unique dependency identity; otherwise use explicit keys instead of relying on duplicate value `TypeId`s
- Users CANNOT register injectables for framework-managed types (`reinhardt::*`, `reinhardt_*::*` namespaces) — wrap in newtypes (pseudo orphan rule)
- In 0.3.x, `#[injectable]` emits inert WASM stubs for shared app modules; avoid broad call-site `#[cfg]` workarounds around provider symbols
- Run `cargo run --bin check-di -- --validate` to verify missing deps, scope violations, circular deps, and orphan rule compliance

## Dynamic References

For the latest DI API:

1. Read `reinhardt/crates/reinhardt-di/src/lib.rs` for types and traits
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for macro documentation
3. Grep for `#[inject]` in `reinhardt/tests/` for real usage examples
