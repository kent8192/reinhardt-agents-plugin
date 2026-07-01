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
3. For Reinhardt 0.3 provider functions, return `FactoryOutput<K, T>` from `#[injectable(scope = "...")]`
4. Use `#[inject] dependency: Depends<K, T>` in handlers or `#[server_fn]` functions to receive keyed provider output

### Integrating with Database/Auth

1. Read `references/di-with-db.md` for database pool and auth injection
2. Use built-in types: `DatabaseConnection`, `CurrentUser<T>`, `Session`
3. These are already injectable — just use `#[inject]` in handlers

## Important Rules

- All injectable types MUST be explicitly registered (`#[injectable]` or manual `impl Injectable`) — there is no auto-injection for `Default` types
- Custom injection logic requires `#[async_trait] impl Injectable` (method is `inject`, not `resolve`)
- Prefer `#[injectable]` for registering provider functions and injectable structs (async, explicit scope, auto-registered)
- `#[injectable_factory]` is a deprecated 0.2 compatibility alias in 0.3.x — do not use it in new code
- Use `#[injectable_key]` plus `FactoryOutput<K, T>` for 0.3 provider functions; the key type is the provider identity
- Consume keyed provider outputs with `Depends<K, T>`; remove old `DependsResult` / `DependsOption` sugar aliases and deleted `Injected<T>` wrappers
- In 0.3.x, inject direct `T` values for normal dependencies and use `Depends<K, T>` only for keyed `FactoryOutput<K, T>` provider output
- Treat DI as common dependency injection for readability and swappability, not as an abstraction layer for every use case
- DI-ify dependencies reused across multiple endpoints: settings, provider factories/registries, shared DB accessors, job queues, event publishers, storage adapters, and external provider adapters
- In Pages apps, keep `services/` as the DI surface: keys, provider functions, service structs/functions, and stable business operations that own domain policy, state transitions, validation policy, orchestration dependencies, lifecycle scoping, or test overrides
- Keep pure codecs, DTO conversion, error mapping, provider-local wire conversion, provider adapters, prompt builders, parsers, converters, repository/database internals, and narrow private helpers under app-local `server/` modules, not `services/`
- Keep endpoint-specific validation, DTO assembly, persistence flows, generation flows, and outline/edit workflows in the `server_fn` / HTTP endpoint or a small private helper beside it
- Avoid thick facades such as `OutlineService`, `ManuscriptService`, or `DocumentService` when they only hide one endpoint-specific flow
- When a helper needs request-scoped dependencies such as database connections, settings, storage, queues, providers, or another service, prefer an explicit keyed service dependency (`Depends<K, T>`) registered through DI
- Do not "improve" a `#[server_fn]` by only moving the same control flow into `server/`, `service/`, or `services/`; extraction must create a narrower contract, reusable dependency, or independently testable invariant
- If the extracted code still owns the endpoint request shape, response DTO, persistence order, and provider sequence, it is still the endpoint workflow and should stay visible near the `#[server_fn]`
- Inline and delete single-use delegated helpers when they only forward one endpoint/section's request, dependencies, and control flow
- Test service-boundary domain rules directly so later endpoint refactors cannot bypass lifecycle, validation, or orchestration policy
- Reinhardt DI checks: global registry → scope cache → pre-seeded values → `DependencyNotRegistered` error
- Circular dependencies are detected at runtime and return `Err(DiError::CircularDependency)` — they do NOT panic
- `#[use_inject]` enables `#[inject]` in general async functions (not just handlers)
- Test overrides use `ctx.dependency(factory_fn).override_with(value)` for `#[injectable]` functions
- `#[injectable]` auto-derives `Clone` on structs — no need to manually add `#[derive(Clone)]`
- Direct type-based injection is fine only when the type is the unique dependency identity; otherwise use explicit keys instead of relying on duplicate value `TypeId`s
- Stateful providers and fakes that must survive across operations should be singleton-scoped or backed by shared storage; do not rebuild an empty provider registry for each request
- One-off helper functions inside service workflows should either be inlined at the call site or promoted to injectable service methods/dependencies when they represent a reusable boundary
- Long multi-step service workflows should be split into cohesive methods on the injectable service and call sibling steps through `self.method(...)` so dependency reuse remains explicit
- Users CANNOT register injectables for framework-managed types (`reinhardt::*`, `reinhardt_*::*` namespaces) — wrap in newtypes (pseudo orphan rule)
- In 0.3.x, `#[injectable]` emits inert WASM stubs for shared app modules; avoid broad call-site `#[cfg]` workarounds around provider symbols
- Run `cargo run --bin check-di -- --validate` to verify missing deps, scope violations, circular deps, and orphan rule compliance

## Dynamic References

For the latest DI API:

1. Read `reinhardt/crates/reinhardt-di/src/lib.rs` for types and traits
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for macro documentation
3. Grep for `#[inject]` in `reinhardt/tests/` for real usage examples
