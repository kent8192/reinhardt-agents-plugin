---
name: authentication
description: Use when configuring authentication in reinhardt-web applications - covers auth backends (JWT, Session, Token, OAuth2/Social), user models, password hashing, and session management
versions: ["0.1.2", "0.2.x"]
---

# Reinhardt Authentication

Guide developers through authentication setup using reinhardt-auth, including backend configuration, user models, password hashing, and session management.

## When to Use

- User configures or selects an authentication backend
- User defines or customizes a user model
- User works with login/logout flows
- User configures JWT, session, token, or OAuth2/social authentication
- User asks about password hashing or session management
- User mentions: "auth", "authentication", "login", "logout", "JWT", "token", "session", "password", "OAuth", "social login", "Google login", "GitHub login", "BasicAuth", "AuthUser", "AuthInfo", "user model", "BaseUser", "createsuperuser"

## Workflow

### Choosing an Auth Backend

1. Read `references/auth-backends.md` for backend comparison
2. Select backend based on use case (JWT for APIs, Session for web apps, Social for third-party login)
3. Enable the corresponding feature flag in `Cargo.toml`
4. Configure via `#[injectable_factory]` — read DI skill for patterns

### Defining a Custom User Model

1. Read `references/user-models.md` for trait hierarchy and field requirements
2. Define struct with `#[model]` and `#[user]` attributes
3. Implement `BaseUser` trait (or use `#[user]` macro for auto-implementation)
4. Choose password hasher (Argon2 recommended for production)
5. Register user model in app configuration

### Setting Up Auth Extractors

1. Read `../authorization/references/extractors.md` for `AuthInfo` and `AuthUser<T>`
2. Use `AuthInfo` for lightweight access (no DB query)
3. Use `AuthUser<T>` when the full user model is needed
4. Both require `#[inject]` in handler parameters

### Configuring Social/OAuth2 Login

1. Read `references/social-auth.md` for provider setup
2. Configure `ProviderConfig` for each provider (Google, GitHub, Apple, Microsoft)
3. Set up `SocialAuthBackend` with PKCE and state validation
4. Map OAuth claims to user model via `UserMapper`

### Session Management

1. Read `references/session-management.md` for backend options
2. Choose session backend (Database, Cache, Cookie, JWT, File, InMemory)
3. Configure session settings (cookie, expiry, security)
4. Set up cleanup and rotation if needed

## Important Rules

- **ALWAYS** use `argon2-hasher` feature for production password hashing
- **NEVER** store secrets (JWT keys, OAuth client secrets) in code — use environment variables
- `AuthInfo` is lightweight (reads from request extensions) — use when you only need user ID
- `AuthUser<T>` loads the full user model from DB — use when you need user fields
- `CurrentUser<T>` is **DEPRECATED** — use `AuthUser<T>` instead
- Feature flags: `auth-jwt`, `auth-session`, `auth-token`, `auth-oauth`, `argon2-hasher`, `social`
- JWT access token lifetime should be short (15 min recommended); use refresh tokens for longer sessions
- Session cookies MUST use `HttpOnly`, `SameSite`, and `Secure` (in production)

## Cross-Domain References

- For DI configuration of auth backends: `../dependency-injection/references/di-patterns.md`
- For permission and authorization setup: `../authorization/SKILL.md`
- For auth in API endpoints: `../api-development/references/auth-config.md`
- For user model definition with `#[model]`: `../macros/references/attribute-macros.md`

## Dynamic References

For the latest auth API:
1. Read `reinhardt/crates/reinhardt-auth/src/lib.rs` for module structure and re-exports
2. Read `reinhardt/crates/reinhardt-auth/src/core/base_user.rs` for BaseUser trait
3. Read `reinhardt/crates/reinhardt-auth/src/jwt.rs` for JWT types
4. Read `reinhardt/crates/reinhardt-auth/src/rest_authentication.rs` for REST auth backends
5. Read `reinhardt/crates/reinhardt-auth/src/social.rs` for social auth module
6. Read `reinhardt/crates/reinhardt-auth/src/sessions/` for session backends
7. Grep for `#[user]` in `reinhardt/tests/` for real user model examples
