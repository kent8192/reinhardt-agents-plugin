# API Testing Reference

## APIClient Usage

The `APIClient` from `reinhardt_test` provides a test HTTP client for making requests against reinhardt views. Use the `api_client` fixture or construct manually.

### Basic Usage with Fixtures

```rust
use reinhardt_test::prelude::*;
use reinhardt_test::fixtures::auth::*;
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_list_users(api_client: APIClient) {
    // Act
    let response = api_client.get("/api/users/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
    let body: Vec<UserResponse> = response.json().unwrap();
    assert!(!body.is_empty());
}
```

### APIClient Construction

| Method | Description |
|--------|-------------|
| `APIClient::new()` | Create with default base URL (`http://testserver`) |
| `APIClient::with_base_url(url)` | Create with custom base URL |
| `APIClient::from_handler(handler)` | In-process dispatch without TCP (full middleware stack) |
| `APIClient::builder()` | Advanced configuration via `APIClientBuilder` |
| `api_client` fixture | rstest fixture providing `APIClient::new()` |
| `api_client_from_url(url)` | Helper for creating from server URL |

### APIClientBuilder

```rust
use reinhardt_test::prelude::*;
use std::time::Duration;

let client = APIClient::builder()
    .base_url("http://localhost:8080")
    .timeout(Duration::from_secs(30))
    .http1_only()            // or .http2_prior_knowledge()
    .cookie_store(true)
    .build();
```

For in-process testing (no TCP, runs full middleware stack):

```rust
let router = build_routes(scope).into_server();
let client = APIClient::from_handler(router);
let resp = client.get("/api/health/").await.unwrap();
```

### APIClient Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `get` | `async fn get(&self, path: &str) -> ClientResult<TestResponse>` | Send a GET request |
| `post` | `async fn post(&self, path: &str, data: &T, format: &str) -> ClientResult<TestResponse>` | Send a POST request with body and format |
| `put` | `async fn put(&self, path: &str, data: &T, format: &str) -> ClientResult<TestResponse>` | Send a PUT request with body and format |
| `patch` | `async fn patch(&self, path: &str, data: &T, format: &str) -> ClientResult<TestResponse>` | Send a PATCH request with body and format |
| `delete` | `async fn delete(&self, path: &str) -> ClientResult<TestResponse>` | Send a DELETE request |
| `head` | `async fn head(&self, path: &str) -> ClientResult<TestResponse>` | Send a HEAD request |
| `options` | `async fn options(&self, path: &str) -> ClientResult<TestResponse>` | Send an OPTIONS request |
| `set_header` | `async fn set_header(&self, name, value) -> ClientResult<()>` | Set a default header (async) |
| `force_authenticate` | `async fn force_authenticate(&self, user: Option<Value>)` | Force authenticate as user |
| `credentials` | `async fn credentials(&self, username, password) -> ClientResult<()>` | Set Basic auth credentials |
| `clear_auth` | `async fn clear_auth() -> ClientResult<()>` | Clear authentication and cookies |
| `cleanup` | `async fn cleanup()` | Clear all client state (auth, cookies, headers) |

**Important:** `post`, `put`, and `patch` take `data` and `format` as arguments. The `format` parameter is typically `"json"` or `"form"`.

### TestResponse Methods

| Method | Description |
|--------|-------------|
| `response.status()` | Get `StatusCode` |
| `response.status_code()` | Get status as `u16` |
| `response.headers()` | Get `&HeaderMap` |
| `response.text()` | Get body as `String` |
| `response.json::<T>()` | Deserialize body as JSON (`Result<T, serde_json::Error>`) |
| `response.json_value()` | Get body as `serde_json::Value` |

### Setting Headers

```rust
#[rstest]
#[tokio::test]
async fn test_with_custom_headers(api_client: APIClient) {
    // Arrange
    api_client.set_header("Accept-Language", "en").await.unwrap();
    api_client.set_header("X-Request-ID", "test-123").await.unwrap();

    // Act
    let response = api_client.get("/api/users/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
}
```

### POST with JSON Body

```rust
use serde_json::json;

#[rstest]
#[tokio::test]
async fn test_create_user(api_client: APIClient) {
    // Arrange
    let body = json!({
        "username": "newuser",
        "email": "new@example.com"
    });

    // Act
    let response = api_client.post("/api/users/", &body, "json").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::CREATED);
    let user: UserResponse = response.json().unwrap();
    assert_eq!(user.username, "newuser");
}
```

## Authenticated Requests

Use `reinhardt_test` auth fixtures for test users, then authenticate via `force_authenticate` or `credentials`:

```rust
use reinhardt_test::fixtures::auth::*;

#[rstest]
#[tokio::test]
async fn test_authenticated_endpoint(api_client: APIClient, test_user: TestUser) {
    // Arrange
    let user_json = json!({
        "id": test_user.id.to_string(),
        "username": test_user.username,
    });
    api_client.force_authenticate(Some(user_json)).await;

    // Act
    let response = api_client.get("/api/profile/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
    let profile: ProfileResponse = response.json().unwrap();
    assert_eq!(profile.username, "testuser");
}

#[rstest]
#[tokio::test]
async fn test_unauthorized_without_auth(api_client: APIClient) {
    // Act
    let response = api_client.get("/api/profile/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
```

### JWT Authentication with Fixture

```rust
use reinhardt_test::fixtures::auth::*;

#[rstest]
#[tokio::test]
async fn test_jwt_auth(api_client: APIClient, jwt_auth: JwtAuth) {
    // Arrange
    let token = jwt_auth.generate_token("testuser").unwrap();
    api_client
        .set_header("Authorization", &format!("Bearer {}", token))
        .await
        .unwrap();

    // Act
    let response = api_client.get("/api/profile/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
}
```

### Available Auth Fixtures

| Fixture | Type | Description |
|---------|------|-------------|
| `test_user` | `TestUser` | Standard non-privileged user (username: "testuser") |
| `admin_user` | `TestUser` | Admin with is_admin, is_staff, is_superuser = true |
| `inactive_user` | `TestUser` | User with is_active = false |
| `staff_user` | `TestUser` | Staff but non-admin user |
| `test_users` | `Vec<TestUser>` | 5 pre-configured users (normal, inactive, staff, admin) |
| `jwt_auth` | `JwtAuth` | Pre-configured JWT authentication |
| `jwt_auth_with_secret` | `JwtAuth` | JWT auth with custom secret |
| `argon2_hasher` | `Argon2Hasher` | Argon2 password hasher |
| `in_memory_token_storage` | `InMemoryTokenStorage` | In-memory token storage |

## APIRequestFactory

`APIRequestFactory` creates raw `Request` objects for testing views directly without HTTP transport. Use `force_authenticate` (not `with_user`) to attach a user.

```rust
use reinhardt_test::prelude::*;
use serde_json::json;
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_view_directly() {
    // Arrange
    let factory = APIRequestFactory::new();
    let user = json!({"id": 1, "username": "testuser"});
    let request = factory
        .get("/api/users/1/")
        .force_authenticate(user)
        .build()
        .unwrap();

    // Act
    let response = get_user(request, Path(1)).await;

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
}
```

### Factory Methods

| Method | Description |
|--------|-------------|
| `APIRequestFactory::new()` | Create a new request factory |
| `factory.with_format(format)` | Set default content format (e.g., "json", "xml") |
| `factory.with_header(name, value)` | Add default header (returns `Result`) |
| `factory.get(path)` | Build a GET request (returns `RequestBuilder`) |
| `factory.post(path)` | Build a POST request |
| `factory.put(path)` | Build a PUT request |
| `factory.patch(path)` | Build a PATCH request |
| `factory.delete(path)` | Build a DELETE request |
| `factory.head(path)` | Build a HEAD request |
| `factory.options(path)` | Build an OPTIONS request |
| `factory.request(method, path)` | Build a request with custom method |

### RequestBuilder Methods

| Method | Description |
|--------|-------------|
| `.header(name, value)` | Add a header (returns `Result<Self, ClientError>`) |
| `.query(key, value)` | Add a query parameter |
| `.query_param(key, value)` | Alias for `.query()` |
| `.json(&data)` | Set JSON body (returns `Result<Self, ClientError>`) |
| `.form(&data)` | Set form-encoded body (returns `Result`) |
| `.body(data)` | Set raw body |
| `.force_authenticate(user)` | Attach authenticated user (accepts `serde_json::Value`) |
| `.with_format(format)` | Set content format |
| `.build()` | Finalize (returns `Result<Request<Full<Bytes>>, ClientError>`) |

**Important:** `.json()`, `.header()`, and `.form()` return `Result`, requiring `.unwrap()` or `?` before chaining further.

### POST with APIRequestFactory

```rust
use serde_json::json;

#[rstest]
fn test_create_request() {
    // Arrange
    let factory = APIRequestFactory::new();
    let data = json!({"name": "test"});

    // Act
    let request = factory
        .post("/api/users/")
        .json(&data)
        .unwrap()
        .build()
        .unwrap();

    // Assert
    assert_eq!(request.method(), Method::POST);
    assert_eq!(
        request.headers().get("Content-Type").unwrap(),
        "application/json"
    );
}
```

## URL Reverse for Test Paths

Use `ServerRouter::reverse()` to resolve named routes instead of hardcoding URL paths:

```rust
use reinhardt_urls::routers::ServerRouter;

// Register named routes
let mut router = ServerRouter::new()
    .with_namespace("api")
    .function_named("/users/", Method::GET, "list", list_users)
    .function_named("/users/{id}/", Method::GET, "detail", get_user);
router.register_all_routes();

// Reverse resolve URLs by name
let list_url = router.reverse("api:list", &[]).unwrap();
assert_eq!(list_url, "/users/");

let detail_url = router.reverse("api:detail", &[("id", "123")]).unwrap();
assert_eq!(detail_url, "/users/123/");
```

In tests, prefer using reversed URLs:

```rust
#[rstest]
#[tokio::test]
async fn test_user_list(api_client: APIClient) {
    // Arrange — resolve URL from route name
    let url = app_router().reverse("api:users:list", &[]).unwrap();

    // Act
    let response = api_client.get(&url).await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
}
```

## Testing Response Body

```rust
#[rstest]
#[tokio::test]
async fn test_response_parsing(api_client: APIClient) {
    // Act
    let response = api_client.get("/api/users/1/").await.unwrap();

    // Assert — status
    assert_eq!(response.status(), StatusCode::OK);

    // Assert — JSON body (json() is sync, not async)
    let user: UserResponse = response.json().unwrap();
    assert_eq!(user.id, 1);
    assert_eq!(user.username, "testuser");
    assert!(user.is_active);

    // Assert — headers
    assert_eq!(
        response.headers().get("content-type").unwrap(),
        "application/json"
    );
}
```

## `impl_test_model!` Macro

The `impl_test_model!` macro implements the `Model` trait for test structs, enabling ORM operations in tests. It is NOT a factory pattern for generating test data.

```rust
use reinhardt_test::impl_test_model;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
struct TestUser {
    id: Uuid,
    username: String,
    email: String,
    is_active: bool,
}

// Implements Model trait: table_name, app_label, primary key type
impl_test_model!(TestUser, Uuid, "test_users", "auth", non_option_pk);
```

This generates:

- `Model` trait implementation with `table_name()`, `app_label()`, `pk()` methods
- `TestUserFields` struct implementing `FieldSelector`
- Relationship metadata (if specified)

### With Relationships

```rust
impl_test_model!(
    Post, i64, "posts", "blog",
    relationships: [
        (ManyToOne, "author", "users", "author_id", "posts"),
    ],
    many_to_many: []
);
```

## MSW (Mock Service Worker) for wasm32 (rc.29+)

`reinhardt-test/msw` provides Mock Service Worker integration for intercepting HTTP
requests in `wasm32-unknown-unknown` tests (typically `wasm-pack test`). rc.29 repairs
the integration for current `web-sys` 0.3.98 / `js-sys` and exposes a top-level `msw`
feature on the `reinhardt-web` facade so consumers can enable MSW without reaching
past the facade. (#4288)

### Enabling MSW via the Facade

```toml
[dev-dependencies]
reinhardt = { version = "0.2.0", features = ["test", "msw"] }
```

The facade flag expands to `["test", "pages", "reinhardt-test/msw", "reinhardt-pages/msw"]`.
This replaces the previous (DM-1 violating) pattern of adding a direct
`reinhardt-test = { features = ["msw"] }` dev-dependency in example crates. (#4288)

### Build Notes

- The `msw` feature is `wasm32`-only. Native test runs (`cargo nextest run`) are not
  affected by enabling it.
- Verify the wasm build with:
  `cargo check -p reinhardt-test --features msw --target wasm32-unknown-unknown`. (#4288)
- Run wasm tests via `wasm-pack test --headless --chrome --features msw`. (#4288)

### Compatibility Fixes Shipped in rc.29

The integration was repaired against `web-sys` 0.3.98 / current `js-sys`. Two
breakages were addressed inside `crates/reinhardt-test/src/msw/interceptor.rs`:

1. `Headers::new_with_str_mapping` was removed upstream; the interceptor now
   downcasts via `JsCast::dyn_ref::<js_sys::Object>()` and falls back to
   `Headers::new_with_record_from_str_to_str(&Object)`.
2. `js_sys::global()` now returns `Object` (not `JsValue`); the call site is wrapped
   through `JsValue::from(...)` to satisfy the inferred `Option<JsValue>` constraint.

These are upstream-only fixes — no consumer code change is required. (#4288)

## Test Placement Rules

| Test Type | Location | When to Use |
|-----------|----------|-------------|
| Unit tests | `#[cfg(test)] mod tests` in the functional crate | Testing individual functions, methods, or types in isolation |
| Integration tests (within-crate) | `#[cfg(test)] mod tests` in the functional crate | Testing interactions between modules within the same crate |
| Integration tests (cross-crate) | `tests/` crate at workspace root | Testing interactions between multiple reinhardt crates |
| E2E / API tests | `tests/` crate at workspace root | Testing full request-response cycles through the HTTP layer |

**Key rules:**

- Unit tests go in the same file as the code they test
- Cross-crate integration tests go in the workspace `tests/` crate
- Every test MUST use at least one reinhardt component
- Functional crates MUST NOT use `{ workspace = true }` for `reinhardt-test` in `[dev-dependencies]`
