# DI Patterns Reference

## Architecture Overview

Reinhardt's DI system is FastAPI-inspired with compile-time type safety and async-first design.

```text
reinhardt-di
  ├── Injectable trait          (core injection interface)
  ├── Depends<K, T>             (0.3 keyed dependency wrapper)
  ├── FactoryOutput<K, T>       (0.3 keyed provider output)
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

## Recommended Approach: `#[injectable]` + Keyed Providers

In 0.3.x, `#[injectable]` is the recommended macro for provider functions.
Provider functions return `FactoryOutput<K, T>`, where `K` is the dependency
identity and callers consume the value as `Depends<K, T>`.

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};

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
        provider: LlmProvider::from_settings(&*settings),
    })
}

#[server_fn]
pub async fn generate_novel(
    input: GenerateNovelInput,
    #[inject] service: Depends<NovelGenerationServiceKey, NovelGenerationService>,
) -> Result<NovelDraft, ServerFnError> {
    (*service).generate(input).await.map_err(ServerFnError::from)
}
```

### Rules for Provider Functions

- Function **MUST** be async
- Function **MUST** have an explicit `FactoryOutput<K, T>` return type
- Key type should use `#[injectable_key]` or implement `InjectableKey`
- **ALL** parameters **MUST** be marked with `#[inject]`
- Inject other provider outputs as `Depends<K, T>`
- Scope is specified as a string: `"singleton"`, `"request"`, `"transient"`
- The generated wrapper receives `InjectionContext` and resolves all `#[inject]` dependencies automatically
- `#[injectable_factory]` is retained only as a deprecated 0.2 compatibility
  alias; do not use it for new 0.3.x code

### Pages Service-Layer Boundary

For full-stack Pages apps, `services/` is the DI surface. Keep it limited to
injectable keys, provider functions, service structs/functions, and stable
application business operations that need settings, providers, repositories,
external I/O, lifecycle scoping, or test overrides.

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

`#[server_fn]` functions should stay request-shaped: validate input, assemble
DTOs, and call keyed services for shared business operations. Avoid constructing
settings directly or calling free functions for business operations inside
`#[server_fn]`; that hides dependencies from DI, makes tests harder to override,
and encourages mixed-purpose utility-function clusters.

### Provider Identity and Duplicate Registration

`DependencyRegistry::register()` panics at startup if the same provider identity
is registered twice. This prevents accidental shadowing of dependencies.

If you need two providers for the same underlying value type, use
`#[injectable_key]` with `FactoryOutput<K, T>`:

```rust
use reinhardt::di::{FactoryOutput, injectable, injectable_key};

// BAD: both providers identify as DatabaseConnection.
#[injectable(scope = "singleton")]
async fn create_read_db() -> DatabaseConnection { /* ... */ } // compile-time/provider contract error

#[injectable(scope = "singleton")]
async fn create_write_db() -> DatabaseConnection { /* ... */ } // same problem

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

### Stateful Provider Registries

If a provider stores state that later operations must observe, register it as a
singleton or put the state behind shared storage such as `Arc<Mutex<_>>`,
database rows, Redis, or the real external backend. This applies to fake vector
stores, fake search indexes, in-memory queues, and provider registries used by
both indexing and search.

Do not call `ProviderRegistry::from_settings` or an equivalent constructor in
each service method if that constructor creates a fresh in-memory provider.
Indexing and lookup paths must share the same backing state in tests and in
fake mode.

### Service Method Boundaries

Keep service workflows readable, but do not extract every local branch into a
free helper by default. If a helper is used only once and has no independent
service responsibility, inline it at the call site. This keeps endpoint and
service orchestration close to the behavior being reviewed.

When the extracted logic is a reusable boundary, make it part of DI instead:

- Move cohesive workflow steps onto the injectable service and call them through
  `self.method(...)`.
- Promote cross-service responsibilities into a separate `#[injectable]`
  service dependency.
- Keep injected state on the service struct instead of rebuilding providers or
  registries inside helper functions.
- Prefer a short private method over a long public method only when the split
  preserves a domain boundary, invariant check, or dependency reuse point.

### `#[inject]` Inside Providers

Parameters marked with `#[inject]` are resolved from the `InjectionContext`
before the provider body executes. Use direct `T` for normal injectable values
and `Depends<K, T>` only when consuming keyed provider output:

```rust
#[injectable_key]
struct UserServiceKey;

#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>, // Resolves FactoryOutput<PrimaryDatabase, DatabaseConnection>
    #[inject] config: AppConfig,                              // Resolves direct Injectable value
) -> FactoryOutput<UserServiceKey, UserService> {
    FactoryOutput::new(UserService::new(db, config))
}
```

- `Depends<K, T>` parameter: resolves keyed provider output `FactoryOutput<K, T>`
- `T` parameter: resolves `T` as a direct `Injectable` value; the generated
  resolver clones from the cached `Arc<T>` when cache lookup is used

---

## Endpoint Boundary: Shared Dependencies, Local Flows

DI is common dependency injection for readability and swappability. It is not
an abstraction layer for every use case. Put dependencies in DI when multiple
`server_fn` / HTTP endpoints share them: settings, provider factories or
registries, shared database accessors, job queue helpers, event publishers,
storage adapters, and external provider adapters.

Keep endpoint-specific validation, DTO assembly, persistence sequences,
generation flows, outline edits, and other one-off workflows in the endpoint
function or in a small private helper next to that endpoint. Avoid facades such
as `OutlineService`, `ManuscriptService`, or `DocumentService` when they only
hide a single endpoint's control flow.

Moving the same script from `#[server_fn]` into `server/`, `service/`, or
`services/` is not a cleanup by itself. Extract only when the new function or
module owns a narrower concern, such as prompt rendering, provider adaptation,
repository lookup, shared policy, or a domain operation reused by more than one
endpoint. If the extracted item still knows the endpoint DTO, response shape,
persistence order, and provider sequence, it is still the endpoint workflow.
Before extracting, name the dependency that became injectable, the invariant
that became independently testable, or the other endpoint that will reuse it; if
the only answer is "the `server_fn` got shorter", keep the workflow visible.

Inline and delete delegated helpers that are used by exactly one endpoint or
one section when they still pass through the same endpoint DTOs, dependencies,
persistence order, and provider sequence. A private helper is justified when it
has a smaller contract, returns a reusable domain value, isolates a named
invariant, or is called by more than one workflow.

The same boundary applies to simple ORM CRUD. Do not register or inject a
service whose only behavior is `Model::objects().get(...)`,
`Model::objects().filter(...).all().await`, `create`, `update`, or `delete`.
Names such as `get_project_model`, `list_document_chunks`, and `document_path`
can make endpoint code less explicit when they hide the concrete model, filters,
ownership guard, ordering, `NotFound` mapping, or DTO conversion. Keep those
plain CRUD calls at the endpoint or `server_fn` call site. Introduce an
injectable service only when it owns reusable behavior beyond CRUD, such as
transaction boundaries, cross-model orchestration, provider calls,
parsing/chunking, projection building, or nontrivial state transitions.

### Preferred: inject shared dependencies, keep the workflow visible

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};
use reinhardt::pages::prelude::*;

#[injectable_key]
pub struct AiProviderRegistryKey;

#[injectable(scope = "singleton")]
async fn create_ai_provider_registry(
    #[inject] settings: AiSettings,
) -> FactoryOutput<AiProviderRegistryKey, ProviderRegistry> {
    FactoryOutput::new(ProviderRegistry::from_settings(&settings))
}

#[server_fn]
pub async fn generate_chapter(
    project_id: Uuid,
    input: GenerateChapterRequest,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
    #[inject] providers: Depends<AiProviderRegistryKey, ProviderRegistry>,
) -> Result<ChapterResponse, ServerFnError> {
    input.validate()?;

    let outline = Outline::objects()
        .filter(Outline::project_id.eq(project_id))
        .get(&*db)
        .await?;
    let draft = build_chapter_draft(&providers, &outline, &input).await?;
    let chapter = Chapter::from_draft(project_id, draft);
    let saved = Chapter::objects()
        .create_with_conn(&*db, &chapter)
        .await?;

    Ok(ChapterResponse::from_model(&saved))
}

#[cfg(native)]
async fn build_chapter_draft(
    providers: &ProviderRegistry,
    outline: &Outline,
    input: &GenerateChapterRequest,
) -> Result<ChapterDraft, ServerFnError> {
    providers
        .writer(input.provider)
        .generate_chapter(outline, input)
        .await
}
```

When a nearby helper mentions server-only types or providers, keep it in a
server-only module or gate it with `#[cfg(native)]`; only the `#[server_fn]`
body is replaced by the WASM client stub.

### Avoid: hiding an endpoint workflow behind a thick facade

```rust
// Avoid this when the service only wraps generate_chapter's unique flow.
// Moving this body to server/generation.rs would be the same problem if the
// helper still owns the endpoint request, response, and persistence order.
#[injectable(scope = "request")]
pub struct ManuscriptService {
    #[inject]
    db: Depends<PrimaryDatabase, DatabaseConnection>,
    #[inject]
    providers: Depends<AiProviderRegistryKey, ProviderRegistry>,
}

impl ManuscriptService {
    pub async fn generate_chapter(
        &self,
        project_id: Uuid,
        input: GenerateChapterRequest,
    ) -> Result<ChapterResponse, ServerFnError> {
        // Validation, DTO assembly, persistence, and generation are now hidden
        // from the endpoint even though no other endpoint reuses this flow.
        run_hidden_generation_pipeline(&self.db, &self.providers, project_id, input).await
    }
}
```

Use a service when it represents a stable shared capability, such as a common
job queue client, provider registry, storage adapter, policy engine, or domain
operation reused by several endpoints. For one endpoint's use-case script,
prefer endpoint-local code.

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

`#[injectable]` can also be applied to provider functions. In 0.3.x, provider
functions are async and return `FactoryOutput<K, T>` so the key type becomes
the dependency identity:

```rust
use reinhardt::di::prelude::*;

#[injectable_key]
pub struct DatabaseKey;

#[injectable(scope = "singleton")]
async fn create_database(
    #[inject] config: AppConfig,
) -> FactoryOutput<DatabaseKey, DatabaseConnection> {
    FactoryOutput::new(DatabaseConnection::connect(&config.database_url).await)
}
```

### Differences from legacy `#[injectable_factory]`

| Feature | `#[injectable]` provider function | Legacy `#[injectable_factory]` |
|---------|--------------------------|------------------------|
| Sync/async | Async only | Async only |
| Scope control | `scope = "..."` | `scope = "..."` |
| Override support | `ctx.dependency(fn).override_with(value)` | Compatibility only |
| Registration | Registers provider output in the global registry | Deprecated alias |

For 0.3.x code, **`#[injectable]` is the supported provider macro**. Use
`#[injectable_factory]` only when maintaining older 0.2-era code; it is a
deprecated compatibility alias. Use `#[injectable_key]` with
`FactoryOutput<K, T>` and consume provider output as `Depends<K, T>`.

---

## Registration Requirement

All injectable types **MUST** be explicitly registered. There is no auto-injection for `Default` types. Use one of:

| Method | When |
|--------|------|
| `#[injectable]` on struct | Struct with `#[inject]` / `#[no_inject]` field attributes |
| `#[injectable]` on function | Function that produces `T` or `FactoryOutput<K, T>` |
| `impl Injectable` manually | Custom resolution logic |
| `#[injectable_factory]` | Deprecated 0.2 compatibility alias for provider functions |

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
| `Depends<K, T>` where `K: InjectableKey` | Resolves keyed provider output `FactoryOutput<K, T>` |
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
    #[inject] email_service: EmailService,
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
    #[inject] order_service: OrderService,      // Injected from DI context
    #[inject] notification: NotificationService,
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
4. Resolves `#[inject]` parameters as direct `T` values or wrapper types such
   as `Depends<K, T>`
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

## `Depends<K, T>` Wrapping

`Depends<K, T>` resolves a keyed provider output from the registry. The provider
must return `FactoryOutput<K, T>`, and `K` must implement `InjectableKey`.
`Depends<K, T>` dereferences to `T` and only requires `T: Send + Sync + 'static`
for shared access; extracting an owned `T` with `.into_inner()` requires `T:
Clone`.

Factory parameters and handler injection can receive `Depends<K, T>` for keyed
provider output or direct `T` for normal injectable values:

```rust
#[injectable_key]
struct AppConfigKey;
#[injectable_key]
struct UserServiceKey;
#[injectable_key]
struct HandlerNameKey;

// Receives keyed FactoryOutput<AppConfigKey, AppConfig>
#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] config: Depends<AppConfigKey, AppConfig>,
) -> FactoryOutput<UserServiceKey, UserService> {
    FactoryOutput::new(UserService::new(config))
}

// Receives direct Injectable value
#[injectable(scope = "transient")]
async fn make_handler(#[inject] service: MyService) -> FactoryOutput<HandlerNameKey, String> {
    FactoryOutput::new(service.value)
}
```

### Extracting Values from `Depends<K, T>`

| Method | Requires `T: Clone` | Behavior |
|--------|---------------------|----------|
| `.into_inner()` | Yes | Clones the inner value out of the Arc |
| `.try_unwrap()` | No | Returns `Ok(T)` if this is the last reference, `Err(Self)` otherwise (mirrors `Arc::try_unwrap`) |

Prefer `try_unwrap()` when the wrapper is the sole owner (e.g., at the end of a request scope) to avoid requiring `Clone` on `T`:

```rust
#[injectable_key]
struct StateLockKey;
#[injectable_key]
struct ProcessorKey;

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

Extract shared reusable policy into a third service:

```rust
// BAD: UserService ↔ OrderService (circular)

// GOOD: Both depend on AccountPolicyService (no cycle)
#[injectable_key]
pub struct AccountPolicyServiceKey;

#[injectable_key]
pub struct UserServiceKey;

#[injectable_key]
pub struct OrderServiceKey;

#[injectable(scope = "singleton")]
async fn create_user_service(
    #[inject] policy: Depends<AccountPolicyServiceKey, AccountPolicyService>,
) -> FactoryOutput<UserServiceKey, UserService> {
    FactoryOutput::new(UserService::from_policy(&*policy))
}

#[injectable(scope = "singleton")]
async fn create_order_service(
    #[inject] policy: Depends<AccountPolicyServiceKey, AccountPolicyService>,
) -> FactoryOutput<OrderServiceKey, OrderService> {
    FactoryOutput::new(OrderService::from_policy(&*policy))
}
```

---

## Testing: Dependency Override

Reinhardt DI provides a fluent API for overriding dependencies in tests using `ctx.dependency(factory_fn).override_with(value)`.

### Override via `InjectionContext::dependency()`

For functions registered with `#[injectable]` (function form), use the fluent override API:

```rust
use reinhardt_di::{FactoryOutput, InjectionContext, SingletonScope, injectable_key};
use std::sync::Arc;

#[injectable_key]
pub struct DatabaseKey;

#[injectable]
async fn create_database(
    #[inject] config: AppConfig,
) -> FactoryOutput<DatabaseKey, DatabaseConnection> {
    FactoryOutput::new(DatabaseConnection::connect(&config.database_url).await)
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

### Build a `Depends<K, T>` Wrapper Directly

```rust
#[injectable_key]
struct TestConfigKey;

#[rstest]
fn test_with_depends() {
    // Arrange
    let mock_config = AppConfig { debug: true, max_retries: 0 };
    let depends = Depends::<TestConfigKey, AppConfig>::from_value(mock_config);

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
use reinhardt::di::{get_di_context, try_get_di_context, ContextLevel, FactoryOutput};

#[injectable_key]
pub struct RouterKey;

#[injectable(scope = "transient")]
async fn make_router(#[inject] config: AppConfig) -> FactoryOutput<RouterKey, Router> {
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
| Complex async initialization | `#[injectable]` provider returning `FactoryOutput<K, T>` |
| Struct with injected fields | `#[injectable]` on struct |
| Simple type with `Default` | `#[injectable]` provider returning `FactoryOutput<K, T>` with `Default::default()` body |
| Custom resolution logic | `impl Injectable` manually |
| Endpoint DI | `#[inject]` in `#[get]`/`#[post]` etc. |
| Endpoint-specific workflow | Endpoint body or private helper next to that endpoint |
| Single-use helper that only delegates the same endpoint flow | Inline into the caller and delete the helper |
| General function DI | `#[use_inject]` + `#[inject]` |
| Test mocking (factory) | `ctx.dependency(fn).override_with(value)` |
| Test mocking (unit) | Construct direct values or use `Depends::<K, T>::from_value()` for keyed wrappers |

---

## Provider Identity Patterns

In 0.3.x, provider identity should be explicit when a value type has more than
one meaning. Prefer `#[injectable_key]` with `FactoryOutput<K, T>` for provider
functions. Newtype wrappers are still useful when the wrapper type is part of
your domain model or makes call sites clearer.

**Use keys for multiple providers that produce the same value type:**

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};

// BAD: Vec<String> is too generic and the provider has no explicit key identity
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
| Single-key value identity for `Vec<String>` — ambiguous intent | `Depends<AllowedOrigins, Vec<String>>` — self-documenting |
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
    #[inject] service: ItemService,
) -> ViewResult<Response> {
    // ...
}
```

### Testing: #[serial(di_registry)] No Longer Required

In 0.2.x, DI override tests no longer need `#[serial(di_registry)]` because `injection_context_with_di_overrides` creates an isolated per-context registry automatically. Tests can run in parallel without interfering with each other's DI state.
