# ModelAdmin Configuration

## The `#[admin]` Macro

Define ModelAdmin structs using the `#[admin]` macro for declarative configuration:

```rust
use reinhardt::admin;
use crate::models::Cluster;

#[admin(model,
    for = Cluster,
    name = "Cluster",
    list_display = [id, user_id, name, api_url, is_active, created_at],
    list_filter = [is_active],
    search_fields = [name, api_url],
    ordering = [(created_at, desc)],
    readonly_fields = [id, created_at, updated_at],
    list_per_page = 25,
    permissions = allow_all
)]
pub struct ClusterAdmin;
```

## `#[admin]` Macro Options

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `for = Model` | Type | Target model type (required) | `for = User` |
| `name = "..."` | String | Display name in admin panel | `name = "User"` |
| `list_display = [...]` | Field list | Fields shown in list view | `list_display = [id, name, email]` |
| `list_filter = [...]` | Field list | Filter sidebar fields | `list_filter = [is_active]` |
| `search_fields = [...]` | Field list | Fields searchable via admin search bar | `search_fields = [name, email]` |
| `ordering = [(field, dir)]` | Tuple list | Default sort order (`asc` or `desc`) | `ordering = [(created_at, desc)]` |
| `readonly_fields = [...]` | Field list | Non-editable fields in detail view | `readonly_fields = [id, created_at]` |
| `list_per_page = N` | Integer | Pagination size (default: 25) | `list_per_page = 50` |
| `permissions = ...` | Policy | Permission policy for the model | `permissions = allow_all` |

## Examples

### User Administration

```rust
use reinhardt::admin;
use crate::models::User;

#[admin(model,
    for = User,
    name = "User",
    list_display = [id, username, email, is_active, is_staff, is_superuser, last_login, date_joined],
    list_filter = [is_active, is_staff, is_superuser],
    search_fields = [username, email],
    ordering = [(date_joined, desc)],
    readonly_fields = [id, password_hash, last_login, date_joined, updated_at],
    list_per_page = 25,
    permissions = allow_all
)]
pub struct UserAdmin;
```

### Blog Post Administration

```rust
use reinhardt::admin;
use crate::models::Post;

#[admin(model,
    for = Post,
    name = "Post",
    list_display = [id, title, author_id, status, published_at, created_at],
    list_filter = [status],
    search_fields = [title],
    ordering = [(created_at, desc)],
    readonly_fields = [id, created_at, updated_at],
    list_per_page = 20,
    permissions = allow_all
)]
pub struct PostAdmin;
```

## ModelAdmin Trait (Manual Implementation)

For advanced customization beyond the macro, implement the `ModelAdmin` trait directly:

```rust
use reinhardt::admin::ModelAdmin;

pub trait ModelAdmin: Send + Sync {
    fn model_name(&self) -> &str;
    fn table_name(&self) -> &str { "" }
    fn pk_field(&self) -> &str { "id" }
    fn list_display(&self) -> Vec<&str> { vec!["id"] }
    fn list_filter(&self) -> Vec<&str> { vec![] }
    fn search_fields(&self) -> Vec<&str> { vec![] }
    fn fields(&self) -> Option<Vec<&str>> { None }
    fn readonly_fields(&self) -> Vec<&str> { vec![] }
    fn ordering(&self) -> Vec<&str> { vec![] }
    fn list_per_page(&self) -> Option<usize> { None }

    // Permission methods
    async fn has_view_permission(&self, user: &dyn AdminUser) -> bool { true }
    async fn has_add_permission(&self, user: &dyn AdminUser) -> bool { true }
    async fn has_change_permission(&self, user: &dyn AdminUser) -> bool { true }
    async fn has_delete_permission(&self, user: &dyn AdminUser) -> bool { true }
}
```

### When to Use Manual Implementation

- Custom logic for determining displayed fields based on user permissions
- Dynamic list_display that changes based on request context
- Custom queryset filtering beyond simple field filters
- Override default CRUD behavior (e.g., soft delete instead of hard delete)

### Manual Implementation Example

```rust
use reinhardt::admin::ModelAdmin;

pub struct AuditLogAdmin;

impl ModelAdmin for AuditLogAdmin {
    fn model_name(&self) -> &str { "AuditLog" }
    fn table_name(&self) -> &str { "audit_logs" }

    fn list_display(&self) -> Vec<&str> {
        vec!["id", "action", "user_id", "resource", "timestamp"]
    }

    fn search_fields(&self) -> Vec<&str> {
        vec!["action", "resource"]
    }

    fn readonly_fields(&self) -> Vec<&str> {
        // All fields are readonly for audit logs
        vec!["id", "action", "user_id", "resource", "details", "timestamp"]
    }

    fn list_per_page(&self) -> usize { 50 }
}
```

## AdminDatabase and AdminRecord

The admin panel uses `AdminDatabase` for database operations and `AdminRecord` for data representation. These are abstracted — you do not interact with them directly in most cases. The admin framework handles:

- Querying the database based on `list_display` fields
- Applying filters from `list_filter` configuration
- Executing search queries across `search_fields`
- Pagination using `list_per_page`
- Sorting based on `ordering` configuration

## Registering ModelAdmin

After defining a ModelAdmin struct, register it with the `AdminSite`:

```rust
admin_site.register("Cluster", ClusterAdmin).expect("failed to register");
```

The first argument is the display name used in the admin panel navigation. It should match the `name` field in the `#[admin]` macro for consistency.
