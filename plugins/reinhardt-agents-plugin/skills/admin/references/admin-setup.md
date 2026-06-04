# Admin Panel Setup

## Feature Flag

Enable the `admin` feature in your `Cargo.toml`:

```toml
[dependencies]
reinhardt = { version = "...", features = ["admin"] }
```

## AdminSite Configuration

Create and configure an `AdminSite` with authentication and model registrations:

```rust
use reinhardt::admin::AdminSite;

pub fn configure_admin() -> AdminSite {
    let mut admin_site = AdminSite::new("My App Administration");

    // Authentication setup (required)
    admin_site.set_user_type::<User>();
    if let Some(secret) = get_jwt_secret() {
        admin_site.set_jwt_secret(secret.as_bytes());
    }

    // Register models
    admin_site
        .register("User", UserAdmin)
        .expect("failed to register User admin");
    admin_site
        .register("Product", ProductAdmin)
        .expect("failed to register Product admin");

    admin_site
}
```

### AdminSite Methods

| Method | Description |
|--------|-------------|
| `AdminSite::new(title)` | Create with display title |
| `.set_user_type::<U>()` | Set user model for authentication |
| `.set_jwt_secret(bytes)` | Set JWT secret for admin auth tokens |
| `.set_url_prefix(prefix)` | Set URL prefix for admin routes |
| `.set_favicon(data)` | Set custom favicon data |
| `.register(name, admin)` | Register a ModelAdmin instance |
| `.unregister(name)` | Remove a registered ModelAdmin |
| `.registered_models()` | List all registered model names |

## Mounting in Router

Use `admin_routes_with_di` for DI-compatible routing:

```rust
use reinhardt::admin::{admin_routes_with_di, core::admin_static_routes};

#[routes]
pub fn routes() -> UnifiedRouter {
    let admin_site = Arc::new(configure_admin());
    let (admin_router, admin_di) = admin_routes_with_di(admin_site);

    UnifiedRouter::new()
        .mount("/admin/", admin_router)
        .mount("/static/admin/", admin_static_routes())
        .with_di_registrations(admin_di)
        // ... other routes
}
```

### Key Points

- Wrap `AdminSite` in `Arc` before passing to `admin_routes_with_di`
- The function returns a tuple: `(ServerRouter, DiRegistrationList)`
- Mount admin routes at `/admin/` (conventional path)
- Mount admin static files at `/static/admin/` for CSS/JS assets
- Call `.with_di_registrations(admin_di)` to wire admin services into the DI container

## Authentication Requirements

The admin panel requires:

1. **User type** — A model implementing the admin user trait, set via `set_user_type::<U>()`
2. **JWT secret** — Used for admin session tokens, set via `set_jwt_secret(bytes)`

### Getting the JWT Secret from Settings

```rust
fn get_jwt_secret() -> Option<String> {
    // From environment variable
    std::env::var("REINHARDT_ADMIN_JWT_SECRET").ok()
    // Or from project settings via DI
}
```

## Complete Setup Example

```rust
use std::sync::Arc;
use reinhardt::admin::{AdminSite, admin_routes_with_di, core::admin_static_routes};
use reinhardt::routes;
use reinhardt::urls::prelude::UnifiedRouter;

// 1. Define ModelAdmin structs (see model-admin.md)
// 2. Configure AdminSite
pub fn configure_admin() -> AdminSite {
    let mut admin_site = AdminSite::new("My App Admin");

    admin_site.set_user_type::<User>();
    admin_site.set_jwt_secret(b"your-secret-key");

    admin_site.register("User", UserAdmin).unwrap();
    admin_site.register("Post", PostAdmin).unwrap();
    admin_site.register("Comment", CommentAdmin).unwrap();

    admin_site
}

// 3. Mount in router
#[routes]
pub fn routes() -> UnifiedRouter {
    let admin_site = Arc::new(configure_admin());
    let (admin_router, admin_di) = admin_routes_with_di(admin_site);

    UnifiedRouter::new()
        .mount("/admin/", admin_router)
        .mount("/static/admin/", admin_static_routes())
        .with_di_registrations(admin_di)
}
```

---

## Version Differences (0.2.x)

### SecurityMiddleware Builder

In 0.2.x, `SecurityConfig` is removed. If the admin panel mounts security middleware, use the builder API directly:

```rust
// 0.2.x
SecurityMiddleware::new()
    .with_hsts(true)
    .with_ssl_redirect(settings.is_production())
```
