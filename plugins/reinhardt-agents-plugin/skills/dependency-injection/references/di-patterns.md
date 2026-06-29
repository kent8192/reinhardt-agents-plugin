# DI Patterns Reference

## Architecture Overview

Reinhardt's DI system is FastAPI-inspired with compile-time type safety and async-first design.

```text
reinhardt-di
  ├── Injectable trait          (core injection interface)
  ├── Injected<T>               (Arc-wrapped dependency with metadata)
  ├── Depends<K, T>             (keyed FastAPI-style Depends wrapper)
  ├── FactoryOutput<K, T>       (provider output registered under key K)
  ├── OptionalInjected<T>       (= Option<Injected<T>>)
  ├── InjectionContext           (dependency resolution container)
  ├── OverrideRegistry           (test override support)
  ├── FunctionHandle<O>          (fluent override API)
  └── Scopes: Singleton, Request, Transient

reinhardt-di/macros
  ├── #[injectable]              (register struct or provider function)
  └── #[injectable_key]          (declare explicit provider key type)

reinhardt-core/macros
  ├── #[use_inject]              (enable #[inject] in general functions)
  ├── #[inject]                  (parameter attribute for DI resolution)
  └── #[get], #[post], etc.      (endpoint macros with built-in #[inject] support)
```

---

## Recommended Approach (0.3): Keyed Provider Functions

Use `#[injectable]` provider functions for application services. Return
`FactoryOutput<K, T>` when a provider function produces a value type; the key
`K` is the dependency identity and the service is injected as
`Depends<K, T>`.

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};
use reinhardt::pages::prelude::*;

#[injectable_key]
pub struct NovelGenerationServiceKey;

pub struct NovelGenerationService {
    provider: LlmProvider,
}

impl NovelGenerationService {
    pub async fn generate(&self, input: GenerateNovelInput) -> Result<NovelDraft, AppError> {
        let prompt = build_generation_prompt(&input);
        self.provider.generate(prompt).await
    }
}

#[injectable(scope = "request")]
async fn novel_generation_service(
    #[inject] settings: Depends<AppSettingsKey, AppSettings>,
) -> FactoryOutput<NovelGenerationServiceKey, NovelGenerationService> {
    FactoryOutput::new(NovelGenerationService {
        provider: LlmProvider::from_settings(&settings),
    })
}

#[server_fn]
pub async fn generate_novel(
    input: GenerateNovelInput,
    #[inject] service: Depends<NovelGenerationServiceKey, NovelGenerationService>,
) -> Result<NovelDraft, ServerFnError> {
    service.generate(input).await.map_err(ServerFnError::from)
}
```

### Rules for `#[injectable]` Provider Functions

- Function **MUST** be `async`
- Function **MUST** have an explicit `FactoryOutput<Key, Service>` return type when it is a provider
- Key type should use `#[injectable_key]` or implement `InjectableKey`
- **ALL** parameters **MUST** be marked with `#[inject]`
- Inject other provider outputs as `Depends<Key, T>`
- Scope is specified as a string: `"singleton"`, `"request"`, `"transient"`
- The generated wrapper receives `InjectionContext` and resolves all `#[inject]` dependencies automatically
- Automatically registers with the global `DependencyRegistry` via `inventory`
- `#[injectable_factory]` is a deprecated compatibility alias in 0.3; use `#[injectable]` for new provider functions

### Pages Service-Layer Boundary

For full-stack Pages apps, `services/` is the DI surface. Keep it limited to
injectable service keys, provider functions, service structs, and methods that
represent application business operations.

Prefer keyed injectable services over clusters of utility functions whenever
the behavior is application business logic, depends on settings/providers,
touches repositories or external I/O, needs lifecycle scoping, or should be
overridable in tests. Utility functions are still appropriate for small pure
transformations that do not need DI or a business-operation boundary.

Do **not** use `services/` as a general server-side utility bucket. Put pure
helpers, prompt builders, parsing/conversion logic, provider implementation
details, repository/database internals, and state-transition helpers in
app-local `server/` modules instead.

Recommended layout for an app such as `cocrea`:

```text
src/apps/cocrea/
├── services.rs                 # Module entry for injectable service surface
├── services/
│   └── server.rs               # Keys, FactoryOutput providers, service structs
├── server.rs                   # Module entry for server-only implementation details
├── server/
│   ├── providers/              # LLM/provider adapters
│   ├── prompts/                # Prompt construction
│   └── repositories/           # Database/repository helpers
└── server_fn/                  # Request/response boundary; injects services
```

`#[server_fn]` functions should stay thin: validate/request-shape work at the
boundary, then call a keyed service such as
`Depends<NovelGenerationServiceKey, NovelGenerationService>`. Avoid constructing
settings directly or calling free functions for business operations inside
`#[server_fn]`; that hides dependencies from DI, makes tests harder to override,
and encourages mixed-purpose utility-function clusters.

### Duplicate Registration Detection

`DependencyRegistry::register()` panics at startup if the same `TypeId` is registered twice. This prevents accidental shadowing of dependencies.

If you need two providers for the same underlying value type, use distinct
provider keys:

```rust
use reinhardt::di::{FactoryOutput, injectable, injectable_key};

// BAD: unkeyed direct providers for the same value type collide.
#[injectable(scope = "singleton")]
async fn create_read_db() -> DatabaseConnection { /* ... */ }
#[injectable(scope = "singleton")]
async fn create_write_db() -> DatabaseConnection { /* ... */ }  // PANIC: duplicate TypeId

// GOOD: key types create distinct provider identities.
#[injectable_key]
pub struct ReadDbKey;

#[injectable_key]
pub struct WriteDbKey;

#[injectable(scope = "singleton")]
async fn create_read_db() -> FactoryOutput<ReadDbKey, DatabaseConnection> {
    FactoryOutput::new(DatabaseConnection::connect(&read_url).await.unwrap())
}

#[injectable(scope = "singleton")]
async fn create_write_db() -> FactoryOutput<WriteDbKey, DatabaseConnection> {
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

Users **CANNOT** register `#[injectable]` provider functions or structs for types in framework namespaces. This prevents accidental override of framework-managed services. Violations cause a startup panic.

**Framework prefixes** (registration panics if the type name starts with any of these):

- `reinhardt::`, `reinhardt_admin::`, `reinhardt_di::`, `reinhardt_core::`
- `reinhardt_auth::`, `reinhardt_db::`, `reinhardt_rest::`
- All other `reinhardt_*` crate namespaces

The `startproject` and `startapp` commands also reject names starting with `reinhardt_` or `reinhardt-`, because Cargo normalizes hyphens to underscores, placing all types under the reserved `reinhardt_*::*` namespace.

If you need to customize a framework type, wrap it in a newtype:

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

### `#[inject]` Inside Factories

Parameters marked with `#[inject]` are resolved from the `InjectionContext`
before the factory body executes. Use `Depends<Key, T>` for keyed provider
outputs:

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};

#[injectable_key]
pub struct UserRepositoryKey;

#[injectable_key]
pub struct UserServiceKey;

#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] repo: Depends<UserRepositoryKey, UserRepository>,
    #[inject] config: AppConfig, // Direct Injectable value when the type itself is the identity.
) -> FactoryOutput<UserServiceKey, UserService> {
    FactoryOutput::new(UserService::new(repo, config))
}
```

- `Depends<Key, T>` parameter: resolves `FactoryOutput<Key, T>` via DI with caching, circular dependency detection, and metadata
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

### Differences from `#[injectable_factory]`

| Feature | `#[injectable]` (function) | `#[injectable_factory]` |
|---------|--------------------------|------------------------|
| Sync/async | Both supported | Async only |
| Scope control | Per-parameter `#[inject(scope = ...)]` | Per-function `scope = "..."` |
| Override support | `ctx.dependency(fn).override_with(value)` | Not supported |
| Registration | Generates `Injectable` impl for return type | Registers factory in global registry |

In Reinhardt 0.3, prefer `#[injectable]` provider functions with
`FactoryOutput<Key, T>` for new code. `#[injectable_factory]` appears in older
0.1/0.2 examples as a compatibility alias.

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
| `#[injectable]` provider returning `FactoryOutput<Key, T>` | Async provider with explicit key and scope (recommended in 0.3) |
| `#[injectable]` on struct | Struct with `#[inject]` / `#[no_inject]` field attributes |
| `#[injectable]` on function | Function that produces the type |
| `impl Injectable` manually | Custom resolution logic |

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
| `Depends<Key, T>` where `T: Send + Sync + 'static` | Resolves `FactoryOutput<Key, T>` with DI metadata and caching |
| `Option<T>` where `T: Injectable` | Returns `Some(T)` on success, `None` on any error |

---

## Using `#[inject]` in Handlers

HTTP method decorators (`#[get]`, `#[post]`, etc.) have built-in `#[inject]` support:

```rust
use reinhardt::di::prelude::*;
use reinhardt::views::prelude::*;

#[get("/users/", name = "user_list")]
pub async fn list_users(
    #[inject] user_service: Depends<UserServiceKey, UserService>,
) -> ViewResult<Response> {
    let users = user_service.list_active().await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&users)?))
}

#[post("/users/", name = "user_create")]
pub async fn create_user(
    Json(body): Json<CreateUserRequest>,
    #[inject] user_service: Depends<UserServiceKey, UserService>,
    #[inject] email_service: Depends<EmailServiceKey, EmailService>,
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
    #[inject] order_service: Depends<OrderServiceKey, OrderService>,      // Injected from DI context
    #[inject] notification: Depends<NotificationServiceKey, NotificationService>,
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

## `Depends<Key, T>` Wrapping

Provider outputs are resolved as `Depends<Key, T>` (internally `Arc<T>` with
DI metadata). `Depends<Key, T>` requires only `T: Send + Sync + 'static` —
`Clone` is **NOT** required on `T`.

Factory parameters and handlers can receive keyed provider outputs with
`Depends<Key, T>` or direct `T` values when the type itself is the dependency
identity:

```rust
#[injectable_key]
pub struct AppConfigKey;

#[injectable_key]
pub struct UserServiceKey;

// Receives Depends<Key, T> — Arc-wrapped with caching and metadata.
#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] config: Depends<AppConfigKey, AppConfig>,
) -> FactoryOutput<UserServiceKey, UserService> {
    FactoryOutput::new(UserService::new(config))
}

// Receives T directly when T has its own unique Injectable identity.
#[injectable(scope = "transient")]
async fn make_handler(#[inject] service: MyService) -> String {
    service.value
}
```

### Extracting Values from `Depends<Key, T>` and `Injected<T>`

| Method | Requires `T: Clone` | Behavior |
|--------|---------------------|----------|
| `.into_inner()` | Yes | Clones the inner value out of the Arc |
| `.try_unwrap()` | No | Returns `Ok(T)` if this is the last reference, `Err(Self)` otherwise (mirrors `Arc::try_unwrap`) |

Prefer `try_unwrap()` when the wrapper is the sole owner (e.g., at the end of a request scope) to avoid requiring `Clone` on `T`:

```rust
#[injectable_key]
pub struct StateLockKey;

#[injectable_key]
pub struct ProcessorKey;

#[injectable(scope = "request")]
async fn create_processor(
    #[inject] lock: Depends<StateLockKey, RwLock<State>>,
) -> FactoryOutput<ProcessorKey, Processor> {
    // RwLock<State> does not implement Clone
    // try_unwrap() works because the factory is the sole consumer
    let state_lock = lock.try_unwrap().expect("sole owner");
    FactoryOutput::new(Processor::new(state_lock))
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
#[injectable_key]
pub struct UserRepositoryKey;

#[injectable_key]
pub struct UserServiceKey;

#[injectable_key]
pub struct OrderServiceKey;

#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] repo: Depends<UserRepositoryKey, UserRepository>,
) -> FactoryOutput<UserServiceKey, UserService> {
    FactoryOutput::new(UserService::new(repo))
}

#[injectable(scope = "singleton")]
async fn create_order_service(
    #[inject] repo: Depends<UserRepositoryKey, UserRepository>,
) -> FactoryOutput<OrderServiceKey, OrderService> {
    FactoryOutput::new(OrderService::new(repo))
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
use reinhardt::di::{
    ContextLevel,
    Depends,
    FactoryOutput,
    get_di_context,
    injectable,
    injectable_key,
    try_get_di_context,
};

#[injectable_key]
pub struct RouterKey;

#[injectable(scope = "transient")]
async fn make_router(
    #[inject] config: Depends<AppConfigKey, AppConfig>,
) -> FactoryOutput<RouterKey, Router> {
    // Access the DI context directly
    let di_ctx = get_di_context(ContextLevel::Current);
    FactoryOutput::new(Router::new().with_di_context(di_ctx))
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
| Complex async initialization | `#[injectable]` provider returning `FactoryOutput<Key, T>` |
| Struct with injected fields | `#[injectable]` on struct |
| Simple type with `Default` | `#[injectable]` provider returning `FactoryOutput<Key, T>` with `Default::default()` body |
| Custom resolution logic | `impl Injectable` manually |
| Endpoint DI | `#[inject]` in `#[get]`/`#[post]` etc. |
| General function DI | `#[use_inject]` + `#[inject]` |
| Test mocking (factory) | `ctx.dependency(fn).override_with(value)` |
| Test mocking (unit) | `Injected::from_value()` / `Depends::from_value()` |

---

## Keyed Provider Pattern for DI Uniqueness

In Reinhardt 0.3, provider functions that return `FactoryOutput<Key, T>` use
the explicit `Key` as part of the dependency identity. Use a distinct key type
for each meaning of the same value type.

**Always use keyed providers for configuration values and generic types:**

```rust
use reinhardt::di::{FactoryOutput, injectable, injectable_key};

pub struct AllowedOrigins(pub Vec<String>);

#[injectable_key]
pub struct AllowedOriginsKey;

#[injectable(scope = "singleton")]
async fn create_allowed_origins() -> FactoryOutput<AllowedOriginsKey, AllowedOrigins> {
    FactoryOutput::new(AllowedOrigins(vec!["https://example.com".to_string()]))
}
```

### Why This Matters

| Without key | With key |
|-------------|----------|
| Duplicate registration risk for generic value types | Explicit provider identity |
| `Depends<Vec<String>>` — ambiguous intent | `Depends<AllowedOriginsKey, AllowedOrigins>` — self-documenting |
| Errors discovered at runtime | Type misuse caught at compile time |

### When to Use Keys and Newtypes

- **Primitive wrappers**: `String`, `u32`, `bool` used as configuration values
- **Generic collections**: `Vec<T>`, `HashMap<K, V>` used as shared state
- **Common library types**: Types from external crates that multiple factories might produce

### When Extra Keys Are NOT Needed

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
