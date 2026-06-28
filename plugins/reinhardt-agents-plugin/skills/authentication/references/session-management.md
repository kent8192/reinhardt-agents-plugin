# Reinhardt Session Management Reference

**Feature:** `sessions`

**Module:** `reinhardt_auth::sessions` (re-exported via `reinhardt::sessions`)

---

## Session Backend Trait

```rust
#[async_trait]
pub trait SessionBackend: Send + Sync {
    async fn load(&self, session_key: &str) -> Result<Option<SessionData>, Error>;
    async fn save(&mut self, session_key: &str, data: &SessionData, expiry: Duration) -> Result<(), Error>;
    async fn delete(&mut self, session_key: &str) -> Result<(), Error>;
    async fn exists(&self, session_key: &str) -> Result<bool, Error>;
}
```

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
use reinhardt_auth::{sessions::config::SessionConfig, SessionSettings};

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

## Session Cleanup

Expired sessions should be cleaned up periodically:

```rust
use reinhardt::sessions::SessionCleanupTask;

// Run cleanup every hour
let cleanup = SessionCleanupTask::new(session_backend.clone())
    .with_interval(Duration::from_secs(3600));
cleanup.start().await;
```

---

## Session Rotation

Rotate session IDs to prevent session fixation attacks:

```rust
use reinhardt::sessions::SessionRotator;

// Rotate session on login
let rotator = SessionRotator::new(session_backend.clone());
rotator.rotate_session(&old_session_key).await?;
```

---

## CSRF Protection

```rust
use reinhardt::sessions::CsrfSessionManager;

let csrf = CsrfSessionManager::new(session_backend.clone());
let token = csrf.generate_token(&session_key).await?;
csrf.validate_token(&session_key, &submitted_token).await?;
```

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
2. Read `reinhardt/crates/reinhardt-auth/src/sessions/backend.rs` for SessionBackend trait
3. Read `reinhardt/crates/reinhardt-auth/src/sessions/config.rs` for SessionConfig
