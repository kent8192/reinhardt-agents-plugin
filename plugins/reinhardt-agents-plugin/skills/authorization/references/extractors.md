# Reinhardt Auth Extractors Reference

Auth extractors provide access to authentication state and user data in handlers via dependency injection.

**Feature:** `params` (enabled by default)

---

## Extractor Comparison

| Extractor | DB Query | Returns | Use Case |
|-----------|----------|---------|----------|
| `AuthInfo` | No | `AuthState` (user_id, flags) | Lightweight auth check, routing decisions |
| `AuthUser<U>` | Yes | Full user model `U` | When you need user fields (name, email, etc.) |
| `CurrentUser<U>` | **DEPRECATED** | — | Use `AuthUser<U>` instead |

---

## AuthInfo (Lightweight)

**Module:** `reinhardt_auth::auth_info`

Reads authentication state from request extensions without querying the database. This is the pattern used in the reinhardt-cloud dashboard.

```rust
pub struct AuthInfo(pub AuthState);
```

### AuthState

```rust
pub struct AuthState {
    // Access methods:
    pub fn user_id(&self) -> Option<&str>;
    pub fn is_authenticated(&self) -> bool;
    pub fn is_admin(&self) -> bool;
    pub fn is_staff(&self) -> bool;
    pub fn is_active(&self) -> bool;
}
```

### Usage

```rust
use reinhardt::views::prelude::*;

#[get("/profile/", name = "user_profile")]
pub async fn get_profile(
    #[inject] AuthInfo(state): AuthInfo,
) -> ViewResult<Response> {
    let user_id = state.user_id()
        .ok_or(AppError::Authentication("Not authenticated".into()))?;

    // Use user_id for queries without loading the full user model
    let profile = Profile::objects()
        .filter(Profile::user_id.eq(user_id))
        .get().await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&profile)?))
}
```

### When to Use AuthInfo

- You only need the user ID (e.g., for filtering queries)
- You only need auth flags (is_authenticated, is_admin, etc.)
- Performance matters — avoids a DB round-trip
- The auth middleware already validated the token/session

---

## AuthUser<U> (Full User Model)

**Module:** `reinhardt_auth::auth_user`

Loads the full user model from the database using the authenticated user's ID.

```rust
pub struct AuthUser<U: BaseUser>(pub U);
```

### Type Constraints

```rust
where
    U: BaseUser + Model + Clone + Send + Sync + 'static,
    <U as BaseUser>::PrimaryKey: FromStr + ToString + Send + Sync,
    <U as Model>::PrimaryKey: From<<U as BaseUser>::PrimaryKey>,
```

### Usage

```rust
use reinhardt::views::prelude::*;
use reinhardt::auth::prelude::*;

#[get("/admin/dashboard/", name = "admin_dashboard")]
pub async fn admin_dashboard(
    #[inject] AuthUser(user): AuthUser<User>,
) -> ViewResult<Response> {
    if !user.is_staff {
        return Err(AppError::Authentication("Admin access required".into()));
    }
    // `user` is a full User model instance loaded from DB
    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&DashboardData::for_user(&user).await?)?))
}
```

### Error Behavior

| Condition | Response |
|-----------|----------|
| Not authenticated | HTTP 401 Unauthorized |
| User not found in DB | HTTP 401 Unauthorized |
| Database error | HTTP 500 Internal Server Error |

### When to Use AuthUser

- You need user fields (name, email, roles, etc.)
- You need to check user-specific attributes beyond basic flags
- You need to pass the user model to other services
- The small DB overhead is acceptable

---

## Combining Extractors with Guards

```rust
// Guard + AuthInfo (lightweight)
#[get("/api/data/", name = "api_data")]
pub async fn api_data(
    _guard: guard!(IsAuthenticated),
    #[inject] AuthInfo(state): AuthInfo,
) -> ViewResult<Response> {
    // Guard ensures auth, AuthInfo provides user_id
    let data = Data::objects()
        .filter(Data::owner_id.eq(state.user_id().unwrap()))
        .all().await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&data)?))
}

// Guard + AuthUser (full model)
#[get("/admin/settings/", name = "admin_settings")]
pub async fn admin_settings(
    _guard: guard!(IsAdminUser & IsActiveUser),
    #[inject] AuthUser(user): AuthUser<User>,
) -> ViewResult<Response> {
    // Guard ensures admin + active, AuthUser provides full model
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&Settings::for_admin(&user)?)?))
}
```

---

## Server Functions (Pages/WASM)

```rust
use reinhardt::pages::prelude::*;

#[server_fn]
pub async fn get_user_profile() -> Result<UserProfile, ServerFnError> {
    // In server functions, auth info is available from the request context
    let auth_info = extract_auth_info()?;
    let user_id = auth_info.user_id()
        .ok_or(ServerFnError::new("Not authenticated"))?;

    let profile = UserProfile::objects()
        .filter(UserProfile::user_id.eq(user_id))
        .get().await
        .map_err(|e| ServerFnError::new(e.to_string()))?;

    Ok(profile)
}
```

## Version Differences (0.2.x)

In 0.2.x, auth extractors return types based on the unified `AuthIdentity` trait instead of concrete user types. `AuthUser<T>` still resolves the full user model, but the underlying authentication layer uses `Box<dyn AuthIdentity>` instead of `Box<dyn User>`.

---

## Dynamic References

For the latest extractor API:

1. Read `reinhardt/crates/reinhardt-auth/src/auth_info.rs` for AuthInfo
2. Read `reinhardt/crates/reinhardt-auth/src/auth_user.rs` for AuthUser
3. Read `reinhardt/crates/reinhardt-auth/src/current_user.rs` for deprecated CurrentUser
