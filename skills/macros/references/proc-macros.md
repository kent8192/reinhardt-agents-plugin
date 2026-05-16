# Reinhardt Function-Like Macros Reference

Function-like procedural macros invoked with `macro_name!(...)` syntax.

---

## `guard!`

**Crate:** `reinhardt-auth/macros`

Generate type-safe permission guard expressions with boolean operators.

### Syntax

```rust
guard!(Permission)              // Single permission
guard!(A & B)                   // AND: All<(A, B)>
guard!(A | B)                   // OR: Any<(A, B)>
guard!(!A)                      // NOT: Not<A>
guard!((A | B) & C)             // Grouping
guard!(mod::path::Permission)   // Qualified paths
```

### Operator Precedence

| Operator | Precedence | Expands To |
|----------|-----------|------------|
| `!` | Highest | `Not<P>` |
| `&` | Middle | `All<(P1, P2)>` |
| `\|` | Lowest | `Any<(P1, P2)>` |

### Expansion Examples

| Input | Expanded Type |
|-------|---------------|
| `guard!(IsAdminUser)` | `Guard<IsAdminUser>` |
| `guard!(IsAuthenticated & IsActiveUser)` | `Guard<All<(IsAuthenticated, IsActiveUser)>>` |
| `guard!(IsAdminUser \| IsStaffUser)` | `Guard<Any<(IsAdminUser, IsStaffUser)>>` |
| `guard!(!IsAnonymous)` | `Guard<Not<IsAnonymous>>` |
| `guard!((A \| B) & C)` | `Guard<All<(Any<(A, B)>, C)>>` |

### Usage

```rust
use reinhardt::auth::prelude::*;

#[get("/admin/", name = "admin_panel")]
pub async fn admin_panel(
    _guard: guard!(IsAdminUser & IsActiveUser),
    #[inject] AuthUser(user): AuthUser<User>,
) -> ViewResult<Response> {
    // Only active admins reach here
}
```

---

## `installed_apps!`

**Crate:** `reinhardt-core/macros`

Compile-time validated application registry.

### Syntax

```rust
installed_apps! {
    users: "users",
    posts: "posts",
    comments: "comments",
}
```

Each entry maps a Rust identifier to an app label string. Duplicate labels are detected at compile time.

### Usage

```rust
// src/config/apps.rs
use reinhardt::installed_apps;

installed_apps! {
    auth: "auth",
    blog: "blog",
    api: "api",
}
```

---

## `path!`

**Crate:** `reinhardt-urls/routers-macros`

Validate URL path syntax at compile time.

### Syntax

```rust
path!("/users/")
path!("/users/{user_id}/")
path!("/users/{user_id}/posts/{post_id}/")
```

### Validation Rules

| Rule | Description |
|------|-------------|
| Must start with `/` | `path!("users/")` is invalid |
| Parameters must be `{snake_case}` | `path!("/users/{userId}/")` is invalid |
| No double slashes | `path!("/users//posts/")` is invalid |
| No `..` path traversal | `path!("/users/../admin/")` is invalid |
| No nested parameters | `path!("/users/{{id}}/")` is invalid |
| Unique parameter names | `path!("/users/{id}/posts/{id}/")` is invalid |

### Usage in Routing

```rust
use reinhardt::urls::path;

let router = UnifiedRouter::new()
    .route(path!("/users/"), user_list)
    .route(path!("/users/{user_id}/"), user_detail);
```

---

## `page!`

**Crate:** `reinhardt-pages/macros`

**Feature:** `pages`

Anonymous component DSL for WASM frontend views.

```rust
page!(|name: String| {
    div {
        h1 { "Hello, {name}!" }
        p { "Welcome to Reinhardt Pages." }
    }
})
```

---

## `head!`

**Crate:** `reinhardt-pages/macros`

**Feature:** `pages`

HTML `<head>` section DSL.

```rust
head!({
    title { "My Page Title" }
    meta { charset: "utf-8" }
    link { rel: "stylesheet", href: "/static/styles.css" }
})
```

---

## `form!`

**Crate:** `reinhardt-pages/macros`

**Feature:** `pages`

Type-safe form component bound to a `#[server_fn]` submission handler.

### Syntax (rc.22+)

```rust
form! {
    server_fn: submit_login,    // The #[server_fn] target
    method: Post,               // Get | Post | Put | Patch | Delete
    fields: {
        username: CharField { required },
        password: CharField { required, min_length: 8 },
    },
    strip_arguments: {
        // Explicit, named expressions routed positionally to server_fn.
        // Compiler-validated: rejects duplicate keys and field-name collisions.
        csrf_token: ::reinhardt::reinhardt_pages::csrf::get_csrf_token()
            .unwrap_or_default(),
    },
}
```

The receiving `#[server_fn]` declares `csrf_token: String` (or `_csrf_token`
if discarded) as an explicit parameter alongside the form fields.

### `strip_arguments` semantics (added in rc.22)

- The mechanism is **not CSRF-specific**. Any expression — context lookups,
  feature-detection results, build-time constants — may be routed.
- The validator rejects duplicate keys and collisions with declared form
  fields at compile time.
- Each entry is appended **positionally** to the `server_fn` call in the
  order it appears, so the server-fn signature must match.

### Backward-compatible auto-injection

Unmigrated forms still compile: when `strip_arguments` is omitted and
`method != Get`, the macro silently appends `__csrf_token: String` for
backward compatibility (and emits a deprecation marker). New code should
prefer the explicit `strip_arguments` form because it surfaces the wiring
at the call site, lets the compiler validate arity, and makes the mechanism
generalizable beyond CSRF.

### Migration from pre-rc.22 implicit CSRF auto-inject

```rust
// Before (rc.21 and earlier) — silent argument arity surprise on WASM
#[server_fn]
pub async fn submit(payload: String) -> Result<(), ServerFnError> { /* ... */ }

form! {
    server_fn: submit,
    method: Post,
    fields: { payload: CharField { required } },
}

// After (rc.22 onward) — explicit, compiler-validated wiring
#[server_fn]
pub async fn submit(
    payload: String,
    _csrf_token: String,
) -> Result<(), ServerFnError> { /* ... */ }

form! {
    server_fn: submit,
    method: Post,
    fields: { payload: CharField { required } },
    strip_arguments: {
        csrf_token: ::reinhardt::reinhardt_pages::csrf::get_csrf_token()
            .unwrap_or_default(),
    },
}
```

CSRF verification continues to run in the server-side CSRF middleware; the
receiving handler may discard the value (`_csrf_token`).

## Dynamic References

For the latest function-like macro definitions:
1. Read `reinhardt/crates/reinhardt-auth/macros/src/lib.rs` for guard!
2. Read `reinhardt/crates/reinhardt-core/macros/src/lib.rs` for installed_apps!
3. Read `reinhardt/crates/reinhardt-urls/routers-macros/src/lib.rs` for path!
4. Read `reinhardt/crates/reinhardt-pages/macros/src/lib.rs` for page!, head!, form!
