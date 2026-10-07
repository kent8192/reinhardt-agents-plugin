# Reinhardt Session Management Reference

**Feature:** `sessions`

**Module:** `reinhardt_auth::sessions` (re-exported via `reinhardt::auth::sessions`)

---

## Session Backend Trait (0.4.0-alpha.20)

```rust
#[async_trait]
pub trait SessionBackend: Send + Sync + Clone {
    async fn load<T>(&self, session_key: &str) -> Result<Option<T>, SessionError>
    where
        T: for<'de> Deserialize<'de> + Serialize + Send + Sync;

    async fn save<T>(
        &self,
        session_key: &str,
        data: &T,
        ttl: Option<u64>,
    ) -> Result<(), SessionError>
    where
        T: Serialize + Send + Sync;

    async fn delete(&self, session_key: &str) -> Result<(), SessionError>;
    async fn exists(&self, session_key: &str) -> Result<bool, SessionError>;
}
```

TTL is optional and measured in seconds. Implement internal mutation with the
backend's own synchronized storage; the public receivers are shared.

---

## Available Backends

| Backend | Type | Feature | Storage | Performance | Use Case |
|---------|------|---------|---------|-------------|----------|
| Database | `DatabaseSessionBackend` | `database` | Database table | Moderate | Default, no extra infra |
| Cache/Redis | `CacheSessionBackend<C>` | (base) | Cache | Fast | High-traffic apps |
| Cookie | `CookieSessionBackend` | `cookie` | Encrypted cookie | Fastest | Small data, no server state |
| JWT | `JwtSessionBackend` | `jwt` | JWT token | Fast | Stateless sessions |
| File | `FileSessionBackend` | `file` | Filesystem | Moderate | Simple deployments |
| InMemory | `InMemorySessionBackend` | (base) | Process memory | Fastest | Dev/testing only |

---

## Session Configuration

Use the `SessionSettings` fragment under `[auth_session]` and convert it to the
compatibility `SessionConfig` value when wiring session middleware.

### Setup from ProjectSettings

```rust
use reinhardt::settings;
use reinhardt::auth::{sessions::config::SessionConfig, SessionSettings};

#[settings(core: CoreSettings | auth_session: SessionSettings)]
pub struct ProjectSettings;

fn session_config(settings: &ProjectSettings) -> SessionConfig {
    settings.auth_session.to_config()
}
```

---

## Serialization Formats

| Format | Feature | Size | Speed | Use Case |
|--------|---------|------|-------|----------|
| JSON | (default) | Larger | Moderate | Debugging, readability |
| MessagePack | `messagepack` | Compact | Fast | Production |
| CBOR | `cbor` | Compact | Fast | Production |
| Bincode | `bincode` | Smallest | Fastest | High-performance |

---

## Compression

| Algorithm | Feature | Ratio | Speed |
|-----------|---------|-------|-------|
| Zstd | `compression-zstd` | Best | Fast |
| Gzip | `compression-gzip` | Good | Moderate |
| Brotli | `compression-brotli` | Very good | Slower |

---

## Session Cleanup (0.4.0-alpha.20)

```rust
use reinhardt::auth::sessions::cleanup::SessionCleanupTask;
use std::time::Duration;

let cleanup = SessionCleanupTask::new(
    session_backend.clone(),
    Duration::from_secs(7200),
);
let removed = cleanup.run_cleanup().await?;
```

The second argument is maximum age, not a scheduler interval. Invoke
`run_cleanup` from the application's owned periodic task; retain its task
guard so cancellation and shutdown follow the application's lifecycle.

## Session Rotation

```rust
use reinhardt::auth::sessions::rotation::{RotationPolicy, SessionRotator};

let rotator = SessionRotator::new(RotationPolicy::default());
rotator.rotate(&mut session).await?;
```

Rotate the live session, rather than passing a backend or an old key string.

## CSRF Protection

```rust
use reinhardt::auth::sessions::csrf::CsrfSessionManager;

let csrf = CsrfSessionManager::new();
let token = csrf.generate_token(&mut session)?;
if !csrf.validate_token(&mut session, &submitted_token)? {
    return Err(reinhardt::Error::PermissionDenied("Invalid CSRF token".into()));
}
```

These token operations are synchronous and take `&mut Session<B>`.
A successful `Result` does not imply a matching token: reject `Ok(false)`.
Use the application error adapter when constructing an HTTP response.

---

## Session Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `SESSION_COOKIE_NAME` | `"sessionid"` | Default session cookie name |
| `SESSION_KEY_USER_ID` | `"_auth_user_id"` | Session key for user ID |

### Version Differences (0.2.x)

In 0.2.x, permission lookups during session resolution use the user ID instead of the username. This aligns with the broader 0.2.x change where all permission resolution is user-ID-based rather than username-based.

---

## Session Replication

**Feature:** `replication`

For distributed deployments, session data can be replicated across nodes.

---

## Multi-Tenant Isolation

Sessions support tenant isolation for multi-tenant applications, ensuring session data is scoped to the correct tenant.

---

## Session Analytics

| Tool | Purpose |
|------|---------|
| Session Logger | Log session lifecycle events |
| Prometheus metrics | Track active sessions, creation/expiry rates |

## Dynamic References

For the latest session API:

1. Read `reinhardt/crates/reinhardt-auth/src/sessions/` for all session implementations
2. Read `reinhardt/crates/reinhardt-auth/src/sessions/backends/cache.rs` for SessionBackend trait
3. Read `reinhardt/crates/reinhardt-auth/src/sessions/config.rs` for SessionConfig
