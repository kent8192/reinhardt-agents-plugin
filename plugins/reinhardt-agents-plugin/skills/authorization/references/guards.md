# Reinhardt Guards Reference

## Guard System Overview

Guards are DI-integrated permission wrappers. When injected into a handler, they check the `Permission` during dependency resolution and return HTTP 403 if denied.

**Module:** `reinhardt_auth::guard` (re-exported via `reinhardt::auth`)

**Feature:** `params` (enabled by default)

---

## Guard Types

### `Guard<P: Permission>`

The primary permission guard. Wraps any `Permission` type and performs the check during DI injection.

```rust
pub struct Guard<P: Permission>(PhantomData<P>);
```

- Zero-sized marker type
- Implements `Injectable` — automatically checked when injected
- Returns HTTP 403 Forbidden on failure

### `Public`

No-op guard that always succeeds. Equivalent to `Guard<AllowAny>`.

```rust
pub struct Public;
```

### `All<(P1, P2, ...)>`

AND combinator — all permissions must pass. Supports tuple arity 2-8.

```rust
pub struct All<T>(PhantomData<T>);
// All<(IsAuthenticated, IsActiveUser)> — both must pass
```

### `Any<(P1, P2, ...)>`

OR combinator — at least one permission must pass. Supports tuple arity 2-8.

```rust
pub struct Any<T>(PhantomData<T>);
// Any<(IsAdminUser, IsStaffUser)> — either can pass
```

### `Not<P>`

NOT combinator — inverts the permission result.

```rust
pub struct Not<P>(PhantomData<P>);
// Not<IsAnonymous> — deny anonymous users
```

---

## `guard!` Macro

**Module:** `reinhardt_auth::macros` (re-exported via `reinhardt::auth`)

Generates type-safe guard expressions with boolean operators:

### Syntax

```rust
guard!(Permission)              // Single permission
guard!(A & B)                   // AND
guard!(A | B)                   // OR
guard!(!A)                      // NOT
guard!((A | B) & C)             // Grouping
guard!(mod::path::Permission)   // Qualified paths
```

### Operator Precedence

| Operator | Precedence | Description |
|----------|-----------|-------------|
| `!` | Highest | NOT |
| `&` | Middle | AND |
| `\|` | Lowest | OR |

### Expansion Examples

```rust
guard!(IsAdminUser)
// → Guard<IsAdminUser>

guard!(IsAuthenticated & IsActiveUser)
// → Guard<All<(IsAuthenticated, IsActiveUser)>>

guard!(IsAdminUser | IsStaffUser)
// → Guard<Any<(IsAdminUser, IsStaffUser)>>

guard!(!IsAnonymous)
// → Guard<Not<IsAnonymous>>

guard!((IsAdminUser | IsStaffUser) & IsActiveUser)
// → Guard<All<(Any<(IsAdminUser, IsStaffUser)>, IsActiveUser)>>
```

---

## Usage in Handlers

### With `guard!` macro (recommended)

```rust
use reinhardt::views::prelude::*;
use reinhardt::auth::prelude::*;

#[get("/admin/users/", name = "admin_user_list")]
pub async fn admin_user_list(
    _guard: guard!(IsAdminUser & IsActiveUser),
) -> ViewResult<Response> {
    let users = User::objects().all().await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&users)?))
}
```

### With explicit Guard type

```rust
#[get("/dashboard/", name = "dashboard")]
pub async fn dashboard(
    _guard: Guard<IsAuthenticated>,
) -> ViewResult<Response> {
    // Only authenticated users reach here
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&dashboard_data)?))
}
```

### Public access

```rust
#[get("/health/", name = "health_check")]
pub async fn health_check(
    _guard: Public,
) -> ViewResult<Response> {
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&json!({ "status": "ok" }))?))
}
```

### Combining Guard with Auth Extractors

```rust
#[get("/profile/", name = "user_profile")]
pub async fn user_profile(
    _guard: guard!(IsAuthenticated),
    #[inject] AuthUser(user): AuthUser<User>,
) -> ViewResult<Response> {
    // Guard ensures auth, AuthUser provides the user model
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&user)?))
}
```

---

## `#[permission_required]` Attribute

Alternative to Guard for attribute-based access control:

```rust
use reinhardt::prelude::*;

#[permission_required("users.can_edit")]
#[get("/users/{id}/edit/", name = "edit_user")]
pub async fn edit_user(
    Path(id): Path<Uuid>,
) -> ViewResult<Response> {
    // Only users with "users.can_edit" permission reach here
    let user = User::objects().get(id).await?;
    Ok(Response::new(StatusCode::OK)
        .with_body(json::to_vec(&user)?))
}
```

---

## Guard vs `#[permission_required]`

| Feature | `Guard<P>` / `guard!` | `#[permission_required]` |
|---------|----------------------|--------------------------|
| **Mechanism** | DI injection | Attribute macro |
| **Type safety** | Compile-time type checked | String-based permission name |
| **Combining** | `&`, `\|`, `!` operators | Single permission per attribute |
| **Custom permissions** | Any `Permission` impl | Named permissions only |
| **When checked** | During DI resolution | Before handler execution |
| **Recommended** | For type-safe, composable checks | For simple named permissions |

## Dynamic References

For the latest guard API:

1. Read `reinhardt/crates/reinhardt-auth/src/guard.rs` for Guard, Public, All, Any, Not
2. Read `reinhardt/crates/reinhardt-auth/macros/src/lib.rs` for guard! macro implementation
3. Read `reinhardt/crates/reinhardt-core/macros/src/lib.rs` for permission_required macro
