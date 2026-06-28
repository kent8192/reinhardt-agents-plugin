---
name: authorization
description: Use when configuring authorization and permissions in reinhardt-web applications - covers Permission trait, Guard types, guard! macro, model/object permissions, and auth extractors
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Authorization

Guide developers through authorization setup using reinhardt-auth, including permission classes, guard types, the `guard!` macro, and auth extractors.

## When to Use

- User configures access control or permissions
- User defines permission classes or guards
- User uses `#[permission_required]` attribute
- User works with `Guard<P>`, `AuthInfo`, `CurrentUser<T>`, or legacy `AuthUser<T>` usage
- User mentions: "permission", "authorization", "guard", "access control", "role", "admin only", "IsAuthenticated", "AllowAny", "RBAC", "object permission", "model permission", "IP whitelist", "rate limit"

## Workflow

### Adding Permission Checks to Views

1. Read `references/guards.md` for Guard types and `guard!` macro
2. Choose permission class from `references/permissions.md`
3. Apply via `Guard<P>` in handler parameters (DI) or `#[permission_required]` attribute
4. Use `guard!` macro for combining permissions (`&`, `|`, `!`)

### Using Auth Extractors

1. Read `references/extractors.md` for `AuthInfo` and `CurrentUser<T>`
2. Use `AuthInfo` for lightweight access (reads request extensions, no DB query)
3. Use `CurrentUser<T>` for full user model (loads from DB)
4. Both use `#[inject]` — requires `params` feature

### Implementing Custom Permissions

1. Read `references/permissions.md` for the `Permission` trait
2. Implement `async fn has_permission(&self, context: &PermissionContext<'_>) -> bool`
3. Register as injectable if needed

### Object-Level Permissions

1. Read `references/permissions.md` (Object Permissions section)
2. Implement `ObjectPermissionChecker` trait
3. Use `ObjectPermission<T>` wrapper to create `Permission` impl
4. Manage grants via `ObjectPermissionManager`

## Important Rules

- `Guard<P>` is the primary mechanism for DI-based permission checks (returns 403 on failure)
- `Public` guard always succeeds (equivalent to `AllowAny` in guard context)
- `guard!` macro precedence: `!` > `&` > `|` — use parentheses for clarity
- `AuthInfo` is lightweight (no DB query) — use when you only need auth state
- `CurrentUser<T>` loads from DB — use when you need user model fields
- `AuthUser<T>` is removed in 0.3.x — replace it with `CurrentUser<T>` before upgrading
- Permission checks run **before** the handler executes
- `#[permission_required]` is for attribute-based access control on views
- For ViewSet permissions, use handler builder APIs such as `ModelViewSetHandler::add_permission(...)`; per-action override hooks are not part of the current ViewSet API

## Cross-Domain References

- For auth backend setup: `../authentication/SKILL.md`
- For DI patterns with guards: `../dependency-injection/references/di-patterns.md`
- For auth config in API endpoints: `../api-development/references/auth-config.md`

## Dynamic References

For the latest authorization API:

1. Read `reinhardt/crates/reinhardt-auth/src/core/permission.rs` for Permission trait
2. Read `reinhardt/crates/reinhardt-auth/src/guard.rs` for Guard, Public, All, Any, Not
3. Read `reinhardt/crates/reinhardt-auth/macros/src/lib.rs` for guard! macro
4. Read `reinhardt/crates/reinhardt-auth/src/model_permissions.rs` for DjangoModelPermissions
5. Read `reinhardt/crates/reinhardt-auth/src/object_permissions.rs` for ObjectPermission
6. Read `reinhardt/crates/reinhardt-auth/src/advanced_permissions.rs` for RoleBasedPermission
7. Read `reinhardt/crates/reinhardt-auth/src/ip_permission.rs` for IP-based permissions
8. Read `reinhardt/crates/reinhardt-auth/src/time_based_permission.rs` for time-based permissions
9. Read `reinhardt/crates/reinhardt-auth/src/rate_limit_permission.rs` for rate limiting
