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
reinhardt = { version = "...", features = ["auth-jwt", "argon2-hasher"] }
```

### Configuration

Create a `JwtAuth` helper from the project's composed settings accessor or from
an app-owned settings wrapper registered in DI:

```rust
use chrono::Duration;
use reinhardt::auth::jwt::{Claims, JwtAuth, JwtError};

fn jwt_auth(settings: &ProjectSettings) -> JwtAuth {
    JwtAuth::new(settings.jwt_secret_key.as_bytes())
}

fn create_jwt_token(jwt_auth: &JwtAuth, user: &User) -> Result<String, JwtError> {
    let claims = Claims::new(
        user.id.to_string(),
        user.username.clone(),
        Duration::minutes(15),
        user.is_staff,
        user.is_superuser,
    );
    jwt_auth.encode(&claims)
}
```

### Middleware Setup

Apply JWT middleware via `UnifiedRouter`:

```rust
use reinhardt::middleware::JwtAuthMiddleware;

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
use reinhardt::CurrentUser;

#[get("/admin/dashboard/", name = "admin_dashboard")]
pub async fn admin_dashboard(
    #[inject] CurrentUser(user): CurrentUser<User>,
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
pub async fn login(
    username: String,
    password: String,
    #[inject] settings: ProjectSettings,
) -> Result<AuthResponse, ServerFnError> {
    let user = authenticate(&username, &password).await?;
    let jwt_auth = jwt_auth(&settings);
    let token = create_jwt_token(&jwt_auth, &user)?;
    Ok(AuthResponse { token, user_id: user.id })
}
```

## Session Authentication Setup

> **Note**: JWT is the verified production pattern (confirmed in the reinhardt-cloud dashboard). Session-based auth types should be verified against the reinhardt-auth source code before use. The dashboard uses JWT exclusively with no session types.

### Feature Flag

```toml
[dependencies]
reinhardt = { version = "...", features = ["auth-session", "sessions", "argon2-hasher"] }
```

### Configuration

Use the `SessionSettings` fragment and convert it to the compatibility
`SessionConfig` value when wiring session middleware:

```rust
use reinhardt::auth::{sessions::config::SessionConfig, SessionSettings};

fn session_config(auth_session: &SessionSettings) -> SessionConfig {
    auth_session.to_config()
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

Permission classes control access to views. Apply them via `Guard<P>` in
`#[inject]` parameters, `#[permission_required("app.codename")]` for named
permission checks, or `ModelViewSetHandler::add_permission(...)` when using the
handler builder APIs.

| Permission | Description |
|-----------|-------------|
| `AllowAny` | No authentication required |
| `IsAuthenticated` | User must be authenticated |
| `IsAdminUser` | User must have `is_staff = true` |
| `IsAuthenticatedOrReadOnly` | Authenticated for write, anyone for read |

### Applying Permissions

```rust
use reinhardt::auth::{Guard, IsAuthenticated};
use reinhardt::CurrentUser;

#[get("/admin/dashboard/", name = "admin_dashboard")]
pub async fn admin_dashboard(
    #[inject] _guard: Guard<IsAuthenticated>,
    #[inject] CurrentUser(user): CurrentUser<User>,
) -> ViewResult<Response> {
    if !user.is_staff {
        return Err(AppError::Authentication("Admin access required".into()));
    }
    Ok(Response::json(serde_json::json!({ "status": "ok" })))
}

fn article_handler() -> ModelViewSetHandler<Article> {
    ModelViewSetHandler::<Article>::new()
        .add_permission(std::sync::Arc::new(IsAuthenticated))
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
