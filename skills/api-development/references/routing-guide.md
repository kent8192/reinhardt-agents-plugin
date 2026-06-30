# Reinhardt Routing Guide Reference

## App-Level URL Configuration

> **Note: The `url_patterns()` convention below is removed in 0.2.x.** All URL registration uses `#[routes]` instead. The content below applies to 0.1.x only. See the [Root-Level URL Configuration](#root-level-url-configuration) section for the `#[routes]` pattern that works in both versions.

Each app defines its routes using a `ServerRouter`. Handlers decorated with `#[get]`, `#[post]`, etc. are registered via `.endpoint()`.

```rust
// src/apps/user/urls.rs
use reinhardt::urls::prelude::*;
use super::views;

pub fn url_patterns() -> ServerRouter {
    ServerRouter::new()
        .endpoint(views::list_users)
        .endpoint(views::get_user)
        .endpoint(views::create_user)
        .endpoint(views::update_user)
        .endpoint(views::delete_user)
}
```

The HTTP method and path come from the decorator on each handler:

```rust
// src/apps/user/views.rs
#[get("/users/", name = "user_list")]
pub async fn list_users(Query(params): Query<PaginationParams>) -> ViewResult<Response> { ... }

#[get("/users/{id}/", name = "user_retrieve")]
pub async fn get_user(Path(id): Path<i64>) -> ViewResult<Response> { ... }

#[post("/users/", name = "user_create")]
pub async fn create_user(Json(body): Json<CreateUserRequest>) -> ViewResult<Response> { ... }

#[patch("/users/{id}/", name = "user_update")]
pub async fn update_user(Path(id): Path<i64>, Json(body): Json<UpdateUserRequest>) -> ViewResult<Response> { ... }

#[delete("/users/{id}/", name = "user_delete")]
pub async fn delete_user(Path(id): Path<i64>) -> ViewResult<Response> { ... }
```

### ViewSet Routing

For ViewSets, the router auto-generates standard CRUD routes:

```rust
// src/apps/user/urls.rs
use reinhardt::urls::prelude::*;
use super::views::UserViewSet;

pub fn url_patterns() -> ServerRouter {
    let mut router = ServerRouter::new();

    // Registers: GET /, POST /, GET /{id}, PUT /{id}, PATCH /{id}, DELETE /{id}
    router.register_viewset::<UserViewSet>("/");

    router
}
```

## Root-Level URL Configuration

The project's root `urls.rs` uses `UnifiedRouter` to combine all app routers. It supports DI context, middleware, and server functions:

The root router function MUST be annotated with `#[routes]`:

```rust
// src/config/urls.rs
use reinhardt::routes;
use reinhardt::urls::prelude::UnifiedRouter;
use reinhardt::di::{InjectionContext, SingletonScope};

#[routes]
pub fn routes() -> UnifiedRouter {
    let singleton_scope = Arc::new(SingletonScope::new());
    let di_ctx = Arc::new(InjectionContext::builder(singleton_scope).build());

    let jwt_secret = crate::config::settings::get_jwt_secret()
        .expect("JWT secret must be configured");

    UnifiedRouter::new()
        .mount("/api/", crate::apps::user::urls::url_patterns())
        .mount("/api/", crate::apps::auth::urls::url_patterns())
        .server(|s| {
            s.server_fn(server::login::login::marker)
             .server_fn(server::register::register::marker)
        })
        .with_di_context(di_ctx)
        .with_middleware(SecurityMiddleware::new())
        .with_middleware(JwtAuthMiddleware::from_secret(jwt_secret.as_bytes()))
}
```

### Version Differences for `#[routes]`

- **0.1.x**: Supports flags: `standalone`, `server_only`, `no_client_resolvers`, `no_ws_resolvers`, `client_inventory`
- **0.2.x**: Simplified to inventory registration only. All above flags removed. The macro is ~370 lines (down from ~1460)

### ClientRouter Version Differences

- **0.1.x**: `ClientRouter` has `named_route()`, `named_route_params()`, `named_route_result()`, `named_route_path()`, `named_page()` methods
- **0.2.x**: All `named_*` methods removed. Every `ClientRouter::route*` method requires `name` as mandatory first argument

```rust
// 0.1.x
let router = ClientRouter::new()
    .named_route("/users/:id", "user_detail", handler);

// 0.2.x — name is first positional arg
let router = ClientRouter::new()
    .route("user_detail", "/users/:id", handler);
```

### UnifiedRouter Methods

| Method | Description |
|--------|-------------|
| `.mount(prefix, router)` | Mount an app's `ServerRouter` under a URL prefix |
| `.mount_unified(prefix, router)` | Mount a child `UnifiedRouter` (extracts its server router) |
| `.with_prefix(prefix)` | Set a URL prefix for the entire server router (alternative to `.mount()`) |
| `.with_di_context(ctx)` | Attach the DI injection context |
| `.with_di_registrations(regs)` | Apply deferred DI registrations (e.g., from admin setup) |
| `.with_middleware(mw)` | Add global middleware (e.g., `JwtAuthMiddleware`) |
| `.server(\|s\| { ... })` | Register server functions for Pages/WASM |

### with_prefix vs mount

Two ways to organize routes under a common prefix:

```rust
// Option A: with_prefix — sets prefix on the router itself
pub fn api_routes() -> ServerRouter {
    ServerRouter::new()
        .with_prefix("/api/")
        .endpoint(views::list_users)
        .endpoint(views::create_user)
}

// Option B: mount — parent mounts child under a prefix (used by reinhardt-cloud dashboard)
UnifiedRouter::new()
    .mount("/api/", user_routes())
    .mount("/api/", auth_routes())
```

Endpoint decorators should declare the route-local path, for example
`#[get("/search/sources/", name = "writing_sources_search")]`. Compose broader
prefixes such as `"/api/writing"` in the app route aggregate or `*_urls.rs`
module with `mount` / `with_prefix`, then call routes through reverse helpers.
Do not hardcode the full mounted path inside the handler or rebuild it inside a
function body.

### DI Context Setup

Build an `InjectionContext` with a `SingletonScope` and attach it to the router. Register singletons via `#[injectable]` provider functions (not `set_singleton`). Access the context in middleware via `request.get_di_context::<InjectionContext>()`:

```rust
use reinhardt::di::{InjectionContext, SingletonScope};

// Build DI context in the #[routes] function
let singleton_scope = Arc::new(SingletonScope::new());
let di_ctx = InjectionContext::builder(singleton_scope).build();

UnifiedRouter::new()
    .mount("/api/", app_routes())
    .with_di_context(di_ctx)
```

Register services using `#[injectable]` instead of manual `set_singleton`:

```rust
use reinhardt::di::prelude::*;

#[injectable_key]
struct EmailServiceKey;

#[injectable(scope = "singleton")]
async fn create_email_service(
    #[inject] config: AppConfig,
) -> FactoryOutput<EmailServiceKey, EmailService> {
    FactoryOutput::new(EmailService::new(&config.email_api_key))
}
```

Access the DI context:

```rust
// In middleware: from the request
let ctx = request.get_di_context::<InjectionContext>();

// In #[injectable]: global function
use reinhardt::di::{get_di_context, ContextLevel};
let ctx = get_di_context(ContextLevel::Root);    // singleton scope context
let ctx = get_di_context(ContextLevel::Current); // request/transient scope context
```

## URL Path Parameters

URL patterns support path parameters using `{param}` syntax. Parameters are extracted via the `Path<T>` extractor in the handler signature:

```rust
// Single path parameter
#[get("/users/{id}/", name = "user_retrieve")]
pub async fn get_user(Path(id): Path<i64>) -> ViewResult<Response> {
    // id is extracted as i64 from the URL
    let user = User::objects().get(id).await?;
    // ...
}

// Multiple path parameters (use a tuple)
#[get("/users/{user_id}/posts/{post_id}/", name = "user_post_retrieve")]
pub async fn get_user_post(
    Path((user_id, post_id)): Path<(i64, i64)>,
) -> ViewResult<Response> {
    // ...
}

// String path parameter
#[get("/users/{username}/", name = "user_by_name")]
pub async fn get_by_username(Path(username): Path<String>) -> ViewResult<Response> {
    // ...
}
```

## Mounting and Nesting

Routers can be nested to any depth:

```rust
pub fn api_v1_router() -> ServerRouter {
    ServerRouter::new()
        .endpoint(views::v1::list_users)
        .endpoint(views::v1::get_user)
}

pub fn root_router() -> UnifiedRouter {
    UnifiedRouter::new()
        .mount("/api/v1/users/", api_v1_router())
        .mount("/api/v2/users/", api_v2_router())
}
```

This produces routes like:

- `GET /api/v1/users/` -> `views::v1::list_users`
- `GET /api/v2/users/` -> `views::v2::list_users`

## Per-Route Middleware

Apply middleware to specific routes or groups of routes:

```rust
use reinhardt::middleware::prelude::*;

pub fn router() -> ServerRouter {
    let mut router = ServerRouter::new();

    // Public routes (no auth required)
    router.endpoint(views::health_check);
    router.endpoint(views::login);

    // Protected group with authentication middleware
    let mut protected = ServerRouter::new();
    protected.middleware(AuthenticationMiddleware::new());
    protected.endpoint(views::get_profile);
    protected.endpoint(views::update_settings);
    router.include("/", protected);

    // Admin group with additional authorization
    let mut admin = ServerRouter::new();
    admin.middleware(AuthenticationMiddleware::new());
    admin.middleware(RequirePermission::new("is_staff"));
    admin.endpoint(views::admin_dashboard);
    admin.endpoint(views::admin_list_users);
    router.include("/admin", admin);

    router
}
```

### Common Middleware

| Middleware | Description |
|-----------|-------------|
| `JwtAuthMiddleware::from_secret(secret)` | JWT authentication (verified pattern from dashboard) |
| `AuthenticationMiddleware` | Validates auth credentials and populates auth state for `AuthInfo` / `CurrentUser` |
| `RequirePermission::new(perm)` | Checks user has the specified permission |
| `CorsMiddleware` | Cross-Origin Resource Sharing headers |
| `RateLimitMiddleware` | Request rate limiting |
| `CompressionMiddleware` | Response compression (gzip, brotli) |
| `LoggingMiddleware` | Request/response logging |
| `SecurityHeadersMiddleware` | Adds security headers (CSP, HSTS, X-Frame-Options) |

---

## Type-Safe URL Resolution

> Requires feature flag: `url-resolver`
>
> **(0.1.x only -- removed in 0.2.x)** In 0.2.x, the type-safe URL reversal layer (`typed.rs`), `UrlReverser`, `ClientUrlReverser`, and `Route::with_name()` are removed.

The `UrlResolver` trait and generated extension traits provide compile-time verified URL resolution, eliminating string-based `reverse()` calls.

### Setup

Enable the feature in `Cargo.toml`:

```toml
[dependencies]
reinhardt = { workspace = true, features = ["url-resolver"] }
```

### Usage

View macros (`#[get]`, `#[post]`, etc.) generate extension traits on `ResolvedUrls` for each named route:

```rust
use reinhardt::urls::prelude::*;

// Given this view:
#[get("/users/{id}/", name = "user_detail")]
pub async fn user_detail(Path(id): Path<i64>) -> ViewResult<Response> { /* ... */ }

// The macro generates a resolution method. Use it like:
let url = ResolvedUrls::user_detail(42);
// url == "/users/42/"
```

### `UrlResolver` Trait

```rust
pub trait UrlResolver {
    fn resolve_url(&self, name: &str, params: &[(&str, &str)]) -> String;
}
```

For dynamic resolution (when the route name is not known at compile time), use the trait method directly.

---

## VersionedRouter / `reinhardt-router` crate (rc.27+)

Since v0.1.0-rc.27, the `VersionedRouter` trait and the `RouteVersionInfo`
value type live in their own published crate, **`reinhardt-router`**, which
sits below `reinhardt-urls` in the dependency graph. This was extracted to
break the previous `reinhardt-urls` ↔ `reinhardt-rest` circular dependency
that had forced two `_stub` placeholders inside `reinhardt-rest::versioning`.

### What it gives you

- `DefaultRouter` and `SimpleRouter` (in `reinhardt-urls`) implement
  `VersionedRouter`, exposing the registered routes' version metadata to
  generic consumers.
- `reinhardt-rest::versioning` now drives namespace-based versioning by
  introspecting any `&impl VersionedRouter`, with the previously
  `///ignore`-d doc examples now runnable.
- A `cargo check` against `--target wasm32-unknown-unknown` keeps the trait
  surface intact across native and WASM via the existing drift-detection
  `const _: fn() = ...` block.

### When you need it

- Building tooling or middleware that needs to enumerate routes per version.
- Feeding a custom `Versioning` implementation in `reinhardt-rest`.

### When you do **not** need it

- Standard route registration through `ServerRouter` / `UnifiedRouter`
  continues to work unchanged. `Model::objects()` of routing — you only
  reach for `VersionedRouter` when you want to introspect.

### Out of scope (rc.29)

`UnifiedRouter` does not yet implement `VersionedRouter` (~1.3 KLOC of
unrelated code in a different module). Track upstream if your tooling
needs it. (#4332)

### Cross-target server-function stubs (rc.27+)

`ServerRouterStub` (the WASM sibling of `ServerRouter`) gained a `server_fn`
no-op stub so chains like `UnifiedRouter::new().server(|s|
s.server_fn(marker))` compile on `wasm32-unknown-unknown` without
`#[cfg(native)]` workarounds at the call site. The `#4185` drift-detection
`const _` was extended to include `.server_fn(())` so future omissions are
caught at WASM compile time. (#4263)

---

## Duplicate Route Name Detection

> **Note**: `UrlReverser` is removed in 0.2.x. The duplicate detection below applies to 0.1.x only.

`UrlReverser::register()` returns `Result<(), DuplicateRouteError>` instead of `()`. `ServerRouter::register_all_routes()` collects all errors and reports them at startup. If two routes share the same `name`, the server will fail to start with a clear error message listing the conflicts.

```rust
// These two routes share the same name — startup will fail
#[get("/users/", name = "user_list")]
pub async fn list_users_v1() -> ViewResult<Response> { /* ... */ }

#[get("/api/users/", name = "user_list")]  // ERROR: duplicate name "user_list"
pub async fn list_users_v2() -> ViewResult<Response> { /* ... */ }
```

Ensure all route `name` values are unique across the entire application.
