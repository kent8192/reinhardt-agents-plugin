---
name: admin
description: Use when setting up or customizing the reinhardt admin panel - covers AdminSite configuration, ModelAdmin registration, and the #[admin] macro
versions: ["0.1.2", "0.2.x"]
---

# Reinhardt Admin Panel

Guide developers through setting up and customizing the reinhardt admin panel for model management.

## When to Use

- User sets up an admin panel for their application
- User registers models with admin
- User customizes admin list views, filters, or search
- User mentions: "admin", "admin panel", "ModelAdmin", "AdminSite", "admin interface", "back office"

## Workflow

### Setting Up Admin Panel

1. Read `references/admin-setup.md` for initial setup
2. Configure `AdminSite` with auth settings
3. Create `ModelAdmin` structs using `#[admin]` macro
4. Register models with the admin site
5. Mount admin routes in `UnifiedRouter`

### Customizing Model Admin

1. Read `references/model-admin.md` for `#[admin]` macro options
2. Configure list_display, list_filter, search_fields, ordering
3. Set readonly_fields for non-editable fields
4. Configure permissions

## Important Rules

- Always set `set_user_type` and `set_jwt_secret` for admin auth
- Use `admin_routes_with_di` for DI-compatible admin routing
- Mount admin at `/admin/` and static files at `/static/admin/`
- Feature flag: `admin` must be enabled in Cargo.toml

## Dynamic References

For the latest admin API:
1. Read `reinhardt/crates/reinhardt-admin/src/core/site.rs` for AdminSite
2. Read `reinhardt/crates/reinhardt-admin/src/core/model_admin.rs` for ModelAdmin trait
3. Read `reinhardt-cloud/dashboard/src/config/admin.rs` for production example
