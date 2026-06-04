# DI Mock Fixtures Reference (rc.29+)

The DI testing kit ships in rc.29 as an additive, feature-gated override API for the
global `DependencyRegistry`, plus ergonomics on top of it in `reinhardt-testkit` and a
proc-macro crate `reinhardt-testkit-macros`. (#4297)

## Why

`#[injectable_factory]` and `#[injectable]` register factories into a global
`OnceLock<DependencyRegistry>`. Before rc.29, tests had no safe way to swap a
registered factory without writing `unsafe` registry-reset code or pre-seeding
`SingletonScope` (which only works for Singleton/Request scopes). The DI testing kit
fixes that with a Drop-guarded override API. (#4297)

## Feature Flag

The override APIs are gated behind the `testing` feature on `reinhardt-di` and are
re-exported through `reinhardt-testkit`. Use the `reinhardt` facade with the `test`
feature in dev-dependencies; do not enable `testing` outside of test builds. (#4297)

## `#[serial(di_registry)]` is MANDATORY

All tests that touch the override API MUST be annotated with `#[serial(di_registry)]`
from `serial_test`. The global `DependencyRegistry` is shared process-wide; running
override tests concurrently produces non-deterministic results. (#4297)

This requirement is documented in `instructions/TESTING_STANDARDS.md` (TI-8) and
`crates/reinhardt-testkit/README.md`. (#4297)

## `with_di_overrides!` Macro (Recommended)

The `with_di_overrides!` proc-macro is the highest-level API. It accepts a
comma-separated list of override entries and returns `(InjectionContext, DiOverrides)`,
where the second element is an RAII guard that restores the previous registry state on
Drop. (#4297)

```rust
use reinhardt_testkit::with_di_overrides;
use rstest::*;
use serial_test::serial;

#[rstest]
#[serial(di_registry)]
#[tokio::test]
async fn test_login() {
    let (ctx, _di) = with_di_overrides! {
        singleton Config { api_key: "test_key".into() },
        transient HttpClient => |_ctx| async {
            Ok(HttpClient::mock())
        },
    };
    // ... assertions ...
}
```

Source: PR #4297 description, verbatim. (#4297)

### Macro Entry Kinds

| Kind | Form | Semantics |
|------|------|-----------|
| `singleton` | `singleton T { ... }` | Inserts a ready-made value into the singleton scope |
| `transient` | `transient T => \|_ctx\| async { ... }` | Registers a factory closure that resolves a fresh instance per `ctx.resolve` call |

Using any other kind triggers a compile-time error — covered by the trybuild UI test
`fail_unknown_kind`. (#4297)

## `register_override` + `OverrideGuard` (Low-Level API)

When the macro is too rigid (e.g. dynamic override sets), use the lower-level
`DependencyRegistry::register_override` directly. It returns an `OverrideGuard` whose
`Drop` impl restores the prior factory entry. (#4297)

Behavior verified by the TDD test suite in
`crates/reinhardt-di/tests/register_override.rs` (5 tests, all `#[serial(di_registry)]`):

- `register_override` is non-panicking on duplicate registration (it replaces).
- `OverrideGuard` restores the previous factory when dropped.
- Transient-scope resolves see the override mid-test.
- Dropping the registry while a guard exists is safe.

The guard must be kept alive for the duration of the assertions — `let _guard = ...;`
is the common idiom. (#4297)

## `DiOverrideBuilder` API

`reinhardt-testkit::DiOverrideBuilder` is the programmatic builder that backs the
proc-macro. Use it when you want to assemble overrides conditionally:

- `DiOverrideBuilder::new()` — start an empty builder
- `.singleton::<T>(value)` — register a ready singleton
- `.transient::<T, F>(factory)` — register an async factory closure
- `.build()` — install the overrides and return a `DiOverrides` guard

`DiOverrides` is the Drop-guarded type returned by both the builder and the macro;
holding it keeps the overrides active. (#4297)

## `injection_context_with_di_overrides`

`injection_context_with_di_overrides(builder) -> (InjectionContext, DiOverrides)`
constructs an `InjectionContext` that already sees the override set. The macro expands
to a call against this helper, but you may invoke it directly when you need the
context wired to a manually-built `DiOverrideBuilder`. (#4297)

Unit coverage lives in `crates/reinhardt-testkit/src/fixtures/di_overrides.rs::tests`
(3 tests):

- Singleton override is visible via `get_singleton`.
- Factory override is visible via `ctx.resolve`.
- Drop reverts the factory override (registry returns to its prior state).

(#4297)

## `reinhardt-testkit-macros` Crate

The proc-macro `with_di_overrides!` lives in the new sibling crate
`reinhardt-testkit-macros`, re-exported from `reinhardt-testkit` so user code only
needs to import from `reinhardt_testkit`. The split exists because proc-macros must
live in a `proc-macro = true` crate. (#4297)

Compile-time behavior is pinned by trybuild UI tests in
`crates/reinhardt-testkit-macros/tests/ui/`:

- `pass_singleton` — happy-path singleton entry compiles
- `pass_factory` — happy-path transient/factory entry compiles
- `fail_unknown_kind` — unknown kind keyword produces the expected error

(#4297)

## Cargo.toml

```toml
[dev-dependencies]
reinhardt = { version = "0.1.2", features = ["test"] }  # For 0.2.x: "0.2.0-rc.2"
rstest = "0.23"
serial_test = "3"
tokio = { version = "1", features = ["full"] }
```

`reinhardt-testkit-macros` is published as a separate crate and pulled in transitively
via `reinhardt-testkit`; you do NOT need to add it as a direct dev-dependency. (#4297)

## Checklist

- [ ] Test is annotated with `#[serial(di_registry)]` **(0.1.x only — not required in 0.2.x)**
- [ ] `DiOverrides`/`OverrideGuard` is bound to a `let` binding that outlives the
      assertions (use `_di`, never `_`)
- [ ] Override kind in the macro is one of `singleton` / `transient`
- [ ] The `testing` feature is enabled only in dev/test builds

## Version Differences (0.2.x)

### #[serial(di_registry)] No Longer Required

In 0.2.x, `injection_context_with_di_overrides` creates an isolated per-context `DependencyRegistry` for each test. This eliminates the need for `#[serial(di_registry)]` — DI override tests can run in parallel without interfering with each other's state.

```rust
// 0.1.x — serial annotation required
#[rstest]
#[serial(di_registry)]
async fn test_with_mock_service() {
    // ...
}

// 0.2.x — parallel execution safe
#[rstest]
async fn test_with_mock_service() {
    // injection_context_with_di_overrides creates isolated registry
    // ...
}
```
