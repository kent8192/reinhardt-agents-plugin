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
| `#[inject] AuthUser(user): AuthUser<User>` | Full user model resolution | `user.username` |

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
    #[inject] reinhardt::AuthUser(user): reinhardt::AuthUser<User>,
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
| `AuthUser<T>` | Full user model resolution from auth token |
| `Depends<T>` | Shared service from the DI container |
| `Depends<DatabaseConnection>` | Database connection from the pool |

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

    fn get_permissions(&self) -> Vec<Box<dyn Permission>> {
        vec![Box::new(IsAuthenticated)]
    }
}
```

## Server Functions (Pages/WASM)

For full-stack applications scaffolded with `--with-pages`, server functions
allow RPC-style calls from client-side WASM. The decorator is `#[server_fn]`
(NOT `#[server]`):

```rust
use reinhardt::pages::prelude::*;

#[server_fn]
pub async fn login(username: String, password: String) -> Result<AuthResponse, ServerFnError> {
    let user = authenticate(&username, &password).await?;
    let token = create_jwt_token(&user)?;
    Ok(AuthResponse { token, user_id: user.id })
}

#[server_fn]
pub async fn get_user_profile(user_id: i64) -> Result<UserProfile, ServerFnError> {
    let db = use_context::<DatabaseConnection>()?;
    let user = User::objects().get(user_id).await?;
    Ok(UserProfile::from(user))
}
```

### `FromRequest` extractors in server functions (rc.18+)

Since rc.18, `#[server_fn]` accepts `FromRequest`-based extractors
(`Validated`, `Json`, `Form`, `Header`, `Cookie`, `Path`, `Query`, `Body`,
`AuthUser<U>`, etc.) as first-class parameters. They are resolved on the
server via `FromRequest::from_request` and **excluded from the WASM client's
argument struct**, so the client call site only passes the
data-shaped parameters.

```rust
#[server_fn]
pub async fn submit_vote(
    poll_id: i64,                            // Sent from the client
    choice_id: i64,                          // Sent from the client
    AuthUser(user): AuthUser<User>,          // Server-side only
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
reference (`${CLAUDE_PLUGIN_ROOT}/skills/macros/references/proc-macros.md`).

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
