# Reinhardt QuerySet API Reference

Reinhardt provides two query APIs at different abstraction levels:

1. **ORM API** (`Model::objects()`) — Django-style, recommended for application code
2. **Low-Level Query Builder** (`reinhardt-query`) — SeaQuery-based, for migrations and raw schema operations

---

## ORM API: Model::objects()

The `Model` trait provides an `objects()` method that returns a `Manager<M>`, which is the entry point for all database operations. Manager methods return a `QuerySet<M>` for fluent query building.

```text
Model::objects() -> Manager<M>
    .all()             -> QuerySet<M>   -> .all().await -> Vec<M>
    .filter(...)       -> QuerySet<M>   -> .all().await -> Vec<M>
    .get(pk)           -> QuerySet<M>   -> .all().await -> Vec<M>
    .create(&model)    -----------------> async Result<M>
    .update(&model)    -----------------> async Result<M>
    .delete(pk)        -----------------> async Result<()>
```

### Basic CRUD

```rust
// Get all records
let users = User::objects().all().all().await?;

// Get by primary key
let user = User::objects().get(42).all().await?;

// Create (INSERT)
let new_user = User { id: None, name: "Alice".to_string(), .. };
let created = User::objects().create(&new_user).await?;

// Update
let updated = User::objects().update(&user).await?;

// Delete by primary key
User::objects().delete(42).await?;

// Count
let total = User::objects().count().await?;

// Bulk operations
let users = User::objects().bulk_create(&[user1, user2, user3]).await?;
let updated = User::objects().bulk_update(&[user1, user2]).await?;

// Get or create (returns (model, was_created))
let (user, created) = User::objects().get_or_create(...).await?;
```

### Filtering

```rust
use reinhardt_db::orm::query::{FilterOperator, FilterValue};

// Filter with operator and value
let active_users = User::objects()
    .filter("is_active", FilterOperator::Eq, FilterValue::Bool(true))
    .all()
    .await?;

// Filter with generated field helpers (preferred for application code)
let alice = User::objects()
    .filter_by(User::field_name().eq("Alice"))
    .all()
    .await?;

let project_docs = Document::objects()
    .filter_by(Document::field_project().eq(project_id))
    .all()
    .await?;

// Type-safe FieldRef
let users = User::objects()
    .filter(User::field_email(), FilterOperator::Eq,
        FilterValue::String("alice@example.com".to_string()))
    .all()
    .await?;
```

Prefer generated field helpers such as `<Model>::field_project().eq(value)` for
application filters. Use lower-level filter constructors only when building
schema tooling or query abstractions that cannot express the predicate through
model metadata.

### Ordering, Pagination, Limit/Offset

```rust
// Order by (ascending)
let users = User::objects().order_by(&["name"]).all().await?;

// Descending order (prefix with "-")
let users = User::objects().order_by(&["-created_at"]).all().await?;

// Multiple fields
let users = User::objects().order_by(&["department", "-salary"]).all().await?;

// Limit
let users = User::objects().limit(10).all().await?;

// Offset
let users = User::objects().offset(20).all().await?;

// Pagination (page, page_size)
let users = User::objects().paginate(3, 10).all().await?;  // page 3, 10 per page
```

### Field Selection

```rust
// Load only specified fields (Django's only())
let users = User::objects().only(&["id", "username"]).all().await?;

// Exclude specified fields from initial load (Django's defer())
let users = User::objects().defer(&["bio", "profile_picture"]).all().await?;

// Select specific fields (Django's values())
let data = User::objects().values(&["id", "username", "email"]).all().await?;

// Alias for values() (Django's values_list())
let data = User::objects().values_list(&["id", "username"]).all().await?;
```

### Relationship Loading

```rust
// Eager load with JOIN (Django's select_related)
let posts = Post::objects()
    .select_related(&["author", "category"])
    .all()
    .await?;

// Prefetch with separate queries (Django's prefetch_related)
let posts = Post::objects()
    .prefetch_related(&["comments", "tags"])
    .all()
    .await?;
```

### Annotations and Aggregation

```rust
use reinhardt_db::orm::annotation::{Annotation, AnnotationValue};
use reinhardt_db::orm::aggregation::Aggregate;

// Add computed field
let users = User::objects()
    .annotate(Annotation::new("total_orders",
        AnnotationValue::Aggregate(Aggregate::count(Some("orders")))))
    .all()
    .await?;

// Scalar subquery annotation
let users = User::objects()
    .annotate_subquery("latest_post_title", |builder| {
        builder
            .select("title")
            .from("posts")
            .where_("user_id = users.id")
            .order_by("-created_at")
            .limit(1)
    })
    .all()
    .await?;
```

### PostgreSQL-Specific Filters

```rust
// Array overlap (&&)
let posts = Post::objects()
    .filter_array_overlap("tags", &["rust", "web"])
    .all().await?;

// Array contains (@>)
let posts = Post::objects()
    .filter_array_contains("tags", &["rust", "web"])
    .all().await?;

// JSONB contains (@>)
let users = User::objects()
    .filter_jsonb_contains("metadata", r#"{"role": "admin"}"#)
    .all().await?;

// JSONB key exists (?)
let users = User::objects()
    .filter_jsonb_key_exists("metadata", "email")
    .all().await?;

// Range contains (@>)
let events = Event::objects()
    .filter_range_contains("date_range", "2024-01-15")
    .all().await?;

// Full-text search
let posts = Post::objects()
    .full_text_search("content", "rust async")
    .all().await?;
```

### Subquery Filters

```rust
// IN subquery
let users = User::objects()
    .filter_in_subquery("id", |sq| {
        sq.select("user_id").from("orders").where_("total > 100")
    })
    .all().await?;

// NOT IN subquery
let users = User::objects()
    .filter_not_in_subquery("id", |sq| {
        sq.select("user_id").from("banned_users")
    })
    .all().await?;

// EXISTS subquery
let users = User::objects()
    .filter_exists(|sq| {
        sq.from("orders").where_("orders.user_id = users.id")
    })
    .all().await?;
```

### CTE (Common Table Expressions)

```rust
let users = User::objects()
    .with_cte(cte)
    .all().await?;
```

### Connection-Aware Methods

When you need explicit connection control (e.g., in transactions):

```rust
let result = User::objects().create_with_conn(&conn, &user).await?;
let result = User::objects().update_with_conn(&conn, &user).await?;
User::objects().delete_with_conn(&conn, pk).await?;
let count = User::objects().count_with_conn(&conn).await?;
```

### Manager Method Reference

| Method | Returns | Description |
|--------|---------|-------------|
| `all()` | `QuerySet<M>` | All records |
| `filter(field, op, value)` | `QuerySet<M>` | Filter with operator/value |
| `filter_by(Filter)` | `QuerySet<M>` | Filter with Filter object |
| `get(pk)` | `QuerySet<M>` | Get by primary key |
| `limit(n)` | `QuerySet<M>` | LIMIT clause |
| `offset(n)` | `QuerySet<M>` | OFFSET clause |
| `order_by(&[fields])` | `QuerySet<M>` | ORDER BY (prefix "-" for DESC) |
| `paginate(page, size)` | `QuerySet<M>` | Pagination (LIMIT + OFFSET) |
| `only(&[fields])` | `QuerySet<M>` | Load only specified fields |
| `defer(&[fields])` | `QuerySet<M>` | Exclude fields from initial load |
| `values(&[fields])` | `QuerySet<M>` | Select specific fields |
| `values_list(&[fields])` | `QuerySet<M>` | Alias for values() |
| `select_related(&[fields])` | `QuerySet<M>` | Eager load with JOIN |
| `prefetch_related(&[fields])` | `QuerySet<M>` | Prefetch with separate queries |
| `annotate(Annotation)` | `QuerySet<M>` | Add computed field |
| `annotate_subquery(name, fn)` | `QuerySet<M>` | Add scalar subquery |
| `filter_array_overlap(field, &[])` | `QuerySet<M>` | PostgreSQL array && |
| `filter_array_contains(field, &[])` | `QuerySet<M>` | PostgreSQL array @> |
| `filter_jsonb_contains(field, json)` | `QuerySet<M>` | PostgreSQL JSONB @> |
| `filter_jsonb_key_exists(field, key)` | `QuerySet<M>` | PostgreSQL JSONB ? |
| `filter_range_contains(field, val)` | `QuerySet<M>` | PostgreSQL range @> |
| `filter_in_subquery(field, fn)` | `QuerySet<M>` | IN subquery |
| `filter_not_in_subquery(field, fn)` | `QuerySet<M>` | NOT IN subquery |
| `filter_exists(fn)` | `QuerySet<M>` | EXISTS subquery |
| `filter_not_exists(fn)` | `QuerySet<M>` | NOT EXISTS subquery |
| `full_text_search(field, query)` | `QuerySet<M>` | Full-text search |
| `with_cte(cte)` | `QuerySet<M>` | Common Table Expression |
| `create(&model)` | `async Result<M>` | INSERT single record |
| `update(&model)` | `async Result<M>` | UPDATE single record |
| `delete(pk)` | `async Result<()>` | DELETE by primary key |
| `count()` | `async Result<i64>` | COUNT records |
| `bulk_create(&[models])` | `async Result<Vec<M>>` | Bulk INSERT |
| `bulk_update(&[models])` | `async Result<Vec<M>>` | Bulk UPDATE |
| `get_or_create(...)` | `async Result<(M, bool)>` | Get or create |

### QuerySet Execution Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `.all().await` | `Result<Vec<T>>` | Execute and return all records |
| `.get().await` | `Result<T>` | Execute and return single record |
| `.count().await` | `Result<usize>` | Execute and return count |
| `.exists().await` | `Result<bool>` | Execute and return existence check |

---

## CustomManager (0.1.x: HasCustomManager / 0.2.x: Objects Associated Type)

For Django-style custom object managers — typically used to enforce row-level access control, default tenant filters, or `bulk_update` permission checks — Reinhardt introduces the opt-in `CustomManager` and `HasCustomManager` traits in `reinhardt-db` (#3981).

### Design Overview

- `CustomManager<M>` is a trait with **53 default-implemented operations** covering the full `Manager<M>` surface (CRUD, filtering, bulk ops, SQL helpers). Implementors override **only** the methods they care about.
- `HasCustomManager` is the opt-in marker trait wired by `#[model(manager = <Path>)]` — see `model-patterns.md` for the macro usage.
- **Three veto hooks** are provided to intercept mutating operations:
  - `before_save(&self, model: &M) -> Result<()>` — runs before `create` / `update`.
  - `before_delete(&self, pk: &M::Pk) -> Result<()>` — runs before `delete`.
  - `before_bulk_update(&self, models: &[M]) -> Result<()>` — runs before `bulk_update`.
  Returning `Err(_)` aborts the operation.
- **Backward compatible**: the `Model` trait is untouched. `Model::objects()` still returns the inherent `Manager<Self>` for every existing model. Opting into a custom manager is purely additive.
- The blanket impl guarantees SQL parity: `bulk_create_sql` / `get_or_create_sql` produce identical output through the trait path and the inherent path.

### Example

```rust
use reinhardt::db::prelude::*;

pub struct TenantScopedManager;

impl<M: Model> CustomManager<M> for TenantScopedManager {
    async fn before_save(&self, model: &M) -> Result<(), DbError> {
        // Enforce tenant isolation before persisting.
        ensure_current_tenant_owns(model)?;
        Ok(())
    }
    // The other 52 methods use the trait defaults.
}
```

### Version Differences

**0.1.x (rc.23+):** Uses the `HasCustomManager` trait with a `custom_manager()` method. `Model::objects()` returns `Manager<Self>` by default; the custom manager is a secondary, opt-in access path.

**0.2.x:** The `HasCustomManager` trait is removed. The `Model` trait now has an associated type `type Objects: CustomManager<Model = Self> + Default`. `Model::objects()` returns the custom manager directly. When writing manual `Model` implementations (without the `#[model]` macro), you must add `type Objects = Manager<Self>;` for the default manager.

```rust
// 0.1.x
impl HasCustomManager for Article {
    type Manager = PublishedManager;
    fn custom_manager() -> Self::Manager { PublishedManager }
}

// 0.2.x — Objects associated type on Model
// (handled automatically by #[model(manager = PublishedManager)])
// For manual impls:
impl Model for Article {
    type Objects = PublishedManager;
    // ...
}
```

## Low-Level Query Builder (reinhardt-query)

For schema operations (DDL), migrations, and cases where the ORM abstraction is insufficient, use `reinhardt-query` directly. This is a SeaQuery-based type-safe SQL builder.

**Use for:** Migrations, schema management, raw queries, database-specific operations.
**Do NOT use for:** Application-level CRUD (use `Model::objects()` instead).

### Schema Operations (DDL)

#### CREATE TABLE

```rust
use reinhardt_query::{Query, ColumnDef, Table, ColumnType, ForeignKey, Index};

let create_stmt = Query::create_table()
    .table(Users::Table)
    .if_not_exists()
    .col(
        ColumnDef::new(Users::Id)
            .big_integer()
            .not_null()
            .auto_increment()
            .primary_key(),
    )
    .col(
        ColumnDef::new(Users::Username)
            .string_len(150)
            .not_null()
            .unique_key(),
    )
    .col(
        ColumnDef::new(Users::Email)
            .string_len(254)
            .not_null(),
    )
    .col(
        ColumnDef::new(Users::IsActive)
            .boolean()
            .not_null()
            .default(true),
    )
    .col(
        ColumnDef::new(Users::CreatedAt)
            .timestamp_with_time_zone()
            .not_null()
            .default(Expr::current_timestamp()),
    )
    .col(
        ColumnDef::new(Users::LastLogin)
            .timestamp_with_time_zone()
            .null(),
    )
    .to_owned();

db.execute(create_stmt).await?;
```

#### ALTER TABLE

```rust
// Add a column
let alter_stmt = Query::alter_table()
    .table(Users::Table)
    .add_column(
        ColumnDef::new(Users::Bio)
            .text()
            .null(),
    )
    .to_owned();

db.execute(alter_stmt).await?;

// Modify a column
let alter_stmt = Query::alter_table()
    .table(Users::Table)
    .modify_column(
        ColumnDef::new(Users::Username)
            .string_len(255)
            .not_null(),
    )
    .to_owned();

db.execute(alter_stmt).await?;

// Drop a column
let alter_stmt = Query::alter_table()
    .table(Users::Table)
    .drop_column(Users::Bio)
    .to_owned();

db.execute(alter_stmt).await?;
```

#### DROP TABLE

```rust
let drop_stmt = Query::drop_table()
    .table(Users::Table)
    .if_exists()
    .to_owned();

db.execute(drop_stmt).await?;
```

#### CREATE INDEX

```rust
let index_stmt = Query::index_create()
    .name("idx_users_email")
    .table(Users::Table)
    .col(Users::Email)
    .unique()
    .to_owned();

db.execute(index_stmt).await?;
```

#### FOREIGN KEY

```rust
let create_stmt = Query::create_table()
    .table(Posts::Table)
    .col(
        ColumnDef::new(Posts::Id)
            .big_integer()
            .not_null()
            .auto_increment()
            .primary_key(),
    )
    .col(
        ColumnDef::new(Posts::AuthorId)
            .big_integer()
            .not_null(),
    )
    .foreign_key(
        ForeignKey::create()
            .name("fk_posts_author")
            .from(Posts::Table, Posts::AuthorId)
            .to(Users::Table, Users::Id)
            .on_delete(ForeignKeyAction::Cascade)
            .on_update(ForeignKeyAction::Cascade),
    )
    .to_owned();
```

### Data Operations (DML)

#### INSERT

```rust
use reinhardt_query::{Query, Expr};

// Single row
let insert_stmt = Query::insert()
    .into_table(Users::Table)
    .columns([Users::Username, Users::Email, Users::IsActive])
    .values_panic(["alice".into(), "alice@example.com".into(), true.into()])
    .to_owned();

db.execute(insert_stmt).await?;

// Multiple rows
let insert_stmt = Query::insert()
    .into_table(Users::Table)
    .columns([Users::Username, Users::Email])
    .values_panic(["alice".into(), "alice@example.com".into()])
    .values_panic(["bob".into(), "bob@example.com".into()])
    .to_owned();

db.execute(insert_stmt).await?;

// Insert with RETURNING (PostgreSQL)
let insert_stmt = Query::insert()
    .into_table(Users::Table)
    .columns([Users::Username, Users::Email])
    .values_panic(["alice".into(), "alice@example.com".into()])
    .returning_col(Users::Id)
    .to_owned();

let id: i64 = db.query_one(insert_stmt).await?;
```

#### SELECT with Filter, Order, Limit

```rust
// Basic select
let select_stmt = Query::select()
    .columns([Users::Id, Users::Username, Users::Email])
    .from(Users::Table)
    .to_owned();

let rows = db.query_all(select_stmt).await?;

// Filtered select
let select_stmt = Query::select()
    .columns([Users::Id, Users::Username])
    .from(Users::Table)
    .and_where(Expr::col(Users::IsActive).eq(true))
    .and_where(Expr::col(Users::Username).like("a%"))
    .to_owned();

// Ordering
let select_stmt = Query::select()
    .columns([Users::Id, Users::Username])
    .from(Users::Table)
    .order_by(Users::CreatedAt, Order::Desc)
    .to_owned();

// Limit and offset (pagination)
let select_stmt = Query::select()
    .columns([Users::Id, Users::Username])
    .from(Users::Table)
    .order_by(Users::Id, Order::Asc)
    .limit(10)
    .offset(20)
    .to_owned();

// Join
let select_stmt = Query::select()
    .columns([Posts::Id, Posts::Title])
    .column((Users::Table, Users::Username))
    .from(Posts::Table)
    .inner_join(
        Users::Table,
        Expr::col((Posts::Table, Posts::AuthorId))
            .equals((Users::Table, Users::Id)),
    )
    .to_owned();

// Aggregation
let select_stmt = Query::select()
    .expr_as(Expr::col(Users::Id).count(), Alias::new("total"))
    .from(Users::Table)
    .and_where(Expr::col(Users::IsActive).eq(true))
    .to_owned();
```

#### UPDATE

```rust
let update_stmt = Query::update()
    .table(Users::Table)
    .value(Users::IsActive, false.into())
    .value(Users::UpdatedAt, Expr::current_timestamp().into())
    .and_where(Expr::col(Users::Id).eq(42))
    .to_owned();

db.execute(update_stmt).await?;
```

#### DELETE

```rust
let delete_stmt = Query::delete()
    .from_table(Users::Table)
    .and_where(Expr::col(Users::IsActive).eq(false))
    .to_owned();

db.execute(delete_stmt).await?;
```

### Column Definition Methods

Quick reference for `ColumnDef` builder methods:

| Method | SQL Effect | Notes |
|--------|------------|-------|
| `.big_integer()` | `BIGINT` | 64-bit integer |
| `.integer()` | `INTEGER` | 32-bit integer |
| `.small_integer()` | `SMALLINT` | 16-bit integer |
| `.float()` | `REAL` | 32-bit float |
| `.double()` | `DOUBLE PRECISION` | 64-bit float |
| `.decimal_len(p, s)` | `DECIMAL(p, s)` | Fixed-point number |
| `.string_len(n)` | `VARCHAR(n)` | Variable-length string |
| `.text()` | `TEXT` | Unbounded text |
| `.boolean()` | `BOOLEAN` | True/false |
| `.timestamp_with_time_zone()` | `TIMESTAMPTZ` | Timestamp with timezone |
| `.timestamp()` | `TIMESTAMP` | Timestamp without timezone |
| `.date()` | `DATE` | Date only |
| `.time()` | `TIME` | Time only |
| `.binary()` | `BYTEA` / `BLOB` | Binary data |
| `.json()` | `JSON` | JSON data |
| `.json_binary()` | `JSONB` | Binary JSON (PostgreSQL) |
| `.uuid()` | `UUID` | UUID type |
| `.not_null()` | `NOT NULL` | Disallow NULL |
| `.null()` | (nullable) | Allow NULL |
| `.default(val)` | `DEFAULT val` | Set default value |
| `.auto_increment()` | `SERIAL` / `AUTO_INCREMENT` | Auto-incrementing |
| `.primary_key()` | `PRIMARY KEY` | Primary key constraint |
| `.unique_key()` | `UNIQUE` | Unique constraint |

### Backend Support

`reinhardt-query` generates backend-specific SQL:

| Backend | Placeholder | Identifier Quoting |
|---------|-------------|-------------------|
| PostgreSQL | `$1, $2, ...` | `"identifier"` |
| MySQL | `?, ?, ...` | `` `identifier` `` |
| SQLite | `?, ?, ...` | `"identifier"` |
| CockroachDB | `$1, $2, ...` | `"identifier"` |
