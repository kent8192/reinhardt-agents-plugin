# API Client & Table Component Reference

## API Client (Django QuerySet-like)

### ApiModel

Implement the `ApiModel` trait to connect a struct to a REST endpoint:

```rust
use reinhardt::pages::api::{ApiModel, ApiQuerySet};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
struct User {
    id: i64,
    username: String,
    email: String,
}

impl ApiModel for User {
    fn endpoint() -> &'static str {
        "/api/users/"
    }
}
```

`ApiModel` is a trait (not a derive macro). It requires `Serialize + DeserializeOwned` and one method: `fn endpoint() -> &'static str`. This enables `User::objects()` to return an `ApiQuerySet<User>`.

### ApiQuerySet

Familiar Django-style query interface for WASM:

```rust
// Get all
let users = User::objects()
    .all()
    .await?;

// Get by ID
let user = User::objects()
    .get(1)
    .await?;

// Filter
let active_users = User::objects()
    .filter("is_active", true)
    .order_by(&["-created_at"])
    .limit(10)
    .all()
    .await?;
```

### QuerySet Methods

| Method | Description |
|--------|-------------|
| `.filter(field, value)` | Equality filter |
| `.filter_op(field, op, value)` | Filter with operator |
| `.exclude(field, value)` | Exclusion filter |
| `.order_by(&[fields])` | Sort (prefix `-` for descending) |
| `.limit(n)` | Limit results |
| `.offset(n)` | Skip first n results |
| `.only(fields)` | Select specific fields |
| `.all()` | Execute and return all results |
| `.get(id)` | Get single item by ID |
| `.first()` | Get first matching item |
| `.count()` | Count matching items |
| `.exists()` | Check if any items match |
| `.create(data)` | Create a new item |
| `.update(pk, data)` | Full update of an item |
| `.partial_update(pk, data)` | Partial update |
| `.delete(pk)` | Delete an item |

### Filter and FilterOp

```rust
use reinhardt::pages::prelude::{Filter, FilterOp};

// Simple equality filter
let filter = Filter::exact("is_active", true);

// Filter with operator
let filter = Filter::with_op("age", FilterOp::Gte, 18);
let users = User::objects()
    .filter_op("age", FilterOp::Gte, 18)
    .all()
    .await?;
```

### CSRF Integration

API calls automatically include CSRF tokens:

```rust
use reinhardt::pages::prelude::get_csrf_token;

// Manual CSRF token access (rarely needed)
let token = get_csrf_token();
```

## Table Component

Django-tables2 equivalent for rendering data tables. `Table` is a trait — implement it on your own struct.

### Column Types

| Column | Description |
|--------|-------------|
| `Column<T>` | Basic typed column |
| `LinkColumn` | Column with link |
| `BooleanColumn` | True/false display |
| `CheckBoxColumn` | Checkbox column |
| `DateTimeColumn` | Date/time formatting |
| `EmailColumn` | Email link |
| `ChoiceColumn` | Display mapped choices |
| `TemplateColumn` | Custom template rendering |
| `JSONColumn` | JSON data display |
| `URLColumn` | URL link |

### Column Setup

```rust
use reinhardt::pages::tables::columns::*;

let name_col = Column::<String>::new("name", "Name");
let email_col = EmailColumn::new("email", "Email");
let active_col = BooleanColumn::new("is_active", "Active");
let profile_col = LinkColumn::new("id", "Profile", "/users/{id}");
```

### Sorting (Sortable trait)

```rust
use reinhardt::pages::tables::{Sortable, SortDirection};

// Implement Sortable trait on your table type
table.sort_by("name", SortDirection::Ascending);

// Query current sort state
let current = table.current_sort();
```

### Pagination

```rust
use reinhardt::pages::tables::Pagination;

// Constructor takes per_page only
let mut pagination = Pagination::new(20);

// Set page and query state
pagination.set_page(3);
let total = pagination.total_pages();
let next = pagination.next_page();   // Option<usize>
let prev = pagination.prev_page();   // Option<usize>
let start = pagination.start_index();
let end = pagination.end_index();

// Table trait method
table.handle_pagination(3);
```

### Filtering (Filterable trait)

```rust
use reinhardt::pages::tables::Filterable;

// Implement Filterable trait on your table type
table.filter_by("is_active", "true");
table.clear_filters();
let active = table.current_filters();
```

### Export (Exportable trait)

```rust
use reinhardt::pages::tables::{ExportFormat, Exportable};
use std::io::Write;

// ExportFormat variants (uppercase)
// ExportFormat::CSV, ExportFormat::JSON, ExportFormat::Excel, ExportFormat::YAML

// Export requires a writer and returns Result
let mut buf = Vec::new();
table.export(&mut buf, ExportFormat::CSV)?;
```
