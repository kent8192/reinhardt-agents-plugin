# DI Patterns Reference

## Architecture Overview

Reinhardt's DI system is FastAPI-inspired with compile-time type safety and async-first design.

```text
reinhardt-di
  ├── Injectable trait          (core injection interface)
  ├── Injected<T>               (Arc-wrapped dependency with metadata)
  ├── Depends<T>                (FastAPI-style Depends wrapper)
  ├── Depends<K, T>             (0.3 keyed dependency wrapper)
  ├── FactoryOutput<K, T>       (0.3 keyed provider output)
  ├── OptionalInjected<T>       (= Option<Injected<T>>)
  ├── InjectionContext           (dependency resolution container)
  ├── OverrideRegistry           (test override support)
  ├── FunctionHandle<O>          (fluent override API)
  └── Scopes: Singleton, Request, Transient

reinhardt-di/macros
  ├── #[injectable]              (register struct or provider function)
  ├── #[injectable_key]          (declare explicit provider identity)
  └── #[injectable_factory]      (deprecated 0.2 compatibility alias)

reinhardt-core/macros
  ├── #[use_inject]              (enable #[inject] in general functions)
  ├── #[inject]                  (parameter attribute for DI resolution)
  └── #[get], #[post], etc.      (endpoint macros with built-in #[inject] support)
```

---

## Recommended Approach: `#[injectable]` + Optional Keys

In 0.3.x, `#[injectable]` is the recommended macro for both injectable structs
and provider functions. Return a plain `T` when the type itself is the unique
dependency identity. Return `FactoryOutput<K, T>` when the produced value type
can have multiple meanings in one application.

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};

#[injectable_key]
struct PrimaryDatabase;

#[injectable(scope = "singleton")]
async fn create_database(
    #[inject] config: Depends<AppConfig>,
) -> FactoryOutput<PrimaryDatabase, DatabaseConnection> {
    FactoryOutput::new(
        DatabaseConnection::connect(&config.database_url)
            .await
            .unwrap(),
    )
}

#[injectable(scope = "singleton")]
async fn create_email_service(#[inject] config: Depends<AppConfig>) -> EmailService {
    EmailService::new(&config.email_api_key)
}

#[injectable(scope = "transient")]
async fn create_request_logger(
    #[inject] config: Depends<AppConfig>,
    #[inject] user_info: AuthInfo,
) -> RequestLogger {
    RequestLogger::new(config.log_level, user_info.user_id())
}
```

### Rules for Provider Functions

- Function may be sync or async
- Function **MUST** have an explicit return type
- **ALL** parameters **MUST** be marked with `#[inject]`
- Scope is specified as a string: `"singleton"`, `"request"`, `"transient"`
- The generated wrapper receives `InjectionContext` and resolves all `#[inject]` dependencies automatically
- Return `T` for unique dependency identity, or `FactoryOutput<K, T>` when an
  explicit key should identify the provider
- `#[injectable_factory]` is retained only as a deprecated 0.2 compatibility
  alias; do not use it for new 0.3.x code

### Provider Identity and Duplicate Registration

`DependencyRegistry::register()` panics at startup if the same provider identity
is registered twice. This prevents accidental shadowing of dependencies.

If you need two providers for the same underlying value type, use
`#[injectable_key]` with `FactoryOutput<K, T>`:

```rust
use reinhardt::di::{FactoryOutput, injectable, injectable_key};

// BAD: both providers identify as DatabaseConnection
#[injectable(scope = "singleton")]
async fn create_read_db() -> DatabaseConnection { /* ... */ }

#[injectable(scope = "singleton")]
async fn create_write_db() -> DatabaseConnection { /* ... */ }  // PANIC: duplicate TypeId

// GOOD: keys make provider identity explicit
#[injectable_key]
struct ReadDb;

#[injectable_key]
struct WriteDb;

#[injectable(scope = "singleton")]
async fn create_read_db() -> FactoryOutput<ReadDb, DatabaseConnection> {
    FactoryOutput::new(DatabaseConnection::connect(&read_url).await.unwrap())
}

#[injectable(scope = "singleton")]
async fn create_write_db() -> FactoryOutput<WriteDb, DatabaseConnection> {
    FactoryOutput::new(DatabaseConnection::connect(&write_url).await.unwrap())
}
```

### Registry Validation (`check-di`)

The `RegistryValidator` performs startup sanity checks on the DI registry:

| Check | Description |
|-------|-------------|
| Missing dependencies | Detects factories that depend on unregistered types |
| Scope compatibility | Singletons cannot depend on request-scoped or transient types |
| Circular dependencies | Static cycle detection (complement to runtime detection) |
| Framework type overrides | Rejects user registrations for framework-managed types (see Pseudo Orphan Rule) |

Run validation with the CLI:

```bash
cargo run --bin check-di -- --validate
```

### Pseudo Orphan Rule

Users **CANNOT** register `#[injectable_factory]` or `#[injectable]` for types in framework namespaces. This prevents accidental override of framework-managed services. Violations cause a startup panic.

**Framework prefixes** (registration panics if the type name starts with any of these):

- `reinhardt::`, `reinhardt_admin::`, `reinhardt_di::`, `reinhardt_core::`
- `reinhardt_auth::`, `reinhardt_db::`, `reinhardt_rest::`
- All other `reinhardt_*` crate namespaces

The `startproject` and `startapp` commands also reject names starting with `reinhardt_` or `reinhardt-`, because Cargo normalizes hyphens to underscores, placing all types under the reserved `reinhardt_*::*` namespace.

If you need to customize a framework type, use an application-owned wrapper or
explicit key:

```rust
// BAD: panics at startup — framework type override
#[injectable(scope = "singleton")]
async fn custom_auth() -> reinhardt_auth::AuthBackend { /* ... */ }

// GOOD: newtype wrapper
pub struct CustomAuth(pub reinhardt_auth::AuthBackend);

#[injectable(scope = "singleton")]
async fn custom_auth() -> CustomAuth {
    CustomAuth(reinhardt_auth::AuthBackend::new(/* ... */))
}
```

### `#[inject]` Inside Providers

Parameters marked with `#[inject]` are resolved from the `InjectionContext`
before the provider body executes. Use `Depends<T>` or `Depends<K, T>` for
injected dependencies:

```rust
#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] db: Depends<DatabaseConnection>,  // Resolved via Depends (Arc-wrapped with metadata)
    #[inject] config: AppConfig,                // Resolved as T (cloned from Arc)
) -> UserService {
    UserService::new(db, config)
}
```

- `Depends<T>` parameter: resolves `T` via DI with caching, circular dependency detection, and metadata
- `Depends<K, T>` parameter: resolves keyed provider output `FactoryOutput<K, T>`
- `T` parameter: resolves `T`, then clones out of `Arc`

---

## `#[injectable]` for Structs

Mark a struct as injectable with automatic field injection:

```rust
use reinhardt::di::prelude::*;

#[injectable(scope = Singleton)]
pub struct AppConfig {
    #[no_inject]
    pub database_url: String,
    #[no_inject]
    pub debug: bool,
}

#[injectable(scope = Request)]
pub struct RequestLogger {
    #[inject]
    config: AppConfig,
    #[inject(cache = false)]
    request_id: RequestId,
}
```

### Field Attributes

| Attribute | Description |
|-----------|-------------|
| `#[inject]` | Inject this field from the DI container |
| `#[inject(cache = false)]` | Inject without caching |
| `#[inject(scope = Singleton)]` | Use singleton scope |
| `#[no_inject(default = Default)]` | Initialize with `Default::default()` |
| `#[no_inject(default = value)]` | Initialize with specific value |
| `#[no_inject]` | Initialize with `None` (field must be `Option<T>`) |

### Struct Requirements

- Struct must have named fields
- All fields must have either `#[inject]` or `#[no_inject]` attribute
- `#[injectable]` auto-derives `Clone` if not already present (required by `Injectable` trait)
- All `#[inject]` field types must implement `Injectable`

---

## `#[injectable]` for Functions

`#[injectable]` can also be applied to functions. It generates an `Injectable` trait implementation for the return type:

```rust
use reinhardt::di::prelude::*;

#[injectable]
fn create_database(#[inject] config: AppConfig) -> DatabaseConnection {
    DatabaseConnection::connect(&config.database_url)
}

#[injectable]
async fn create_cache(#[inject] config: AppConfig) -> CacheClient {
    CacheClient::connect(&config.cache_url).await
}
```

### Differences from legacy `#[injectable]`

| Feature | `#[injectable]` (function) | `#[injectable]` |
|---------|--------------------------|------------------------|
| Sync/async | Both supported | Async only |
| Scope control | Per-parameter `#[inject(scope = ...)]` | Per-function `scope = "..."` |
| Override support | `ctx.dependency(fn).override_with(value)` | Not supported |
| Registration | Generates `Injectable` impl for return type | Registers factory in global registry |

For 0.3.x code, **prefer `#[injectable]`** for provider functions. The
`#[injectable]` macro is retained only as a deprecated compatibility
alias for older 0.2-era code. When a provider function returns a value type
that is not a unique dependency identity, use `#[injectable_key]` with
`FactoryOutput<K, T>` and consume it as `Depends<K, T>`.

---

## `Injected<T>` Wrapper

`Injected<T>` is the internal wrapper type for injected dependencies. It wraps `Arc<T>` with injection metadata.

```rust
use reinhardt_di::{Injected, OptionalInjected};

// In handler parameters
async fn handler(
    db: Injected<Database>,                       // Required dependency
    cache: OptionalInjected<RedisCache>,           // Optional dependency
) -> String {
    // Injected<T> implements Deref<Target = T>
    db.query("SELECT 1").await;

    if let Some(cache) = cache {
        cache.get("key").await;
    }
    "OK".to_string()
}
```

### Key API

| Method | Description |
|--------|-------------|
| `Injected::<T>::resolve(&ctx)` | Resolve with cache (default) |
| `Injected::<T>::resolve_uncached(&ctx)` | Resolve without cache |
| `Injected::from_value(value)` | Create from value (for testing) |
| `injected.into_inner()` | Extract inner `T` value (requires `T: Clone`) |
| `injected.try_unwrap()` | Extract inner `T` without `Clone`. Returns `Result<T, Self>` (succeeds when refcount == 1) |
| `injected.as_arc()` | Get `&Arc<T>` reference |
| `injected.metadata()` | Get injection metadata (scope, cached) |

### `OptionalInjected<T>`

Type alias for `Option<Injected<T>>`. Used with `#[inject(optional = true)]`:

```rust
// Correct pairing:
// #[inject(optional = true)]  → OptionalInjected<T>
// #[inject] or #[inject(optional = false)]  → Injected<T>
// Mismatches cause compile errors.
```

---

## Registration Requirement

All injectable types **MUST** be explicitly registered. There is no auto-injection for `Default` types. Use one of:

| Method | When |
|--------|------|
| `#[injectable]` on struct | Struct with `#[inject]` / `#[no_inject]` field attributes |
| `#[injectable]` on function | Function that produces `T` or `FactoryOutput<K, T>` |
| `impl Injectable` manually | Custom resolution logic |
| `#[injectable]` | Deprecated 0.2 compatibility alias for provider functions |

Unregistered types return `DiError::DependencyNotRegistered` at runtime.

> **Note:** The `Injectable` trait doc comment in reinhardt-web mentions auto-injection for `Default + Clone` types, but this is not implemented (tracked in kent8192/reinhardt-web#3501).

---

## Custom Injectable with `impl Injectable`

For types needing custom construction logic:

```rust
use reinhardt::di::prelude::*;
use async_trait::async_trait;

pub struct EmailService {
    api_key: String,
    sender: String,
}

#[async_trait]
impl Injectable for EmailService {
    async fn inject(ctx: &InjectionContext) -> DiResult<Self> {
        let config = ctx.resolve::<AppConfig>().await?;
        Ok(Self {
            api_key: std::env::var("EMAIL_API_KEY")
                .map_err(|_| DiError::NotFound("EMAIL_API_KEY env var".into()))?,
            sender: config.default_sender.clone(),
        })
    }
}
```

### `Injectable` Trait

```rust
#[async_trait]
pub trait Injectable: Sized + Send + Sync + 'static {
    async fn inject(ctx: &InjectionContext) -> DiResult<Self>;

    // Optional: bypass cache
    async fn inject_uncached(ctx: &InjectionContext) -> DiResult<Self> {
        Self::inject(ctx).await
    }
}
```

### Blanket Implementations

| Type | Behavior |
|------|----------|
| `Depends<T>` where `T: Send + Sync + 'static` | Resolves `T` with DI metadata and caching |
| `Option<T>` where `T: Injectable` | Returns `Some(T)` on success, `None` on any error |

---

## Using `#[inject]` in Handlers

HTTP method decorators (`#[get]`, `#[post]`, etc.) have built-in `#[inject]` support:

```rust
use reinhardt::di::prelude::*;
use reinhardt::views::prelude::*;

#[get("/users/", name = "user_list")]
pub async fn list_users(
    #[inject] user_service: Depends<UserService>,
) -> ViewResult<Response> {
    let users = user_service.list_active().await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&users)?))
}

#[post("/users/", name = "user_create")]
pub async fn create_user(
    Json(body): Json<CreateUserRequest>,
    #[inject] user_service: Depends<UserService>,
    #[inject] email_service: Depends<EmailService>,
) -> ViewResult<Response> {
    let user = user_service.create(&body).await?;
    email_service.send_welcome(&user).await?;
    Ok(Response::new(StatusCode::CREATED)
        .with_body(json::to_vec(&UserResponse::from(user))?))
}
```

---

## `#[use_inject]` for General Functions

The `#[use_inject]` macro enables `#[inject]` in **any async function**, not just endpoint handlers. The macro transforms the function to accept a `Request` parameter and extract `InjectionContext` from it.

```rust
use reinhardt_core::use_inject;

#[use_inject]
pub async fn process_order(
    request: Request,                                    // Regular parameter (passed through)
    #[inject] order_service: Depends<OrderService>,      // Injected from DI context
    #[inject] notification: Depends<NotificationService>,
) -> ViewResult<Response> {
    let order = order_service.process(&request).await?;
    notification.send_order_confirmation(&order).await?;
    Ok(Response::new(StatusCode::OK))
}
```

### How `#[use_inject]` Works

1. Renames the original function to `{name}_original`
2. Generates a wrapper with signature `Fn(Request, ...) -> Future`
3. Extracts `InjectionContext` from `Request.get_di_context()`
4. Resolves `#[inject]` parameters via `Injected::<T>::resolve()`
5. Calls the original function with all resolved dependencies

### Rules

- Function **MUST** be `async`
- Function **MUST** have an explicit return type
- `Request` parameter is optional — if absent, it is automatically added
- Works with both free functions and methods (with `&self`)
- Supports `#[inject(cache = false)]` for uncached injection

---

## Scoping

| Scope | Lifetime | Declaration | Use Case |
|-------|----------|-------------|----------|
| Singleton | One for app lifetime | `scope = Singleton` / `scope = "singleton"` | Shared services, connection pools, configuration |
| Request | One per HTTP request | `scope = Request` / `scope = "request"` | Per-request state, auth context |
| Transient | New instance each time | `scope = Transient` / `scope = "transient"` | Stateless helpers, short-lived objects |

### Resolution Order

When resolving a type `T`:

1. Check global registry for registered scope
2. If registered: check scope cache (singleton/request) → execute factory on miss
3. If not registered: check singleton/request caches for pre-seeded values (via `set_singleton()` / `set_request()`)
4. Return `DiError::DependencyNotRegistered` if none matched

---

## `Depends<T>` Wrapping

Singleton services are resolved as `Depends<T>` (internally `Arc<T>` with DI metadata). `Depends<T>` requires only `T: Send + Sync + 'static` — `Clone` is **NOT** required on `T`.

Factory parameters and handler injection can receive either `Depends<T>` or `T`:

```rust
// Receives Depends<T> — Arc-wrapped with caching and metadata
#[injectable(scope = "singleton")]
async fn create_user_service(#[inject] config: Depends<AppConfig>) -> UserService {
    UserService::new(config)
}

// Receives T (non-Depends) — cloned out of Arc automatically
#[injectable(scope = "transient")]
async fn make_handler(#[inject] service: MyService) -> String {
    service.value
}
```

### Extracting Values from `Depends<T>` and `Injected<T>`

| Method | Requires `T: Clone` | Behavior |
|--------|---------------------|----------|
| `.into_inner()` | Yes | Clones the inner value out of the Arc |
| `.try_unwrap()` | No | Returns `Ok(T)` if this is the last reference, `Err(Self)` otherwise (mirrors `Arc::try_unwrap`) |

Prefer `try_unwrap()` when the wrapper is the sole owner (e.g., at the end of a request scope) to avoid requiring `Clone` on `T`:

```rust
#[injectable(scope = "request")]
async fn create_processor(#[inject] lock: Depends<RwLock<State>>) -> Processor {
    // RwLock<State> does not implement Clone
    // try_unwrap() works because the factory is the sole consumer
    let state_lock = lock.try_unwrap().expect("sole owner");
    Processor::new(state_lock)
}
```

---

## Circular Dependency Detection

Circular dependencies are detected **at runtime** and return `Err(DiError::CircularDependency)` — they do **NOT** panic.

```rust
#[derive(Clone)]
struct ServiceA { b: Arc<ServiceB> }
#[derive(Clone)]
struct ServiceB { a: Arc<ServiceA> }

#[async_trait]
impl Injectable for ServiceA {
    async fn inject(ctx: &InjectionContext) -> DiResult<Self> {
        let b = ctx.resolve::<ServiceB>().await?;
        Ok(ServiceA { b })
    }
}

#[async_trait]
impl Injectable for ServiceB {
    async fn inject(ctx: &InjectionContext) -> DiResult<Self> {
        let a = ctx.resolve::<ServiceA>().await?;
        Ok(ServiceB { a })
    }
}

// Resolving ServiceA returns Err(DiError::CircularDependency("..."))
// Error message includes the full cycle path: "ServiceA -> ServiceB -> ServiceA"
let result = ctx.resolve::<ServiceA>().await;
assert!(result.is_err());
```

### Detection Mechanism

- **Task-local** `HashSet<TypeId>` tracks types currently being resolved
- **O(1)** cycle detection — deterministic at every depth (no sampling)
- **RAII guard** (`ResolutionGuard`) ensures automatic cleanup on drop
- **Maximum depth**: 100 levels (returns `CycleError::MaxDepthExceeded`)
- **Thread-safe**: Task-local storage follows async tasks across thread migrations

### Performance

| Scenario | Overhead |
|----------|----------|
| Cache hit | < 5% (detection completely skipped) |
| Cache miss | 10-20% (O(1) detection via HashSet) |

### Preventing Circular Dependencies

Extract shared logic into a third service:

```rust
// BAD: UserService ↔ OrderService (circular)

// GOOD: Both depend on UserRepository (no cycle)
#[injectable(scope = "singleton")]
async fn create_user_service(#[inject] repo: Depends<UserRepository>) -> UserService {
    UserService::new(repo)
}

#[injectable(scope = "singleton")]
async fn create_order_service(#[inject] repo: Depends<UserRepository>) -> OrderService {
    OrderService::new(repo)
}
```

---

## Testing: Dependency Override

Reinhardt DI provides a fluent API for overriding dependencies in tests using `ctx.dependency(factory_fn).override_with(value)`.

### Override via `InjectionContext::dependency()`

For functions registered with `#[injectable]` (function form), use the fluent override API:

```rust
use reinhardt_di::{InjectionContext, SingletonScope};
use std::sync::Arc;

#[injectable]
fn create_database(#[inject] config: AppConfig) -> DatabaseConnection {
    DatabaseConnection::connect(&config.database_url)
}

#[rstest]
#[tokio::test]
async fn test_with_mock_database() {
    // Arrange
    let singleton = Arc::new(SingletonScope::new());
    let ctx = InjectionContext::builder(singleton).build();

    let mock_db = DatabaseConnection::in_memory();
    ctx.dependency(create_database).override_with(mock_db);

    // Act
    let result = ctx.resolve::<DatabaseConnection>().await;

    // Assert
    assert!(result.is_ok());
    assert!(ctx.dependency(create_database).has_override());
}
```

### `FunctionHandle` API

| Method | Description |
|--------|-------------|
| `.override_with(value)` | Set override value for this factory |
| `.clear_override()` | Remove override, restore normal resolution |
| `.has_override()` | Check if override is set |
| `.get_override()` | Get current override value |

### Override via `Injected::from_value()`

For unit tests that don't need a full `InjectionContext`:

```rust
#[rstest]
fn test_handler_logic() {
    // Arrange
    let mock_db = DatabaseConnection::in_memory();
    let injected_db = Injected::from_value(mock_db);

    // Act
    let result = process_with_db(&injected_db);

    // Assert
    assert!(result.is_ok());
}
```

### Override via `Depends::from_value()`

```rust
#[rstest]
fn test_with_depends() {
    // Arrange
    let mock_config = AppConfig { debug: true, max_retries: 0 };
    let depends = Depends::from_value(mock_config);

    // Act & Assert
    assert_eq!(depends.max_retries, 0);
}
```

### Cleanup

```rust
// Clear specific override
ctx.dependency(create_database).clear_override();

// Clear ALL overrides
ctx.clear_overrides();
```

---

## Accessing DI Context: `get_di_context`

Inside `#[injectable]` execution, use `get_di_context` to access the DI context without requiring `#[inject]`:

```rust
use reinhardt::di::{get_di_context, try_get_di_context, ContextLevel};

#[injectable(scope = "transient")]
async fn make_router(#[inject] config: Depends<AppConfig>) -> Router {
    // Access the DI context directly
    let di_ctx = get_di_context(ContextLevel::Current);
    Router::new().with_di_context(di_ctx)
}

// Non-panicking variant — returns None outside DI resolution context
let maybe_ctx = try_get_di_context(ContextLevel::Root);
```

| `ContextLevel` | Returns | Use Case |
|----------------|---------|----------|
| `Root` | Application-level singleton context | Access app-wide singletons |
| `Current` | Currently active context (may be request-scoped) | Access per-request dependencies |

---

## Error Types

```rust
use reinhardt_di::{DiError, DiResult};

// DiError variants:
DiError::NotFound(String)                    // Dependency not found
DiError::CircularDependency(String)          // Circular dependency detected
DiError::ProviderError(String)               // Provider function error
DiError::TypeMismatch { expected, actual }   // Type mismatch
DiError::ScopeError(String)                  // Scope-related error
DiError::NotRegistered { type_name, hint }   // Type not registered
DiError::DependencyNotRegistered { type_name } // Required dependency missing
DiError::Internal { message }                // Internal DI error
DiError::Authorization(String)               // Maps to HTTP 403
DiError::Authentication(String)              // Maps to HTTP 401
```

`DiError` automatically converts to `reinhardt_core::exception::Error` with appropriate HTTP status codes.

---

## Pattern Selection Guide

| Scenario | Recommended Pattern |
|----------|-------------------|
| Complex async initialization | `#[injectable]` |
| Struct with injected fields | `#[injectable]` on struct |
| Simple type with `Default` | `#[injectable]` with `Default::default()` body |
| Custom resolution logic | `impl Injectable` manually |
| Endpoint DI | `#[inject]` in `#[get]`/`#[post]` etc. |
| General function DI | `#[use_inject]` + `#[inject]` |
| Test mocking (factory) | `ctx.dependency(fn).override_with(value)` |
| Test mocking (unit) | `Injected::from_value()` / `Depends::from_value()` |

---

## Provider Identity Patterns

In 0.3.x, provider identity should be explicit when a value type has more than
one meaning. Prefer `#[injectable_key]` with `FactoryOutput<K, T>` for provider
functions. Newtype wrappers are still useful when the wrapper type is part of
your domain model or makes call sites clearer.

**Use keys for multiple providers that produce the same value type:**

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};

// BAD: Vec<String> is too generic and can conflict if registered elsewhere
#[injectable(scope = "singleton")]
async fn create_allowed_origins() -> Vec<String> {
    vec!["https://example.com".to_string()]
}

// GOOD: the key identifies this provider while the value remains Vec<String>
#[injectable_key]
struct AllowedOrigins;

#[injectable(scope = "singleton")]
async fn create_allowed_origins() -> FactoryOutput<AllowedOrigins, Vec<String>> {
    FactoryOutput::new(vec!["https://example.com".to_string()])
}

async fn handler(
    #[inject] origins: Depends<AllowedOrigins, Vec<String>>,
) {
    // ...
}
```

### Why This Matters

| Without explicit identity | With keyed identity |
|---------------------------|---------------------|
| Duplicate registration panics at startup | Distinct providers can share `T` safely |
| `Depends<Vec<String>>` — ambiguous intent | `Depends<AllowedOrigins, Vec<String>>` — self-documenting |
| Provider meaning hidden in function names | Provider meaning encoded in the DI type |

### When to Use Keys

- **Primitive wrappers**: `String`, `u32`, `bool` used as configuration values
- **Generic collections**: `Vec<T>`, `HashMap<K, V>` used as shared state
- **Common library types**: Types from external crates that multiple factories might produce

### When Keys Are NOT Needed

- **Domain-specific structs**: `UserService`, `DatabaseConnection` — already unique types
- **Types with a single factory**: If only one factory ever produces the type, there is no conflict risk

### Related

- kent8192/reinhardt-web#3457 — duplicate registration detection (runtime enforcement)

---

## Version Differences (0.2.x)

### InjectionContext Per-Context Registry

In 0.2.x, `InjectionContext` gains an `Option<Arc<DependencyRegistry>>` field with a `with_registry()` builder method. Resolution strategy: per-context registry is checked first, falling back to the global `global_registry()`.

```rust
// 0.2.x — isolated registry per context
let ctx = InjectionContext::new()
    .with_registry(custom_registry);
```

This enables per-test registry isolation — `injection_context_with_di_overrides` creates an isolated per-context registry for each test, eliminating the need for `#[serial(di_registry)]`.

### Injectable Trait for Extractors

In 0.2.x, the `Injectable` trait provides implementations for `Path<T>`, `Query<T>`, and `Json<T>` extractors. These can be injected directly as dependencies:

```rust
// 0.2.x — extractors as injectable dependencies
#[get("/items/:id")]
pub async fn get_item(
    #[inject] Path(id): Path<i64>,   // Injectable in 0.2.x
    #[inject] service: Depends<ItemService>,
) -> ViewResult<Response> {
    // ...
}
```

### Testing: #[serial(di_registry)] No Longer Required

In 0.2.x, DI override tests no longer need `#[serial(di_registry)]` because `injection_context_with_di_overrides` creates an isolated per-context registry automatically. Tests can run in parallel without interfering with each other's DI state.
