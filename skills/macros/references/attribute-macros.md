# Reinhardt Attribute Macros Reference

All attribute macros are re-exported through the `reinhardt` facade crate.

---

## Model & Data

### `#[model]`

**Crate:** `reinhardt-core/macros`

Define a database model with automatic trait derivation.

```rust
#[model(app_label = "blog")]
pub struct Post {
    #[field(primary_key)]
    pub id: Option<Uuid>,

    #[field(unique)]
    pub slug: String,

    #[field]
    pub title: String,

    #[field]
    pub content: String,

    #[field]
    pub is_published: bool,

    #[field(auto_now_add = true)]
    pub created_at: DateTime<Utc>,

    #[field(null = true)]
    pub updated_at: Option<DateTime<Utc>>,
}
```

**Options:**

| Option | Type | Description |
|--------|------|-------------|
| `app_label` | `&str` | App this model belongs to (required) |
| `manager` | `Path` | (rc.23+, #3981) Opt the model into a user-supplied `CustomManager` implementor. Emits a `HasCustomManager` impl that wires the model to the named type. `Model::objects()` is untouched and still returns `Manager<Self>`. See `modeling/references/model-patterns.md` for usage examples and `modeling/references/queryset-api.md` for the trait surface. |
| `info` | `bool` | **(0.2.x)** Opt-out of auto-generated `{Model}Info` companion struct. Set `info = false` to disable. Defaults to `true` in 0.2.x. |

**Auto-derives:** `Model`, `Serialize`, `Deserialize`, `Clone`, `Debug`

**UUID Generation:** For `Option<Uuid>` primary key fields, the `#[model]` macro generates `Uuid::now_v7()` (UUID v7, time-ordered) instead of `Uuid::new_v4()`. UUID v7 provides better B-tree index performance due to temporal ordering.

**Generated:** `Model` trait implementation with `fn objects() -> Manager<Self>`, field accessors, table name derivation.

### Field Attributes (`#[field(...)]`)

| Attribute | Type | Description |
|-----------|------|-------------|
| `primary_key` | flag | Mark as primary key |
| `required` | flag | Field is required (NOT NULL) |
| `unique` | flag | Unique constraint |
| `index` | flag | Create database index |
| `default` | value | Default value |
| `generated = SchemaExpr::...` | expression | **(0.4.x)** Portable, typed generated-column expression. Pair with exactly one storage flag. |
| `generated_sql = "..."` | `&str` | **(0.4.x)** Trusted backend-specific generated-column expression when `SchemaExpr` cannot represent it. |
| `generated_stored = true` | `bool` | **(0.4.x)** Store the generated value. |
| `generated_virtual = true` | `bool` | **(0.4.x, MySQL/SQLite)** Compute the generated value virtually. |
| `rename = "..."` | `&str` | Custom database column name |
| `min` | number | Minimum value (numeric) |
| `max` | number | Maximum value (numeric) |
| `skip_info` | `bool` | **(0.2.x)** Exclude this field from the auto-generated `{Model}Info` struct. Set `skip_info = true` to omit. |

Use `#[field]` even when a scalar field has no options. This keeps field
metadata complete for migrations, validation, serializers, admin, and generated
`{Model}Info` structs.

### Typed Generated Columns (0.4.x)

Use the portable `SchemaExpr` subset for `generated`: `col`, `val`, `concat`,
`coalesce`, and chained `binary` / `cast` calls. For a backend-specific trusted
fragment, use the explicit `generated_sql` escape hatch instead of a raw string
in `generated`.

```rust
use reinhardt::db::migrations::SchemaExpr;

#[field(
    max_length = 201,
    generated = SchemaExpr::concat([
        SchemaExpr::col("first_name"),
        SchemaExpr::val(" "),
        SchemaExpr::col("last_name"),
    ]),
    generated_stored = true,
)]
pub full_name: String,
```

`generated` and `generated_sql` are mutually exclusive. Specify exactly one
storage mode: `generated_stored = true`, or `generated_virtual = true` for
MySQL/SQLite. Generated columns cannot have a default or auto-increment; they
are read-only and must not be included in create/update DTOs or partial updates.

### Relationship Attributes (`#[rel(...)]`)

| Attribute | Type | Description |
|-----------|------|-------------|
| `foreign_key` | flag | ForeignKey relationship |
| `many_to_many` | flag | ManyToMany relationship |
| `one_to_one` | flag | OneToOne relationship |
| `related_model = "..."` | `&str` | Target model name |
| `on_delete = "..."` | `&str` | Cascade behavior |

### ORM Attributes

| Attribute | Description |
|-----------|-------------|
| `#[orm_field(type = "...")]` | Override ORM field type |
| `#[orm_relationship(type = "...")]` | Override relationship type |
| `#[orm_ignore]` | Exclude field from ORM reflection |

---

### `#[user]`

**Crate:** `reinhardt-core/macros`

Auto-implement auth traits (`BaseUser`, `AuthIdentity`) for a user model.

```rust
#[model(app_label = "accounts")]
#[user(hasher = Argon2Hasher, username_field = "email")]
pub struct User {
    #[field(primary_key)]
    pub id: Option<Uuid>,
    #[field(unique)]
    pub email: String,
    pub password_hash: Option<String>,
    pub is_active: bool,
    pub is_staff: bool,
    pub is_superuser: bool,
    pub last_login: Option<DateTime<Utc>>,
}
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hasher` | Type | (required) | Password hasher (e.g., `Argon2Hasher`) |
| `username_field` | `&str` | `"username"` | Unique identifier field |

**Generated:** `BaseUser` and `AuthIdentity` trait implementations.

---

### `#[document]`

**Crate:** `reinhardt-db-macros`

Define a NoSQL ODM document (e.g., MongoDB).

```rust
#[document(collection = "users", backend = "mongodb")]
pub struct UserDocument {
    #[field(primary_key)]
    pub id: String,
    #[field(required, unique)]
    pub email: String,
    #[field(index)]
    pub username: String,
}
```

---

## Views & Routing

### HTTP Method Decorators

**Crate:** `reinhardt-core/macros`

| Macro | HTTP Method |
|-------|-------------|
| `#[get]` | GET |
| `#[post]` | POST |
| `#[put]` | PUT |
| `#[patch]` | PATCH |
| `#[delete]` | DELETE |

**Common Options:**

| Option | Type | Description |
|--------|------|-------------|
| `path` | `&str` | URL pattern (1st positional arg) |
| `name` | `&str` | View name for URL reversal |
| `use_inject` | `bool` | Enable `#[inject]` on parameters |
| `pre_validate` | `bool` | Run validation before handler |

Examples that inject `Depends<PrimaryDatabase, DatabaseConnection>` assume a
database provider key in scope:

```rust
#[injectable_key]
struct PrimaryDatabase;
```

```rust
#[get("/users/{id}/", name = "user_detail", use_inject = true)]
pub async fn user_detail(
    Path(id): Path<Uuid>,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
) -> ViewResult<Response> {
    // ...
}

#[post("/users/", name = "create_user")]
pub async fn create_user(
    Json(data): Json<CreateUserRequest>,
) -> ViewResult<Response> {
    // ...
}
```

### `#[api_view]`

**Crate:** `reinhardt-core/macros`

Decorator for function-based API views (Django REST Framework style).

```rust
#[api_view("GET", "POST")]
pub async fn user_list(request: Request) -> ViewResult<Response> {
    match request.method() {
        Method::GET => { /* list users */ }
        Method::POST => { /* create user */ }
        _ => unreachable!(),
    }
}
```

### `#[action]`

**Crate:** `reinhardt-core/macros`

Define custom ViewSet actions beyond standard CRUD.

```rust
impl UserViewSet {
    #[action(["POST"], detail = true)]
    pub async fn activate(&self, request: Request, pk: Uuid) -> ViewResult<Response> {
        // Custom action: POST /users/{pk}/activate/
    }

    #[action(["GET"], detail = false)]
    pub async fn recent(&self) -> ViewResult<Response> {
        // Custom action: GET /users/recent/
    }
}
```

**Options:**

| Option | Type | Description |
|--------|------|-------------|
| methods | `[&str]` | Allowed HTTP methods |
| `detail` | `bool` | `true` for instance-level, `false` for collection-level |

### `#[url_patterns]`

**Removed in 0.2.x.** This macro is entirely removed in 0.2.x. Use `#[routes]` for URL pattern registration instead.

In 0.1.3, `#[url_patterns]` was a legacy attribute for registering URL patterns. All new code should use `#[routes]`.

---

### `#[routes]`

**Crate:** `reinhardt-core/macros`

Register URL patterns for automatic discovery. The macro forces `pub` visibility on the decorated function and automatically emits `#[allow(private_interfaces)]`, so returning a newtype-wrapped `UnifiedRouter` (e.g., `pub(crate)` types required by the DI pseudo orphan rule) does not produce warnings.

```rust
#[routes]
fn routes() -> UnifiedRouter {
    UnifiedRouter::new()
        .mount("/api/users/", user_views::routes())
        .mount("/api/posts/", post_views::routes())
}
```

Newtype pattern (required when the pseudo orphan rule applies to router types):

```rust
pub(crate) struct AppRouter(pub UnifiedRouter);

#[routes]
fn routes() -> AppRouter {
    AppRouter(
        UnifiedRouter::new()
            .mount("/api/", app_routes())
    )
}
// No `private_interfaces` warning — suppressed by the macro
```

#### 0.2.x Changes

- Simplified to inventory registration only (~370 lines, down from ~1460)
- Removed flags: `standalone`, `server_only`, `no_client_resolvers`, `no_ws_resolvers`, `client_inventory`
- Per-app struct generation, `ResolvedUrls`, `url_prelude`, callback macros all removed
- Three function forms preserved: sync, async, async with `#[inject]`

---

## Dependency Injection

### `#[inject]`

**Crate:** `reinhardt-core/macros` (used inside handlers)

Mark a parameter for DI resolution.

```rust
#[get("/config/", name = "config_info", use_inject = true)]
pub async fn config_info(
    #[inject] config: AppConfig,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
    #[inject(cache = false)] counter: RequestCounter,  // Fresh instance each time
) -> ViewResult<Response> {
    // ...
}
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache` | `bool` | `true` | Cache the resolved instance |

### `#[no_inject]`

Exclude a field from DI injection (used in `#[injectable]` structs).

### `#[use_inject]`

**Crate:** `reinhardt-core/macros`

Enable `#[inject]` in general async functions (not just handlers).

```rust
#[use_inject]
pub async fn process_data(
    #[inject] config: AppConfig,
    data: Vec<u8>,
) -> Result<(), Error> {
    // Can use #[inject] outside of HTTP handlers
}
```

### `#[injectable]`

**Crate:** `reinhardt-di/macros`

Mark a struct as injectable with automatic DI registration. Auto-derives `Clone` if not already present.

```rust
#[injectable]
#[scope(singleton)]
pub struct AppConfig {
    pub app_name: String,
    pub version: String,
    pub max_items_per_page: usize,
}
// Clone is auto-derived — no need for #[derive(Clone)]
```

**Associated Attributes:**

| Attribute | Description |
|-----------|-------------|
| `#[scope(singleton)]` | Singleton scope (default) |
| `#[scope(request)]` | Request scope |
| `#[scope(transient)]` | Transient scope (new instance each time) |

### `#[injectable]` Provider Functions

**Crate:** `reinhardt-di/macros`

Mark an async function as a dependency provider with automatic registration.
In 0.3.x, provider functions are async-only. Return `FactoryOutput<K, T>` when the produced value type needs an
explicit provider identity. `#[injectable_factory]` remains only as a deprecated
0.2 compatibility alias.
The `DbSettings` parameter below represents an application-owned settings type
or fragment that your app has registered as an injectable value.

```rust
use reinhardt::di::{FactoryOutput, injectable, injectable_key};

#[injectable_key]
struct PrimaryDatabase;

#[injectable(scope = "singleton")]
async fn create_db_pool(
    #[inject] settings: DbSettings,
) -> FactoryOutput<PrimaryDatabase, DatabaseConnection> {
    FactoryOutput::new(DatabaseConnection::connect(&settings.database_url).await.unwrap())
}
```

---

## Configuration

### `#[settings]`

**Crate:** `reinhardt-core/macros`

Composable configuration — fragment mode or composition mode.

```rust
// Fragment mode
#[settings(fragment = true, section = "cache")]
pub struct CacheSettings {
    pub backend: String,
    pub timeout: u64,
}

// Composition mode
#[settings]
pub struct ProjectSettings {
    pub debug: bool,
    pub allowed_hosts: Vec<String>,
    pub cache: CacheSettings,
}
```

### `#[app_config]`

**Crate:** `reinhardt-core/macros`

Generate AppConfig factory method for app registration.

```rust
#[app_config(name = "blog", label = "Blog")]
pub struct BlogConfig;
```

---

## Admin

### `#[admin]`

**Crate:** `reinhardt-core/macros`

ModelAdmin configuration with compile-time validation.

```rust
#[admin(
    for = User,
    name = "User",
    list_display = [id, username, email, is_active],
    list_filter = [is_active, is_staff],
    search_fields = [username, email],
)]
pub struct UserAdmin;
```

---

## Auth

### `#[permission_required]`

**Crate:** `reinhardt-core/macros`

Attribute-based permission check on views.

```rust
#[permission_required("users.can_edit")]
#[get("/users/{id}/edit/", name = "edit_user")]
pub async fn edit_user(Path(id): Path<Uuid>) -> ViewResult<Response> {
    // Only users with "users.can_edit" permission
}
```

---

## Server Hooks

### `#[hook(on = runserver)]`

**Crate:** `reinhardt-core/macros`

Define a hook that runs during server startup lifecycle. The hook is auto-registered via `inventory::collect!`.

```rust
use reinhardt::commands::prelude::*;

#[hook(on = runserver)]
pub struct MigrationCheck;

#[async_trait]
impl RunserverHook for MigrationCheck {
    async fn validate(&self) -> Result<(), Box<dyn Error + Send + Sync>> {
        // Called before server starts — validate preconditions
        check_pending_migrations().await
    }

    async fn on_server_start(
        &self,
        ctx: &RunserverContext,
    ) -> Result<(), Box<dyn Error + Send + Sync>> {
        // Called after server binds to port
        log::info!("Server started successfully");
        Ok(())
    }
}
```

**Options:**

| Option | Type | Description |
|--------|------|-------------|
| `on` | identifier | Hook lifecycle point. Currently only `runserver` is supported. |

**Requirements:**

- Must be applied to a **unit struct** (no fields, no generics)
- Struct must implement `RunserverHook` trait
- Registered automatically via `inventory::collect!`

**`RunserverHook` trait methods:**

| Method | When Called | Required |
|--------|------------|----------|
| `validate(&self)` | Before DI setup and server start | No (default: `Ok(())`) |
| `on_server_start(&self, ctx: &RunserverContext)` | After server binds to port, DI ready | No (default: `Ok(())`) |

---

## Partial Updates

### `#[apply_update]`

**Crate:** `reinhardt-core/macros`

Apply partial updates to target structs.

```rust
#[apply_update(target(User, Profile))]
pub struct UpdateUserRequest {
    pub display_name: Option<String>,
    pub bio: Option<String>,
}
```

---

## Frontend (Pages/WASM)

### `#[component]` (0.4.0-alpha.1+)

**Crate:** `reinhardt-pages/macros`

Define a route-backed Page component. The macro emits route metadata consumed
by `ClientRouter::component(...)`.

```rust
use reinhardt_pages::{Page, Path, component, page};
use reinhardt_urls::routers::ClientRouter;

#[component("/users/{id}/", name = "user-detail")]
fn user_page(Path(id): Path<i64>) -> Page {
    page!(|id: i64| {
        div { { id.to_string() } }
    })(id)
}

let router = ClientRouter::new().component(user_page);
```

The `name` argument is required, must be a string literal, and is the public
route name. Do not use `#[component("/path/", "name")]`,
`#[component("/path/", route_name)]`, or `name = route_name`; all three forms
are rejected. Migrate a positional string mechanically to `name = "..."`, but
choose the public name explicitly when replacing an identifier shorthand.

---

### `#[server_fn]`

**Crate:** `reinhardt-pages/macros`

Define server RPC functions callable from WASM frontend.

```rust
#[server_fn(endpoint = "/api/users")]
pub async fn get_users() -> Result<Vec<User>, ServerFnError> {
    let users = User::objects().all().await?;
    Ok(users)
}
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `endpoint` | `&str` | auto-generated | Custom endpoint path |
| `codec` | `&str` | `"json"` | Serialization: `json`, `url`, `msgpack` |

**`FromRequest` extractors as parameters (rc.18+):**

Since rc.18, `#[server_fn]` accepts the same `FromRequest`-based extractors as
`#[view]` handlers. The macro resolves them via `FromRequest::from_request`
on the server side and excludes them from the WASM client's argument struct,
so they do not appear in client-side call sites.

```rust
use reinhardt::pages::prelude::*;
use reinhardt::http::{Json, Query, Path, Header, Cookie, Form, Body};
use reinhardt::http::extractors::Validated;

#[server_fn]
pub async fn create_post(
    title: String,                        // Sent from the client
    body: String,                         // Sent from the client
    Validated(payload): Validated<NewPostPayload>, // Server-side, not in client args
    CurrentUser(user): CurrentUser<User>, // Server-side
) -> Result<Post, ServerFnError> {
    // ...
}
```

Supported extractor types include `Validated<T>`, `Json<T>`, `Form<T>`,
`Header<H>`, `Cookie<C>`, `Path<P>`, `Query<Q>`, `Body`, and any type
implementing `FromRequest`. The CSRF-specific implicit `__csrf_token`
auto-injection that existed before rc.22 has been generalized into the
explicit `form!` `strip_arguments` mechanism — see the `form!` reference
in `proc-macros.md`.

**Cross-target WASM marker module (rc.27+, #4293):**

From rc.27, `#[server_fn]` reliably emits a per-function WASM marker module
(`get_users::marker` and friends) on `wasm32-*` targets. The marker carries
the typed `Args` struct and the `#response_type` token so frontend code can
call `worker.handle_server_fn::<get_users::marker>(...)` against MSW-style
mock workers in WASM tests. Two bugs that previously prevented the marker
from being emitted were fixed in #4293:

- The `msw_enabled` gate no longer consults `CARGO_FEATURE_MSW` (proc-macro
  expansion never has that env var set; the macro now relies on Cargo's
  transitive feature unification through `cfg!(feature = "msw")`).
- The WASM marker module body now includes `use super::*;` so user types
  like `VoteRequest` or `(QuestionInfo, Vec<ChoiceInfo>)` resolve inside
  the generated `Args` struct and `#response_type` slot.

No source-level changes are required to pick up the marker — rebuilding
on rc.27+ with the `msw` feature enabled is sufficient.

---

## gRPC & GraphQL

### `#[grpc_handler]`

**Crate:** `reinhardt-grpc/macros`

gRPC service method with DI support.

```rust
#[grpc_handler]
pub async fn get_user(
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
    request: Request<GetUserRequest>,
) -> Result<Response<UserResponse>, Status> {
    // ...
}
```

### `#[graphql_handler]`

**Crate:** `reinhardt-graphql/macros`

GraphQL resolver with DI support.

```rust
#[graphql_handler]
pub async fn get_user(
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
    ctx: &Context<'_>,
) -> Result<User, Error> {
    // ...
}
```

## Dynamic References

For the latest macro definitions:

1. Read `reinhardt/crates/reinhardt-core/macros/src/lib.rs` for core attribute macros
2. Read `reinhardt/crates/reinhardt-di/macros/src/lib.rs` for DI attribute macros
3. Read `reinhardt/crates/reinhardt-db-macros/src/lib.rs` for #[document]
4. Read `reinhardt/crates/reinhardt-pages/macros/src/lib.rs` for #[server_fn]
5. Read `reinhardt/crates/reinhardt-grpc/macros/src/lib.rs` for #[grpc_handler]
6. Read `reinhardt/crates/reinhardt-graphql/macros/src/lib.rs` for #[graphql_handler]
