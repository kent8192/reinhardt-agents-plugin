# Reinhardt Permissions Reference

## Permission Trait

The core authorization interface:

```rust
#[async_trait]
pub trait Permission: Send + Sync {
    async fn has_permission(&self, context: &PermissionContext<'_>) -> bool;
}
```

**Module:** `reinhardt_auth::core::permission` (re-exported via `reinhardt::auth`)

### PermissionContext

```rust
pub struct PermissionContext<'a> {
    pub request: &'a reinhardt_http::Request,
    pub is_authenticated: bool,
    pub is_admin: bool,
    pub is_active: bool,
    pub user: Option<Box<dyn User>>,
}
```

---

## Built-in Permission Classes

### Basic Permissions

| Permission | Description | Allows When |
|-----------|-------------|-------------|
| `AllowAny` | No restrictions | Always |
| `IsAuthenticated` | Requires authentication | `is_authenticated == true` |
| `IsAdminUser` | Requires admin | `is_authenticated && is_admin` |
| `IsActiveUser` | Requires active account | `is_authenticated && is_active` |
| `IsAuthenticatedOrReadOnly` | Read access for all, write for authenticated | `is_authenticated` OR `method in [GET, HEAD, OPTIONS]` |

All implement `Clone`, `Copy`, `Default`.

### Usage with ViewSet Handlers

```rust
use std::sync::Arc;
use reinhardt::auth::IsAuthenticated;

fn user_handler() -> ModelViewSetHandler<User> {
    ModelViewSetHandler::<User>::new()
        .add_permission(Arc::new(IsAuthenticated))
}
```

---

## Permission Operators

Combine permissions with boolean logic:

```rust
use reinhardt::auth::permission_operators::{AndPermission, OrPermission, NotPermission};

// AND: both must pass
let perm = AndPermission::new(IsAuthenticated, IsActiveUser);

// OR: at least one must pass
let perm = OrPermission::new(IsAdminUser, IsStaffUser);

// NOT: inverts the result
let perm = NotPermission::new(IsAnonymous);
```

> **Prefer** the `guard!` macro over manual operator usage — see `guards.md`.

---

## Django Model Permissions

**Module:** `reinhardt_auth::model_permissions`

Maps HTTP methods to `app_label.action_model` format permissions (Django-style):

| HTTP Method | Permission Format |
|-------------|------------------|
| POST | `app.add_<model>` |
| PUT / PATCH | `app.change_<model>` |
| DELETE | `app.delete_<model>` |
| GET / HEAD / OPTIONS | `app.view_<model>` |

### DjangoModelPermissions

```rust
pub struct DjangoModelPermissions { /* ... */ }
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new() -> Self` | Create instance |
| `with_model_name` | `fn with_model_name(model_name: &str) -> Self` | Create for specific model |
| `add_user_permission` | `fn add_user_permission(&mut self, username: &str, permission: &str)` | Grant permission |
| `user_has_permission` | `async fn user_has_permission(&self, username: &str, permission: &str) -> bool` | Check permission |

### DjangoModelPermissionsOrAnonReadOnly

Same as above but allows anonymous read access (GET/HEAD/OPTIONS).

### ModelPermission<T>

Type-safe model permission:

```rust
pub struct ModelPermission<T> { /* ... */ }

impl<T> ModelPermission<T> {
    pub fn new(operation: impl Into<String>) -> Self;
    pub fn operation(&self) -> &str;
}
```

---

## Object Permissions

**Module:** `reinhardt_auth::object_permissions`

Fine-grained per-object access control.

### ObjectPermissionChecker Trait

```rust
#[async_trait]
pub trait ObjectPermissionChecker: Send + Sync {
    async fn has_object_permission(
        &self,
        user: &dyn User,
        object_id: &str,
        permission: &str,
    ) -> bool;
}
```

### ObjectPermissionManager

Built-in in-memory implementation:

```rust
pub struct ObjectPermissionManager { /* ... */ }
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `fn new() -> Self` | Create manager |
| `grant_permission` | `async fn grant_permission(&mut self, username: &str, object_id: &str, permission: &str)` | Grant access |
| `revoke_permission` | `async fn revoke_permission(&mut self, username: &str, object_id: &str, permission: &str)` | Revoke access |
| `revoke_all_permissions` | `async fn revoke_all_permissions(&mut self, username: &str, object_id: &str)` | Revoke all |
| `list_permissions` | `async fn list_permissions(&self, username: &str, object_id: &str) -> Vec<String>` | List grants |

Implements both `ObjectPermissionChecker` and `Permission`.

### ObjectPermission Wrapper

Wraps any `ObjectPermissionChecker` into a `Permission`:

```rust
pub struct ObjectPermission<T: ObjectPermissionChecker> { /* ... */ }

impl<T: ObjectPermissionChecker> ObjectPermission<T> {
    pub fn new(checker: T, object_id: impl Into<String>, permission: impl Into<String>) -> Self;
}
```

### Example

```rust
let mut manager = ObjectPermissionManager::new();
manager.grant_permission("alice", "post-123", "edit").await;
manager.grant_permission("alice", "post-123", "delete").await;

// Check
assert!(manager.has_object_permission(&user, "post-123", "edit").await);
assert!(!manager.has_object_permission(&user, "post-456", "edit").await);
```

---

## Role-Based Permission

**Module:** `reinhardt_auth::advanced_permissions`

```rust
pub struct RoleBasedPermission { /* ... */ }
```

Implements `Permission` — checks user roles against required roles.

---

## IP-Based Permissions

**Module:** `reinhardt_auth::ip_permission`

```rust
pub struct IpWhitelistPermission { /* CIDRs */ }
pub struct IpBlacklistPermission { /* CIDRs */ }
pub struct CidrRange { /* ... */ }
```

Allow or deny based on client IP address with CIDR support.

### Example

```rust
let whitelist = IpWhitelistPermission::new(vec![
    CidrRange::parse("10.0.0.0/8").unwrap(),
    CidrRange::parse("192.168.1.0/24").unwrap(),
]);
```

---

## Time-Based Permissions

**Module:** `reinhardt_auth::time_based_permission`

```rust
pub struct TimeBasedPermission { /* ... */ }
pub struct TimeWindow { pub start: NaiveTime, pub end: NaiveTime }
pub struct DateRange { pub start: NaiveDate, pub end: NaiveDate }
```

Restrict access to specific time windows or date ranges.

---

## Rate Limit Permission

**Feature:** `rate-limit`

**Module:** `reinhardt_auth::rate_limit_permission`

```rust
pub struct RateLimitPermission { /* ... */ }
pub struct RateLimitPermissionBuilder { /* ... */ }
```

Rate-limiting as a permission check. Denies requests that exceed the configured rate.

---

## Custom Permission Example

```rust
use reinhardt::auth::prelude::*;

pub struct IsProjectOwner;

#[async_trait]
impl Permission for IsProjectOwner {
    async fn has_permission(&self, context: &PermissionContext<'_>) -> bool {
        let Some(user) = &context.user else {
            return false;
        };

        // Extract project_id from request path
        let project_id = context.request
            .path_param("project_id")
            .unwrap_or_default();

        // Check ownership (application-specific logic)
        is_owner(user.id(), &project_id).await
    }
}
```

## Version Differences (0.2.x)

### User-ID-Based Permission Lookups

In 0.2.x, permission lookups use user ID instead of username for resolution. This affects `PermissionContext` and any code that resolves permissions by username string:

```rust
// 0.1.x — username-based
context.has_perm("app.change_article", &username).await

// 0.2.x — user-ID-based
context.has_perm("app.change_article", user_id).await
```

---

## Dynamic References

For the latest permission API:

1. Read `reinhardt/crates/reinhardt-auth/src/core/permission.rs` for Permission trait and built-ins
2. Read `reinhardt/crates/reinhardt-auth/src/core/permission_operators.rs` for And/Or/Not
3. Read `reinhardt/crates/reinhardt-auth/src/model_permissions.rs` for Django-style
4. Read `reinhardt/crates/reinhardt-auth/src/object_permissions.rs` for object-level
5. Read `reinhardt/crates/reinhardt-auth/src/ip_permission.rs` for IP-based
6. Read `reinhardt/crates/reinhardt-auth/src/time_based_permission.rs` for time-based
7. Read `reinhardt/crates/reinhardt-auth/src/rate_limit_permission.rs` for rate limiting
