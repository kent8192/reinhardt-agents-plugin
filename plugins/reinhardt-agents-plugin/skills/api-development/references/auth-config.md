# Reinhardt Authentication Configuration Reference

## Auth Backends

Reinhardt supports multiple authentication backends, each enabled via feature flags.

> **0.2.x note**: In 0.2.x, all auth backends implement a unified `AuthBackend` trait. The individual backend types listed below remain, but their return types and configuration are normalized through this common trait. Code that pattern-matched on backend-specific result types should migrate to the `AuthBackend` trait interface.

| Backend | Type | Feature Flag | Transport | Stateful | Use Case |
|---------|------|-------------|-----------|----------|----------|
| JWT | `JwtAuth` | `auth-jwt` | `Authorization: Bearer <token>` | No | APIs, mobile clients, SPAs |
| Session | `SessionAuthentication<B>` | `auth-session` | Cookie (`sessionid`) | Yes | Traditional web apps, admin panel |
| OAuth 2.0 | `OAuth2Authentication` | `auth-oauth` | `Authorization: Bearer <token>` | Depends | Third-party login (Google, GitHub, etc.) |
| Token | `TokenAuthentication` | `auth-token` | `Authorization: Token <key>` | Yes (DB) | Persistent API keys, service accounts |
| Basic | `BasicAuthentication` | (always available) | `Authorization: Basic <b64>` | No | Development, simple integrations |
| Remote User | `RemoteUserAuthentication` | (always available) | Proxy header | No | Reverse proxy auth (nginx, etc.) |

## JWT Authentication Setup (Verified Pattern)

JWT is the verified production pattern, confirmed in use by the reinhardt-cloud dashboard.

### Feature Flag

```toml
[dependencies]
reinhardt = { version = "0.3.0", features = ["auth-jwt", "argon2-hasher"] }
```

### Configuration

Use `#[injectable]` to create `JwtConfig` from `ProjectSettings`:

```rust
use reinhardt::auth::jwt::{JwtConfig, Algorithm};
use reinhardt::di::prelude::*;

#[injectable(scope = "singleton")]
async fn jwt_config(#[inject] settings: Depends<ProjectSettings>) -> JwtConfig {
    JwtConfig {
        secret_key: settings.jwt_secret_key.clone(),
        algorithm: Algorithm::HS256,
        access_token_lifetime: Duration::from_secs(60 * 15),   // 15 minutes
        refresh_token_lifetime: Duration::from_secs(60 * 60 * 24 * 7), // 7 days
        issuer: Some("my-app".to_string()),
        audience: None,
    }
}
```

### Middleware Setup

Apply JWT middleware via `UnifiedRouter`:

```rust
use reinhardt::auth::jwt::JwtAuthMiddleware;

UnifiedRouter::new()
    .mount("/api/", app_router)
    .with_middleware(JwtAuthMiddleware::from_secret(jwt_secret.as_bytes()))
```

### Auth Extractors

Reinhardt provides two auth extractors, both used with `#[inject]`:

#### AuthInfo (Lightweight)

`AuthInfo` provides lightweight access to the authenticated state without loading the full user model. This is the pattern used in the reinhardt-cloud dashboard.

```rust
use reinhardt::views::prelude::*;

#[get("/profile/", name = "user_profile")]
pub async fn get_profile(
    #[inject] AuthInfo(state): AuthInfo,
) -> ViewResult<Response> {
    let user_id = state.user_id();
    // Use user_id for queries without loading the full user model
    let profile = Profile::objects().filter(Profile::user_id.eq(user_id)).get().await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&profile)?))
}
```

#### CurrentUser<T> (Full User Model)

`CurrentUser<T>` resolves the full user model from the auth token or session:

```rust
#[get("/admin/dashboard/", name = "admin_dashboard")]
pub async fn admin_dashboard(
    #[inject] reinhardt::CurrentUser(user): reinhardt::CurrentUser<User>,
) -> ViewResult<Response> {
    if !user.is_staff {
        return Err(AppError::Authentication("Admin access required".into()));
    }
    // user is a full User model instance
    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&DashboardData::for_user(&user).await?)?))
}
```

### Server Functions with Auth

```rust
use reinhardt::pages::prelude::*;

#[server_fn]
pub async fn login(username: String, password: String) -> Result<AuthResponse, ServerFnError> {
    let user = authenticate(&username, &password).await?;
    let token = create_jwt_token(&user)?;
    Ok(AuthResponse { token, user_id: user.id })
}
```

## Session Authentication Setup

> **Note**: JWT is the verified production pattern (confirmed in the reinhardt-cloud dashboard). Session-based auth types should be verified against the reinhardt-auth source code before use. The dashboard uses JWT exclusively with no session types.

### Feature Flag

```toml
[dependencies]
reinhardt = { version = "0.3.0", features = ["auth-session", "sessions", "argon2-hasher"] }
```

### Configuration

Use `#[injectable]` to create `SessionConfig` from `ProjectSettings`:

```rust
use reinhardt::sessions::{SessionConfig, SessionEngine};
use reinhardt::di::prelude::*;

#[injectable(scope = "singleton")]
async fn session_config(#[inject] settings: Depends<ProjectSettings>) -> SessionConfig {
    SessionConfig {
        engine: SessionEngine::Database, // or Redis, Cookie
        cookie_name: "sessionid".to_string(),
        cookie_age: Duration::from_secs(60 * 60 * 24 * 14), // 2 weeks
        cookie_secure: settings.is_production(),
        cookie_httponly: true,
        cookie_samesite: SameSite::Lax,
    }
}
```

### Session Backends

`SessionAuthentication` is generic over `SessionBackend`. Available implementations:

| Backend | Type | Storage | Performance | Use Case |
|---------|------|---------|-------------|----------|
| Database | `DatabaseSessionBackend` | Database table | Moderate | Default, no extra infrastructure |
| Cache/Redis | `CacheSessionBackend<C>` | Cache (Redis, etc.) | Fast | High-traffic applications |
| Cookie | `CookieSessionBackend` | Signed cookie | Fastest | Small session data, no server state |
| JWT | `JwtSessionBackend` | JWT token | Fast | Stateless sessions |
| File | `FileSessionBackend` | Filesystem | Moderate | Simple deployments |
| InMemory | `InMemorySessionBackend` | Process memory | Fastest | Development/testing only |

### Usage in Views

Use HTTP method decorators or `#[server_fn]` — never raw `async fn` with `Request`:

```rust
use reinhardt::auth::prelude::*;
use reinhardt::views::prelude::*;

#[post("/auth/login/", name = "session_login", pre_validate = true)]
pub async fn session_login(
    Json(data): Json<LoginRequest>,
) -> ViewResult<Response> {
    let user = authenticate(&data.username, &data.password).await
        .map_err(|_| AppError::Authentication("Invalid credentials".into()))?;

    // Creates a session and sets the session cookie
    login(&user).await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&json!({ "status": "ok" }))?))
}

#[post("/auth/logout/", name = "session_logout")]
pub async fn session_logout() -> ViewResult<Response> {
    logout().await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&json!({ "status": "ok" }))?))
}
```

Or using server functions (for Pages/WASM):

```rust
#[server_fn]
pub async fn session_login(username: String, password: String) -> Result<AuthResponse, ServerFnError> {
    let user = authenticate(&username, &password).await?;
    login(&user).await?;
    Ok(AuthResponse { status: "ok".to_string() })
}
```

## Password Hashing

Reinhardt uses pluggable password hashers. The `argon2-hasher` feature is recommended for production.

| Hasher | Feature Flag | Security Level | Speed |
|--------|-------------|----------------|-------|
| Argon2id | `argon2-hasher` | Highest (recommended) | Slow (by design) |
| PBKDF2-SHA256 | (default) | High | Moderate |
| Bcrypt | (built-in) | High | Moderate |

```rust
use reinhardt::auth::hashers::make_password;

// Hash a password
let hashed = make_password("user_password")?;

// Verify a password
let is_valid = check_password("user_password", &hashed)?;
```

## Permission Classes

Permission classes control access to views. Apply them via `get_permissions()` on ViewSets or as middleware.

| Permission | Description |
|-----------|-------------|
| `AllowAny` | No authentication required |
| `IsAuthenticated` | User must be authenticated |
| `IsAdminUser` | User must have `is_staff = true` |
| `IsAuthenticatedOrReadOnly` | Authenticated for write, anyone for read |
| `HasPermission(perm)` | User must have the named permission |
| `HasGroupPermission(group)` | User must belong to the named group |

### Applying Permissions

```rust
// On a ViewSet
impl ViewSet for UserViewSet {
    fn get_permissions(&self) -> Vec<Box<dyn Permission>> {
        vec![Box::new(IsAuthenticated)]
    }
}

// On a function-based view (via middleware)
#[permission(IsAdminUser)]
pub async fn admin_dashboard(request: Request, auth: CurrentUser<User>) -> Response {
    // Only staff users reach here
    Response::json(serde_json::json!({ "status": "ok" }))
}

// Per-action permissions on a ViewSet
impl ViewSet for ArticleViewSet {
    fn get_permissions_for_action(&self, action: &Action) -> Vec<Box<dyn Permission>> {
        match action {
            Action::List | Action::Retrieve => vec![Box::new(AllowAny)],
            _ => vec![Box::new(IsAuthenticated)],
        }
    }
}
```

## Security Best Practices

1. **Always use HTTPS in production** — Set `cookie_secure: true` for session cookies
2. **Use `argon2-hasher`** — It is the most resistant to brute-force attacks
3. **Set short JWT access token lifetimes** — 15 minutes is recommended; use refresh tokens for longer sessions
4. **Never store secrets in code** — Use environment variables for `JWT_SECRET_KEY`, database credentials, and OAuth client secrets
5. **Enable CORS carefully** — Only whitelist known origins, never use `*` in production
6. **Use `HttpOnly` and `SameSite` cookies** — Prevent XSS and CSRF attacks on session cookies
7. **Rate-limit auth endpoints** — Apply `RateLimitMiddleware` to login, registration, and token endpoints
8. **Rotate secrets periodically** — Plan for JWT key rotation and session secret rotation
