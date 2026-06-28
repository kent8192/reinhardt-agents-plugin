# Reinhardt Social Authentication (OAuth2/OIDC) Reference

**Feature:** `social`

**Module:** `reinhardt_auth::social` (re-exported via `reinhardt::auth::social`)

---

## Supported Providers

| Provider | Type | Protocol | Feature |
|----------|------|----------|---------|
| `GoogleProvider` | OIDC | OpenID Connect | `social` |
| `GitHubProvider` | OAuth2 | OAuth 2.0 | `social` |
| `AppleProvider` | OIDC | OpenID Connect (JWT client_secret) | `social` |
| `MicrosoftProvider` | OIDC | OpenID Connect / Azure AD | `social` |
| `GenericOidcProvider` | OIDC | OpenID Connect (any IdP) | `social` |

---

## Architecture

```text
User → Authorization URL → Provider → Callback URL → Token Exchange → User Mapping
         (with PKCE)                     (state validation)   (ID token verification)
```

### Module Structure

| Module | Purpose |
|--------|---------|
| `backend` | `SocialAuthBackend` — main entry point |
| `core` | `OAuth2Config`, `OIDCConfig`, `ProviderConfig`, `OAuthToken`, `IdToken`, `StandardClaims` |
| `flow` | `AuthorizationFlow`, `PkceFlow`, `RefreshFlow`, `TokenExchangeFlow`, `StateStore` |
| `oidc` | `DiscoveryClient`, `IdTokenValidator`, `JwkSet`, `JwksCache`, `OIDCDiscovery`, `UserInfoClient` |
| `providers` | Provider implementations |
| `storage` | `SocialAccountStorage`, `InMemorySocialAccountStorage` |
| `user_mapping` | `UserMapper`, `DefaultUserMapper`, `MappedUser` |

---

## Setup

### Feature Flag

```toml
[dependencies]
reinhardt = { version = "...", features = ["social", "argon2-hasher"] }
```

### Provider Configuration

```rust
use reinhardt::auth::social::*;

// Google OIDC
let google = ProviderConfig::google(
    "your-client-id.apps.googleusercontent.com",
    "your-client-secret",
    "https://yourapp.com/auth/google/callback",
);

// GitHub OAuth2
let github = ProviderConfig::github(
    "your-github-client-id",
    "your-github-client-secret",
    "https://yourapp.com/auth/github/callback",
);

// Apple OIDC (requires team_id, key_id, private_key for JWT client_secret)
let apple = ProviderConfig::apple(
    "your-apple-client-id",
    "your-team-id",
    "your-key-id",
    include_str!("../keys/AuthKey.p8"),
    "https://yourapp.com/auth/apple/callback",
);

// Microsoft OIDC / Azure AD
let microsoft = ProviderConfig::microsoft(
    "your-azure-client-id",
    "your-azure-client-secret",
    "https://yourapp.com/auth/microsoft/callback",
);
```

### Backend Registration

```rust
use reinhardt::auth::social::SocialAuthBackend;
use reinhardt::di::prelude::*;

#[injectable(scope = "singleton")]
async fn social_auth(#[inject] settings: ProjectSettings) -> SocialAuthBackend {
    SocialAuthBackend::new()
        .with_provider(ProviderConfig::google(
            &settings.google_client_id,
            &settings.google_client_secret,
            &settings.google_callback_url,
        ))
        .with_provider(ProviderConfig::github(
            &settings.github_client_id,
            &settings.github_client_secret,
            &settings.github_callback_url,
        ))
}
```

---

## OAuth2 Flow

### Step 1: Authorization URL

```rust
use reinhardt::auth::social::flow::{AuthorizationFlow, PkceFlow};

// Generate authorization URL with PKCE
let flow = AuthorizationFlow::new(&provider_config);
let (auth_url, state, pkce_verifier) = flow.authorization_url_with_pkce(
    &["openid", "email", "profile"], // scopes
)?;

// Store state and PKCE verifier in session/cache for callback validation
state_store.store(state.clone(), StateData {
    pkce_verifier,
    provider: "google".to_string(),
}).await?;

// Redirect user to auth_url
```

### Step 2: Callback Handling

```rust
// In callback handler
let callback = CallbackResult {
    code: query.code,
    state: query.state,
};

// Validate state parameter (CSRF protection)
let state_data = state_store.get(&callback.state).await?
    .ok_or(SocialAuthError::InvalidState)?;

// Exchange code for tokens
let token_exchange = TokenExchangeFlow::new(&provider_config);
let token_response = token_exchange.exchange_code(
    &callback.code,
    Some(&state_data.pkce_verifier),
).await?;
```

### Step 3: User Mapping

```rust
// Verify ID token (for OIDC providers)
let validator = IdTokenValidator::new(&provider_config);
let claims = validator.validate(&token_response.id_token).await?;

// Map claims to user
let mapper = DefaultUserMapper::new();
let mapped_user = mapper.map_user(&claims).await?;

// Find or create user in database
let user = social_account_storage
    .find_or_create_user(&mapped_user, "google")
    .await?;
```

---

## Core Types

### StandardClaims

OpenID Connect standard claims extracted from ID tokens:

```rust
pub struct StandardClaims {
    pub sub: String,           // Subject (unique provider ID)
    pub email: Option<String>,
    pub email_verified: Option<bool>,
    pub name: Option<String>,
    pub given_name: Option<String>,
    pub family_name: Option<String>,
    pub picture: Option<String>,
    pub locale: Option<String>,
}
```

### OAuthToken / TokenResponse

```rust
pub struct TokenResponse {
    pub access_token: String,
    pub token_type: String,
    pub expires_in: Option<u64>,
    pub refresh_token: Option<String>,
    pub scope: Option<String>,
    pub id_token: Option<String>,  // OIDC only
}
```

### SocialAccount

Maps OAuth identity to local user:

```rust
pub struct SocialAccount {
    pub provider: String,       // "google", "github", etc.
    pub provider_id: String,    // Provider-specific user ID
    pub user_id: String,        // Local user ID
    pub extra_data: serde_json::Value,
}
```

### SocialAccountStorage Trait

```rust
#[async_trait]
pub trait SocialAccountStorage: Send + Sync {
    async fn find_by_provider(&self, provider: &str, provider_id: &str)
        -> Result<Option<SocialAccount>, Error>;
    async fn create(&mut self, account: SocialAccount) -> Result<(), Error>;
    async fn delete(&mut self, provider: &str, provider_id: &str) -> Result<(), Error>;
}
```

### UserMapper Trait

```rust
#[async_trait]
pub trait UserMapper: Send + Sync {
    async fn map_user(&self, claims: &StandardClaims) -> Result<MappedUser, Error>;
}
```

---

## Security Features

| Feature | Description |
|---------|-------------|
| **PKCE** (RFC 7636) | Proof Key for Code Exchange — prevents authorization code interception |
| **State Parameter** | CSRF protection — validates callback matches initiated flow |
| **ID Token Verification** | JWKS signature verification for OIDC providers |
| **Nonce Validation** | Prevents replay attacks in OIDC flows |
| **JWKS Caching** | Caches provider public keys to avoid repeated fetches |

---

## Error Types

```rust
pub enum SocialAuthError {
    InvalidState,
    TokenExchangeFailed(String),
    IdTokenValidationFailed(String),
    ProviderNotConfigured(String),
    UserMappingFailed(String),
    StorageError(String),
    NetworkError(String),
}
```

## Dynamic References

For the latest social auth API:

1. Read `reinhardt/crates/reinhardt-auth/src/social.rs` for module structure
2. Read `reinhardt/crates/reinhardt-auth/src/social/backend.rs` for SocialAuthBackend
3. Read `reinhardt/crates/reinhardt-auth/src/social/providers/` for provider implementations
4. Read `reinhardt/crates/reinhardt-auth/src/social/flow.rs` for OAuth2 flows
5. Read `reinhardt/crates/reinhardt-auth/src/social/oidc.rs` for OIDC validation

---

## GenericOidcProvider (rc.23+)

`GenericOidcProvider` lets you plug in any OIDC-compliant IdP (Keycloak, Authentik,
self-hosted GitLab, AWS Cognito, Auth0, …) using only a discovery URL plus client
credentials — no need to implement `OAuthProvider` from scratch. (#3999)

**Module:** `reinhardt_auth::social::providers::generic_oidc`
**Feature:** `social`

### Configuration

```rust
use reinhardt::auth::social::providers::generic_oidc::{
    GenericOidcConfig, GenericOidcProvider,
};
use std::time::Duration;

// Keycloak example
let keycloak = GenericOidcProvider::new(GenericOidcConfig {
    client_id: "myapp".into(),
    client_secret: "…".into(),
    redirect_uri: "https://app.example.com/auth/keycloak/callback".into(),
    discovery_url:
        "https://kc.example.com/realms/myrealm/.well-known/openid-configuration".into(),
    scopes: vec!["openid".into(), "email".into(), "profile".into()],
    extra_token_params: vec![],            // e.g. ("audience", "api.example.com") for Auth0
    discovery_ttl: Some(Duration::from_secs(3600)), // default 1h
    jwks_ttl:      Some(Duration::from_secs(3600)), // default 1h
})?;

// Authentik example
let authentik = GenericOidcProvider::new(GenericOidcConfig {
    client_id: "myapp".into(),
    client_secret: "…".into(),
    redirect_uri: "https://app.example.com/auth/authentik/callback".into(),
    discovery_url:
        "https://auth.example.com/application/o/myapp/.well-known/openid-configuration".into(),
    scopes: vec!["openid".into(), "email".into(), "profile".into()],
    ..Default::default()
})?;

// Self-hosted GitLab example
let gitlab = GenericOidcProvider::new(GenericOidcConfig {
    client_id: "myapp".into(),
    client_secret: "…".into(),
    redirect_uri: "https://app.example.com/auth/gitlab/callback".into(),
    discovery_url: "https://gitlab.example.com/.well-known/openid-configuration".into(),
    scopes: vec!["openid".into(), "email".into(), "profile".into()],
    ..Default::default()
})?;
```

### Custom claim mapping (`with_userinfo_mapper`)

For IdPs that return non-standard claim names (GitLab's `groups`, Keycloak's
`realm_access`, …), wrap the provider with a custom mapper:

```rust
let provider = GenericOidcProvider::new(config)?
    .with_userinfo_mapper(|raw: serde_json::Value| {
        // Build StandardClaims from a non-standard payload.
        // Return `Err(_)` to propagate provider errors.
        Ok(StandardClaims { /* … */ })
    });
```

The default mapper handles standard OIDC claims and rejects payloads missing
`sub`. (#3999)

### Caching

Discovery documents and JWKS are cached in-memory through the existing
`DiscoveryClient` / `JwksCache` (default TTL: 1h). Override per-provider via
`discovery_ttl` and `jwks_ttl` on `GenericOidcConfig`.

### Security guarantees

- ID token JWS verification is **mandatory** (signature, `iss`, `aud`, `exp`, `iat` skew).
- `alg: none` and any symmetric `HS*` algorithm are **unconditionally rejected**.
- Allowed asymmetric algorithms are intersected with the IdP's advertised
  `id_token_signing_alg_values_supported`.
- `client_secret` is redacted from `Debug` output to avoid log leaks.
- PKCE verifier never leaks into the authorization URL (verified by integration test
  `pkce_state_and_challenge_round_trip_through_authorization_url`).

### GitHub Provider Claims (rc.23 fix)

Prior to rc.23, `GitHubProvider::get_user_info` delegated to the generic
`UserInfoClient`, which attempted to deserialize GitHub's `/user` response directly
into `StandardClaims`. Because GitHub returns numeric `id` (not OIDC `sub`),
deserialization always failed and `claims = None` was silently returned via `.ok()`
in `SocialAuthBackend::handle_callback`. rc.23 introduces an explicit
`GitHubUserResponse` → `StandardClaims` mapping (`map_github_user_to_claims`) so
real GitHub callbacks now populate `sub` (stringified `id`), `picture`
(`avatar_url`), and a `name`-falls-back-to-`login` mapping. (#4004)

### EC Key Support for OIDC (rc.23+)

`Jwk::to_decoding_key()` now supports EC (Elliptic Curve) keys on P-256, P-384,
and P-521 curves, unblocking ID-token verification against IdPs that publish
EC-only JWKs (Keycloak realm keys configured with ES256, AWS Cognito user pools
on ES256, Apple Sign in with Apple end-to-end ES256, Authentik with ES256
signing keys). This removes the EC-exclusion limitation explicitly noted in the
original `GenericOidcProvider` PR. (#4005)

**Algorithm availability in rc.23:**

| JWK `crv` | jsonwebtoken `Algorithm` | Reachable from `GenericOidcProvider`? |
|-----------|--------------------------|---------------------------------------|
| `P-256`   | `ES256`                  | yes (in `SUPPORTED_ASYMMETRIC_ALGORITHMS`) |
| `P-384`   | `ES384`                  | yes (in `SUPPORTED_ASYMMETRIC_ALGORITHMS`) |
| `P-521`   | (no `ES512` variant in `jsonwebtoken 10.3.0`) | JWK decodes, but ID-token verification not reachable until upstream adds `ES512` |
