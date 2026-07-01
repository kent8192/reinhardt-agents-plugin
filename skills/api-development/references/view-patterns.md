# Reinhardt View Patterns Reference

## Function-Based Views with Decorators

Handler functions use HTTP method decorators (`#[get]`, `#[post]`, `#[put]`, `#[patch]`, `#[delete]`) to declare their route and method. Handlers are async and return `ViewResult<Response>`.

```rust
use reinhardt::views::prelude::*;
use reinhardt::core::exception::Error as AppError;
use reinhardt::core::serde::json;

#[get("/users/{id}/", name = "user_retrieve")]
pub async fn get_user(Path(id): Path<i64>) -> ViewResult<Response> {
    let user = User::objects()
        .get(id)
        .await
        .map_err(|_| AppError::NotFound("User not found".into()))?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(user))?))
}

#[post("/users/", name = "user_create")]
pub async fn create_user(Json(body): Json<CreateUserRequest>) -> ViewResult<Response> {
    body.validate()?;
    let user = User::objects().create_from(&body).await?;

    Ok(Response::new(StatusCode::CREATED)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(user))?))
}

#[patch("/users/{id}/", name = "user_update")]
pub async fn update_user(
    Path(id): Path<i64>,
    Json(body): Json<UpdateUserRequest>,
) -> ViewResult<Response> {
    body.validate()?;
    let user = User::objects().get(id).await?;
    let updated = user.update_from(&body).await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(updated))?))
}

#[put("/users/{id}/", name = "user_replace")]
pub async fn replace_user(
    Path(id): Path<i64>,
    Json(body): Json<CreateUserRequest>,
) -> ViewResult<Response> {
    body.validate()?;
    let user = User::objects().get(id).await?;
    let replaced = user.replace_from(&body).await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(replaced))?))
}

#[delete("/users/{id}/", name = "user_delete")]
pub async fn delete_user(Path(id): Path<i64>) -> ViewResult<Response> {
    let user = User::objects().get(id).await?;
    user.delete().await?;
    Ok(Response::new(StatusCode::NO_CONTENT))
}
```

### Decorator Options

| Option | Description | Example |
|--------|-------------|---------|
| `name = "..."` | Named route for reverse URL lookup | `#[get("/users/", name = "user_list")]` |
| `pre_validate = true` | Run validation before handler body | `#[post("/users/", name = "user_create", pre_validate = true)]` |

Decorator paths should stay local to the app/router, such as
`"/search/sources/"`. Compose app and API prefixes such as `"/api/writing"` in
the route aggregate or `*_urls.rs` module with `mount`/`with_prefix`, and use
reverse helpers at call sites instead of rebuilding full paths in handlers.

### Return Type

All handlers return `ViewResult<Response>`. This is an alias for `Result<Response, AppError>` where errors are automatically converted to HTTP error responses.

### Extractors

Extractors pull typed data from the incoming request:

| Extractor | Description | Example |
|-----------|-------------|---------|
| `Path(id): Path<i64>` | URL path parameter | `#[get("/users/{id}/")]` |
| `Json(body): Json<T>` | JSON request body (requires `T: Deserialize`) | `#[post("/users/")]` |
| `Query(params): Query<T>` | Query string parameters (requires `T: Deserialize`) | `?page=1&per_page=20` |
| `#[inject] AuthInfo(state): AuthInfo` | Lightweight auth state (JWT-based) | `state.user_id()` |
| `#[inject] CurrentUser(user): CurrentUser<User>` | Full user model resolution | `user.username` |

```rust
#[get("/users/", name = "user_list")]
pub async fn list_users(Query(params): Query<PaginationParams>) -> ViewResult<Response> {
    let users = User::objects()
        .paginate(params.page, params.per_page)
        .await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&users)?))
}
```

### Request/Response Serialization

Request types use `Deserialize`, `Validate`, and `Schema`:

```rust
#[derive(Debug, Clone, Deserialize, Validate, Schema)]
pub struct CreateUserRequest {
    pub username: String,
    pub email: String,
}
```

Response types use `Serialize` and `Schema`:

```rust
#[derive(Debug, Serialize, Schema)]
pub struct UserResponse {
    pub id: i64,
    pub username: String,
    pub email: String,
}
```

JSON serialization uses the reinhardt-provided module:

```rust
use reinhardt::core::serde::json;
let bytes = json::to_vec(&response_data)?;
```

## Views with Dependency Injection

Use `#[inject]` to receive services and auth context from the DI container:

```rust
use reinhardt::di::prelude::*;
use reinhardt::CurrentUser;
use reinhardt::views::prelude::*;

#[get("/profile/", name = "user_profile")]
pub async fn get_profile(
    #[inject] AuthInfo(state): AuthInfo,
) -> ViewResult<Response> {
    let user_id = state.user_id();
    let user = User::objects().get(user_id).await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&ProfileResponse::from(user))?))
}

#[get("/admin/users/", name = "admin_user_list")]
pub async fn admin_list_users(
    #[inject] CurrentUser(user): CurrentUser<User>,
    Query(params): Query<PaginationParams>,
) -> ViewResult<Response> {
    if !user.is_staff {
        return Err(AppError::Authentication("Admin access required".into()));
    }
    let users = User::objects().all().await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&users)?))
}
```

### Common Injectable Types

| Type | Description |
|------|-------------|
| `AuthInfo` | Lightweight JWT auth state with `state.user_id()` |
| `CurrentUser<T>` | Full user model resolution from auth token or session |
| `T` | Direct injectable service/configuration value from the DI container |
| `Depends<K, T>` | Keyed provider output from the DI container |
| `Depends<PrimaryDatabase, DatabaseConnection>` | Keyed database connection from the pool |

### Endpoint-local workflows with shared DI dependencies

Use DI for common dependencies that several endpoints share. Keep
endpoint-specific validation, DTO assembly, persistence ordering, generation
steps, and response shaping in the handler or in a private helper beside it.
Do not create `OutlineService`, `ManuscriptService`, or `DocumentService`
facades that merely hide a single endpoint flow.

Do not move the same handler script into `server/`, `service/`, or `services/`
only to shorten the endpoint. Extraction should expose a smaller helper contract,
a reusable dependency, or a focused test target. If the helper still owns the
request DTO, response DTO, persistence order, and provider sequence, it is still
endpoint-local workflow.

Inline and delete a helper that is used only by one endpoint section and only
delegates the same request data, dependencies, persistence order, and provider
sequence. Keep a helper when it returns a narrower domain value, isolates a
named invariant, or has another caller.

Keep simple `Model::objects()` CRUD at the handler call site. Local `NotFound`
mapping, project/tenant ownership checks, ordering, and DTO conversion are still
part of the endpoint flow when they are unique to that route. Do not introduce
semantic wrappers such as `get_project_model`, `list_document_chunks`, or
`document_path` when they only hide one direct ORM query or trivial field/path
derivation.

```rust
// Avoid: this hides the model, filter, ownership guard, and NotFound behavior.
let project = get_project_model(project_id).await?;
let chunks = list_document_chunks(document_id).await?;
let path = document_path(project_id, document_id);

// Prefer: keep direct CRUD and endpoint-specific mapping visible.
let project = Project::objects()
    .get(project_id)
    .await
    .map_err(|_| AppError::NotFound("Project not found".into()))?;
ensure_project_owner(&project, current_user.id)?;

let chunks = DocumentChunk::objects()
    .filter_by(DocumentChunk::field_document_id().eq(document_id))
    .order_by(&["position"])
    .all()
    .await?;
let response = DocumentChunksResponse::from_models(chunks);
```

Extract a helper/service only when it owns reusable domain behavior beyond
simple CRUD, such as transaction boundaries, cross-model orchestration, provider
calls, parsing/chunking, projection building, or nontrivial state transitions.

```rust
use reinhardt::di::Depends;
use reinhardt::views::prelude::*;

#[post("/outlines/{id}/regenerate/", name = "outline_regenerate")]
pub async fn regenerate_outline(
    Path(id): Path<Uuid>,
    Json(input): Json<RegenerateOutlineRequest>,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
    #[inject] providers: Depends<AiProviderRegistryKey, ProviderRegistry>,
) -> ViewResult<Response> {
    input.validate()?;

    let current = Outline::objects().get(id, &*db).await?;
    let draft = build_outline_revision(&providers, &current, &input).await?;
    let revision = OutlineRevision::from_draft(id, draft);
    let saved = OutlineRevision::objects()
        .create_with_conn(&*db, &revision)
        .await?;

    Ok(Response::new(StatusCode::CREATED)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&OutlineRevisionResponse::from_model(&saved))?))
}

async fn build_outline_revision(
    providers: &ProviderRegistry,
    current: &Outline,
    input: &RegenerateOutlineRequest,
) -> Result<OutlineDraft, AppError> {
    providers.outliner(input.provider).regenerate(current, input).await
}
```

## Generic Views

Generic views provide pre-built CRUD behavior. Override methods for customization.

### ListView

```rust
use reinhardt::views::generic::*;

pub struct UserListView;

impl ListView for UserListView {
    type Model = User;
    type Serializer = UserSerializer;

    fn get_queryset(&self) -> QuerySet<User> {
        User::objects().filter(User::is_active.eq(true))
    }

    fn get_pagination(&self) -> Option<Box<dyn Pagination>> {
        Some(Box::new(PageNumberPagination::new(20)))
    }
}
```

### DetailView

```rust
pub struct UserDetailView;

impl DetailView for UserDetailView {
    type Model = User;
    type Serializer = UserSerializer;
    type LookupField = i64;

    fn get_object(&self, id: Self::LookupField) -> QuerySet<User> {
        User::objects().filter(User::id.eq(id))
    }
}
```

### CreateView

```rust
pub struct UserCreateView;

impl CreateView for UserCreateView {
    type Model = User;
    type Serializer = UserCreateSerializer;

    fn perform_create(&self, serializer: &Self::Serializer) -> Result<User, ApiError> {
        serializer.save()
    }
}
```

### UpdateView and DestroyView

```rust
pub struct UserUpdateView;

impl UpdateView for UserUpdateView {
    type Model = User;
    type Serializer = UserSerializer;
    type LookupField = i64;
}

pub struct UserDestroyView;

impl DestroyView for UserDestroyView {
    type Model = User;
    type LookupField = i64;
}
```

### ViewSet (Combines All CRUD)

```rust
pub struct UserViewSet;

impl ViewSet for UserViewSet {
    type Model = User;
    type Serializer = UserSerializer;
    type CreateSerializer = UserCreateSerializer;
    type LookupField = i64;

    fn get_queryset(&self) -> QuerySet<User> {
        User::objects().all()
    }

}

fn user_handler() -> ModelViewSetHandler<User> {
    ModelViewSetHandler::<User>::new()
        .add_permission(std::sync::Arc::new(IsAuthenticated))
}
```

## Server Functions (Pages/WASM)

For full-stack applications scaffolded with `--with-pages`, server functions
allow RPC-style calls from client-side WASM. The decorator is `#[server_fn]`
(NOT `#[server]`). Keep `#[server_fn]` functions as request/response
boundaries: validate input, inject shared keyed services, and keep
endpoint-specific DTO/persistence flow visible unless a narrower service
contract is reused across endpoints.

```rust
use reinhardt::di::Depends;
use reinhardt::pages::prelude::*;

use crate::apps::accounts::services::{
    AuthService,
    AuthServiceKey,
    UserProfileService,
    UserProfileServiceKey,
};

#[server_fn]
pub async fn login(
    username: String,
    password: String,
    #[inject] auth: Depends<AuthServiceKey, AuthService>,
) -> Result<AuthResponse, ServerFnError> {
    (*auth).login(username, password).await.map_err(ServerFnError::from)
}

#[server_fn]
pub async fn get_user_profile(
    user_id: i64,
    #[inject] profiles: Depends<UserProfileServiceKey, UserProfileService>,
) -> Result<UserProfile, ServerFnError> {
    (*profiles).get(user_id).await.map_err(ServerFnError::from)
}
```

Register shared business services in the app's `services/` module with the
Reinhardt 0.3 provider shape:

```rust
use reinhardt::di::{Depends, FactoryOutput, injectable, injectable_key};

#[injectable_key]
pub struct AuthServiceKey;

#[injectable(scope = "request")]
async fn auth_service(
    #[inject] settings: Depends<AppSettingsKey, AppSettings>,
) -> FactoryOutput<AuthServiceKey, AuthService> {
    FactoryOutput::new(AuthService::from_settings(&*settings))
}
```

Keep provider adapters, prompt construction, parsing/conversion helpers, and
repository/database internals outside `services/`, for example under app-local
`server/providers`, `server/prompts`, and `server/repositories`. The
`services/` module should expose the DI surface only: keys, provider functions,
and service structs/functions.

### `FromRequest` extractors in server functions (rc.18+)

Since rc.18, `#[server_fn]` accepts `FromRequest`-based extractors
(`Validated`, `Json`, `Form`, `Header`, `Cookie`, `Path`, `Query`, `Body`,
`CurrentUser<U>`, etc.) as first-class parameters. They are resolved on the
server via `FromRequest::from_request` and **excluded from the WASM client's
argument struct**, so the client call site only passes the
data-shaped parameters.

```rust
#[server_fn]
pub async fn submit_vote(
    poll_id: i64,                            // Sent from the client
    choice_id: i64,                          // Sent from the client
    CurrentUser(user): CurrentUser<User>,    // Server-side only
    Validated(meta): Validated<VoteMetadata>, // Server-side only
) -> Result<(), ServerFnError> {
    Vote::record(user.id, poll_id, choice_id, meta).await?;
    Ok(())
}
```

### CSRF tokens via `form!` `strip_arguments` (rc.22+)

Forms that submit through `#[server_fn]` should declare CSRF (or any other
auxiliary value) **explicitly** via the `form!` macro's `strip_arguments`
block instead of relying on the legacy implicit auto-injection. The
auto-injection path remains for backward compatibility but is deprecated;
new code should follow the explicit pattern documented in the `form!`
reference (`../../macros/references/proc-macros.md`).

### Server functions vs service endpoints

Use `#[server_fn]` for browser-to-server RPC from Reinhardt Pages clients. If a
separate worker, agent service, TypeScript process, or third-party client needs
to call the backend, expose an explicit HTTP or gRPC endpoint instead. Pass
runtime details such as callback domain, model/provider selection, and request
scope through typed settings or request fields; do not hardcode them in the
worker or hide them behind a Pages-only server function.

## Response Building

Build responses using `Response::new(StatusCode)` with builder methods:

```rust
// JSON response
Ok(Response::new(StatusCode::OK)
    .with_header("Content-Type", "application/json")
    .with_body(json::to_vec(&data)?))

// No content (e.g., DELETE)
Ok(Response::new(StatusCode::NO_CONTENT))

// Created with location header
Ok(Response::new(StatusCode::CREATED)
    .with_header("Content-Type", "application/json")
    .with_header("Location", &format!("/api/users/{}/", user.id))
    .with_body(json::to_vec(&user_response)?))
```

## Error Handling

Use `AppError` variants from `reinhardt::core::exception::Error`:

| Variant | HTTP Status | Usage |
|---------|-------------|-------|
| `AppError::Validation(msg)` | 400 Bad Request | Invalid input data |
| `AppError::Authentication(msg)` | 401 Unauthorized | Missing or invalid credentials |
| `AppError::NotFound(msg)` | 404 Not Found | Resource does not exist |
| `AppError::Conflict(msg)` | 409 Conflict | Duplicate or conflicting state |

```rust
use reinhardt::core::exception::Error as AppError;

#[get("/users/{id}/", name = "user_retrieve")]
pub async fn get_user(Path(id): Path<i64>) -> ViewResult<Response> {
    let user = User::objects()
        .get(id)
        .await
        .map_err(|_| AppError::NotFound("User not found".into()))?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(user))?))
}
```

For ORM reads and counts, use `Model::objects()` directly unless the app's
service layer owns reusable domain behavior beyond the query. Do not bypass the
model manager with ad hoc low-level builders when the standard manager API
expresses the query.

## ModelViewSet / ReadOnlyModelViewSet (rc.23+)

Since v0.1.0-rc.23, `ModelViewSet<M, S>` and `ReadOnlyModelViewSet<M, S>`
actually execute database CRUD. In prior releases their `dispatch()` returned
`json!([])` / `json!({})` placeholder responses for every verb regardless of
ORM state, even though the surrounding `ModelViewSetHandler<T>` (with
permissions, serializers, pagination, real DB I/O) already existed in the
crate — it just was never wired into the public ViewSet types (#3991).

The regression fix wires both `ModelViewSet::dispatch` and
`ReadOnlyModelViewSet::dispatch` through `ModelViewSetHandler<M>`. A
companion change to `GenericViewSet<T>::dispatch` replaces the bare
`"Action not implemented"` error with a guidance message that points users
at `ModelViewSet`, `ReadOnlyModelViewSet`, or a hand-written `impl ViewSet`.

### Tightened trait bounds (breaking)

`ModelViewSet<M, S>` and `ReadOnlyModelViewSet<M, S>` now require:

- `M: Model + Serialize + DeserializeOwned + Clone + Send + Sync + 'static`
  (previously only `M: Send + Sync`).
- `S: Send + Sync + 'static` (previously only `Send + Sync`), so the
  resulting ViewSet can flow through `ViewSetBuilder`.

In practice these types were only meaningful with a real `Model`, so
production call sites are unaffected. Tests or scaffolding that constructed
`ModelViewSet::<(), ()>` must switch to a real `Model` type.

### Wiring the database pool

Configure the pool with the builder before mounting the ViewSet, otherwise
the handler has nothing to dispatch against:

```rust
use reinhardt::views::viewsets::{DbBackend, ModelViewSet};

let viewset = ModelViewSet::<Item, ItemSerializer>::new("items")
    .with_pool(pool)
    .with_db_backend(DbBackend::Postgres);
```

`ReadOnlyModelViewSet<M, S>` follows the same `.with_pool(...)
.with_db_backend(...)` pattern but only exposes list/retrieve actions.

### `GenericViewSet` error string change

Tests that previously asserted exact-string equality on the
`"Action not implemented"` error now need substring matching against the
new guidance message.

Source: kent8192/reinhardt-web (#3991), resolves #3985.
