# Reinhardt Authentication Backends Reference

## Backend Overview

| Backend | Type | Feature Flag | Transport | Stateful | Use Case |
|---------|------|-------------|-----------|----------|----------|
| JWT | `JwtAuth` | `auth-jwt` | `Authorization: Bearer <token>` | No | APIs, mobile, SPAs |
| Session | `SessionAuthentication<B>` | `auth-session` | Cookie (`sessionid`) | Yes | Web apps, admin panel |
| Token | `TokenAuthentication` | `auth-token` | `Authorization: Token <key>` | Yes (DB) | Persistent API keys, service accounts |
| Basic | `BasicAuthentication` | (always available) | `Authorization: Basic <b64>` | No | Development, simple integrations |
| Remote User | `RemoteUserAuthentication` | (always available) | Proxy header | No | Reverse proxy auth (nginx) |
| Social/OAuth2 | `SocialAuthBackend` | `social` | OAuth2 redirect flow | Depends | Google, GitHub, Apple, Microsoft |

**Module:** `reinhardt_auth` (re-exported via `reinhardt::auth`)

### Version Differences (0.2.x)

- **Unified `AuthBackend` trait**: In 0.2.x, `AuthenticationBackend` and `AuthBackend` are unified into a single `AuthBackend` trait. The separate `AuthenticationBackend` trait is removed.
- **`authenticate()` return type changed**: `authenticate()` now returns `Result<Option<Box<dyn AuthIdentity>>, AuthenticationError>` instead of `Result<Option<Box<dyn User>>, AuthenticationError>`.
- **All built-in backends migrated**: All built-in backends (JWT, Session, Token, Basic, RemoteUser, Social) implement the unified `AuthBackend` trait in 0.2.x.

**Before/after example:**

```rust
// 0.1.x
#[async_trait]
impl AuthenticationBackend for JwtBackend {
    async fn authenticate(&self, request: &Request) -> Result<Option<Box<dyn User>>, AuthError> {
        // ...
    }
}

// 0.2.x — unified AuthBackend
#[async_trait]
impl AuthBackend for JwtBackend {
    async fn authenticate(&self, request: &Request) -> Result<Option<Box<dyn AuthIdentity>>, AuthError> {
        // ...
    }
}
```

---

## AuthenticationBackend Trait

All backends implement this core trait:

```rust
#[async_trait]
pub trait AuthenticationBackend: Send + Sync {
    async fn authenticate(&self, request: &Request)
        -> Result<Option<Box<dyn User>>, AuthenticationError>;
    async fn get_user(&self, user_id: &str)
        -> Result<Option<Box<dyn User>>, AuthenticationError>;
}
```

There is also a `RestAuthentication` trait used by REST-specific backends:

```rust
#[async_trait]
pub trait RestAuthentication: Send + Sync {
    async fn authenticate(&self, request: &Request)
        -> Result<Option<Box<dyn User>>, AuthenticationError>;
}
```

---

## JWT Authentication

**Feature:** `auth-jwt`

The verified production pattern, confirmed in use by the reinhardt-cloud dashboard.

### Types

```rust
pub struct JwtAuth { /* secret key */ }

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,          // User ID
    pub exp: i64,             // Expiration timestamp
    pub iat: i64,             // Issued at timestamp
    pub username: String,
    pub is_staff: bool,
    pub is_superuser: bool,
}

#[non_exhaustive]
pub enum JwtError {
    TokenExpired,
    InvalidSignature(String),
    InvalidToken(String),
    EncodingError(String),
}
```

### JwtAuth Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new(secret: &[u8]) -> Self` | Create with secret key |
| `encode` | `fn encode(&self, claims: &Claims) -> Result<String, JwtError>` | Encode claims to JWT string |
| `decode` | `fn decode(&self, token: &str) -> Result<Claims, JwtError>` | Decode JWT string to claims |
| `generate_token` | `fn generate_token(&self, user_id: String, username: String, is_staff: bool, is_superuser: bool) -> Result<String, JwtError>` | Generate token for user |
| `verify_token` | `fn verify_token(&self, token: &str) -> Result<Claims, JwtError>` | Verify and decode token |
| `verify_token_allow_expired` | `fn verify_token_allow_expired(&self, token: &str) -> Result<Claims, JwtError>` | Verify without expiration check (for refresh) |

### Claims Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new(user_id: String, username: String, expires_in: Duration, is_staff: bool, is_superuser: bool) -> Self` | Create new claims |
| `is_expired` | `fn is_expired(&self) -> bool` | Check if token is expired |

### Setup

```rust
// Cargo.toml
// reinhardt = { version = "...", features = ["auth-jwt", "argon2-hasher"] }

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

### Middleware

```rust
use reinhardt::middleware::JwtAuthMiddleware;

UnifiedRouter::new()
    .mount("/api/", app_router)
    .with_middleware(JwtAuthMiddleware::from_secret(jwt_secret.as_bytes()))
```

### Token Management

**Token Blacklist** (revocation):

```rust
pub trait TokenBlacklist: Send + Sync {
    async fn is_blacklisted(&self, token: &str) -> bool;
    async fn blacklist(&mut self, token: &str, reason: BlacklistReason);
}

pub struct InMemoryTokenBlacklist; // Built-in implementation
```

**Token Rotation** (refresh):

```rust
pub struct TokenRotationManager { /* ... */ }
pub struct TokenRotationConfig {
    pub rotation_interval: Duration,
    pub max_rotations: usize,
}
```

**Token Storage** (persistence):

```rust
pub trait TokenStorage: Send + Sync {
    async fn store(&mut self, token: StoredToken) -> Result<(), Error>;
    async fn get(&self, token_id: &str) -> Result<Option<StoredToken>, Error>;
    async fn revoke(&mut self, token_id: &str) -> Result<(), Error>;
}

pub struct InMemoryTokenStorage;    // Built-in
pub struct DatabaseTokenStorage;    // Feature: database
```

---

## Session Authentication

**Feature:** `auth-session`, `sessions`

### Types

```rust
pub struct SessionAuthentication<B: SessionBackend> { /* ... */ }

pub struct SessionAuthConfig {
    pub cookie_name: String,
    pub enforce_csrf: bool,
}

pub struct SessionSettings {
    pub cookie_name: String,
    pub cookie_age_secs: Option<u64>,
    pub cookie_secure: bool,
    pub cookie_httponly: bool,
    pub cookie_samesite: String,
}
```

### Construction

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new(session_backend: B) -> Self` | Create with backend |
| `with_config` | `fn with_config(config: SessionAuthConfig, session_backend: B) -> Self` | Create with config |

### Session Backends

| Backend | Type | Storage | Performance | Use Case |
|---------|------|---------|-------------|----------|
| Database | `DatabaseSessionBackend` | Database table | Moderate | Default, no extra infrastructure |
| Cache/Redis | `CacheSessionBackend<C>` | Cache (Redis, etc.) | Fast | High-traffic applications |
| Cookie | `CookieSessionBackend` | Signed cookie | Fastest | Small session data, no server state |
| JWT | `JwtSessionBackend` | JWT token | Fast | Stateless sessions |
| File | `FileSessionBackend` | Filesystem | Moderate | Simple deployments |
| InMemory | `InMemorySessionBackend` | Process memory | Fastest | Development/testing only |

### Setup

```rust
// Cargo.toml
// reinhardt = { version = "...", features = ["auth-session", "sessions", "argon2-hasher"] }

use reinhardt::auth::{sessions::config::SessionConfig, SessionSettings};

fn session_config(auth_session: &SessionSettings) -> SessionConfig {
    auth_session.to_config()
}
```

### Login/Logout Handlers

```rust
use reinhardt::views::prelude::*;

#[post("/auth/login/", name = "session_login")]
pub async fn session_login(
    Json(data): Json<LoginRequest>,
) -> ViewResult<Response> {
    let user = authenticate(&data.username, &data.password).await
        .map_err(|_| AppError::Authentication("Invalid credentials".into()))?;
    login(&user).await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&json!({ "status": "ok" }))?))
}

#[post("/auth/logout/", name = "session_logout")]
pub async fn session_logout() -> ViewResult<Response> {
    logout().await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&json!({ "status": "ok" }))?))
}
```

---

## Token Authentication

**Feature:** `auth-token`

Persistent API keys stored in the database.

### Types

```rust
pub struct TokenAuthentication { /* ... */ }

pub struct TokenAuthConfig {
    pub header_name: String,  // Default: "Authorization"
    pub prefix: String,       // Default: "Token"
}
```

### Construction

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new() -> Self` | Create with defaults |
| `with_config` | `fn with_config(config: TokenAuthConfig) -> Self` | Create with config |
| `add_token` | `fn add_token(&mut self, token: impl Into<String>, user_id: impl Into<String>)` | Register a token |

---

## Basic Authentication

Always available (no feature flag).

```rust
pub struct BasicAuthentication { /* ... */ }

pub struct BasicAuthConfig {
    pub realm: String,
}
```

HTTP header: `Authorization: Basic base64(username:password)`

---

## Remote User Authentication

Always available. Delegates auth to a reverse proxy (nginx, Apache).

```rust
pub struct RemoteUserAuthentication { /* ... */ }
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new() -> Self` | Create with default header (`X-Remote-User`) |
| `with_header` | `fn with_header(mut self, header: impl Into<String>) -> Self` | Custom header name |

---

## Composite Authentication

Combines multiple backends (tries in order until one succeeds):

```rust
pub struct CompositeAuthentication { /* ... */ }
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new() -> Self` | Create empty composite |
| `with_backend` | `fn with_backend<B: AuthenticationBackend + 'static>(mut self, backend: B) -> Self` | Add a backend |
| `with_backends` | `fn with_backends(mut self, backends: Vec<Arc<dyn AuthenticationBackend>>) -> Self` | Add multiple |

### Example

```rust
let auth = CompositeAuthentication::new()
    .with_backend(JwtAuth::new(secret.as_bytes()))
    .with_backend(TokenAuthentication::with_config(token_config))
    .with_backend(BasicAuthentication::new());
```

---

## AuthenticationError

```rust
pub enum AuthenticationError {
    InvalidCredentials,
    UserNotFound,
    SessionExpired,
    InvalidToken,
    TokenExpired,
    NotAuthenticated,
    DatabaseError(String),
    Unknown(String),
}
```

---

## Security Best Practices

1. **Always use HTTPS in production** — Set `cookie_secure: true` for session cookies
2. **Use `argon2-hasher`** — Most resistant to brute-force attacks
3. **Short JWT access token lifetimes** — 15 minutes recommended; use refresh tokens
4. **Never store secrets in code** — Use environment variables
5. **Enable CORS carefully** — Only whitelist known origins, never `*` in production
6. **Use `HttpOnly` and `SameSite` cookies** — Prevent XSS and CSRF
7. **Rate-limit auth endpoints** — Apply `RateLimitMiddleware` to login/register/token endpoints
8. **Rotate secrets periodically** — Plan for JWT key and session secret rotation

## Dynamic References

For the latest auth backend API:

1. Read `reinhardt/crates/reinhardt-auth/src/jwt.rs` for JwtAuth
2. Read `reinhardt/crates/reinhardt-auth/src/rest_authentication.rs` for Session/Token/Basic/Composite
3. Read `reinhardt/crates/reinhardt-auth/src/remote_user.rs` for RemoteUser
4. Read `reinhardt/crates/reinhardt-auth/src/token_blacklist.rs` for token revocation
5. Read `reinhardt/crates/reinhardt-auth/src/token_rotation.rs` for token refresh
6. Read `reinhardt/crates/reinhardt-auth/src/token_storage.rs` for token persistence
