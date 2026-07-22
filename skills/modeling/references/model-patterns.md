# Reinhardt Model Patterns Reference

## Basic Model Definition

Models are defined as Rust structs with the `#[model]` attribute macro. The macro generates the database table mapping, field definitions, and QuerySet integration.

```rust
use reinhardt::db::prelude::*;
use chrono::{DateTime, Utc};

#[model(table_name = "users")]
#[derive(Debug, Clone)]
pub struct User {
    #[field(primary_key = true)]
    pub id: i64,

    #[field(max_length = 150, unique = true)]
    pub username: String,

    #[field(max_length = 254)]
    pub email: String,

    #[field(default = true)]
    pub is_active: bool,

    #[field(auto_now_add = true)]
    pub created_at: DateTime<Utc>,

    #[field(auto_now = true)]
    pub updated_at: DateTime<Utc>,

    #[field(null = true)]
    pub last_login: Option<DateTime<Utc>>,
}
```

## Field Attribute Options

The `#[field]` attribute accepts these options to configure column behavior:

| Option | Type | Description |
|--------|------|-------------|
| `primary_key` | `bool` | Marks the field as the table's primary key. Only one per model. |
| `max_length` | `usize` | Maximum character length for `String` fields. Required for `VARCHAR` columns. |
| `unique` | `bool` | Adds a `UNIQUE` constraint to the column. |
| `default` | literal | Default value for the column. Supports Rust literals (`true`, `false`, `0`, `""`, etc.). |
| `generated` | `SchemaExpr` | **(0.4.x)** Portable, typed generated-column expression. Pair with exactly one storage attribute. |
| `generated_sql` | `&str` | **(0.4.x)** Trusted backend-specific generated-column expression when the portable `SchemaExpr` subset cannot express it. |
| `generated_stored` | `bool` | **(0.4.x)** Store the generated value. Required as one of the two storage choices. |
| `generated_virtual` | `bool` | **(0.4.x, MySQL/SQLite)** Compute the generated value virtually. Required as one of the two storage choices when used. |
| `auto_now_add` | `bool` | Automatically set to the current timestamp on row creation. |
| `auto_now` | `bool` | Automatically set to the current timestamp on every save. |
| `null` | `bool` | Whether the column allows `NULL`. Corresponding Rust type must be `Option<T>`. |
| `db_index` | `bool` | Creates a database index on this column. |
| `db_column` | `&str` | Override the database column name (defaults to the field name). |
| `blank` | `bool` | Whether the field is allowed to be empty (validation-level, not DB-level). |
| `verbose_name` | `&str` | Human-readable name for the field, used in admin and error messages. |
| `skip_info` | `bool` | **(0.2.x)** Excludes this field from the auto-generated `{Model}Info` companion struct. Use for sensitive data (e.g., password hashes). |

### Field Annotation Rule

Every scalar model field should carry `#[field(...)]`. Use bare `#[field]`
when no constraint or default is needed. This keeps macro-generated metadata,
migrations, validators, and `{Model}Info` output aligned across the whole model.

Relation fields use `#[rel(...)]` instead. Do not mix relationship marker types
with plain unmanaged foreign-key IDs unless the scalar ID is an intentional
denormalized/cache field and is named accordingly.

### Relationship Field Audit

Before adding a `#[model]`, list its ForeignKey, OneToOne, and ManyToMany
relationships. Each relationship must use a `#[rel(...)]` marker field rather
than a scalar ID column.

#### Anti-pattern

```rust
#[model(table_name = "articles")]
#[derive(Debug, Clone)]
pub struct Article {
    #[field(primary_key = true)]
    pub id: i64,

    #[field]
    pub author_id: i64,
}
```

#### Preferred

```rust
#[model(table_name = "articles")]
#[derive(Debug, Clone)]
pub struct Article {
    #[field(primary_key = true)]
    pub id: i64,

    #[rel(foreign_key, to = "User", related_name = "articles", on_delete = "CASCADE")]
    pub author: ForeignKeyField<User>,
}
```

After editing, scan every `#[model]` for suspicious `*_id` fields such as
`author_id`, `user_id`, `profile_id`, and `article_id`. Replace any relationship
with the appropriate `#[rel(...)]` field. A scalar `*_id` is acceptable only
when it is not a Reinhardt relationship, such as an external-system identifier
or an intentionally denormalized cache key; name it for that purpose and
document the reason next to the field.

The Semgrep hook audits every `*_id` field inside a `#[model]`, including one
next to a relationship marker, because a duplicate scalar still needs review.
For a valid external or denormalized exception, keep the reason on the field and
add this narrow inline suppression:

```rust
#[field]
pub source_system_record_id: String, // nosemgrep: reinhardt-no-scalar-fk-id -- Immutable external audit identifier.
```

Never use the suppression for a Reinhardt relationship; replace that scalar with
the appropriate `#[rel(...)]` field instead.

## Typed Generated Columns (0.4.x)

**Source:** [original PR #5586](https://github.com/kent8192/reinhardt-web/pull/5586)
defined the typed contract; [merged cherry-pick PR #5615](https://github.com/kent8192/reinhardt-web/pull/5615)
contains its final migration and ORM behavior.

Prefer the portable, DDL-safe `SchemaExpr` subset. It accepts
`SchemaExpr::col`, `SchemaExpr::val`, `SchemaExpr::concat`, and
`SchemaExpr::coalesce`, with chained `binary` and `cast` calls. For example:

```rust
use reinhardt::db::migrations::SchemaExpr;

#[model(table_name = "users")]
#[derive(Debug, Clone)]
pub struct User {
    #[field(primary_key = true)]
    pub id: Option<i64>,

    #[field(max_length = 100)]
    pub first_name: String,

    #[field(max_length = 100)]
    pub last_name: String,

    #[field(
        max_length = 201,
        generated = SchemaExpr::concat([
            SchemaExpr::col("first_name"),
            SchemaExpr::val(" "),
            SchemaExpr::col("last_name"),
        ]),
        generated_stored = true,
    )]
    pub full_name: String,
}
```

Do not use the former raw-string form `generated = "..."`. Use
`generated_sql = "..."` only for a trusted backend-specific expression that
cannot be represented by `SchemaExpr`; it is intentionally an explicit escape
hatch, not the default.

Use exactly one of `generated_stored = true` or `generated_virtual = true`.
Virtual generated columns are available only with the MySQL or SQLite features;
PostgreSQL and CockroachDB require stored generated columns. Generated columns
cannot have a default or auto-increment. SQLite rejects generated primary keys,
and MySQL rejects virtual generated primary keys.

PostgreSQL and CockroachDB also reject a generated column that references
another generated column. Model portable chains from their non-generated input
columns and validate the generated migration on the actual target backend.

Generated fields are read-only. The macro removes them from required model
builder inputs, although an optional builder setter may still exist; ORM write
paths omit any supplied generated value. Keep them out of create/update DTOs
and `QuerySet::update_fields` assignments. Do not make an ordinary create
workflow depend on a model that has no writable fields.

## Rust Type to Database Type Mapping

| Rust Type | Database Type | Notes |
|-----------|---------------|-------|
| `i16` | `SMALLINT` | |
| `i32` | `INTEGER` | |
| `i64` | `BIGINT` | Recommended for primary keys |
| `f32` | `REAL` / `FLOAT` | |
| `f64` | `DOUBLE PRECISION` | |
| `bool` | `BOOLEAN` | |
| `String` | `VARCHAR(max_length)` | Requires `max_length` attribute |
| `String` (no max_length) | `TEXT` | Unbounded text |
| `DateTime<Utc>` | `TIMESTAMPTZ` | From `chrono` crate |
| `NaiveDate` | `DATE` | From `chrono` crate |
| `NaiveTime` | `TIME` | From `chrono` crate |
| `Vec<u8>` | `BYTEA` / `BLOB` | Binary data |
| `serde_json::Value` | `JSONB` | Requires `serde_json` |
| `Uuid` | `UUID` | From `uuid` crate. `#[model]` generates `Uuid::now_v7()` for `Option<Uuid>` primary keys (time-ordered, better B-tree index performance) |
| `Decimal` | `NUMERIC` / `DECIMAL` | From `rust_decimal` crate |
| `Option<T>` | Nullable variant of `T` | Column allows `NULL` |

## Relations

### ForeignKey

A many-to-one relationship. Defined with the `#[rel]` attribute on the field.

```rust
#[model(table_name = "posts")]
#[derive(Debug, Clone)]
pub struct Post {
    #[field(primary_key = true)]
    pub id: i64,

    #[field(max_length = 200)]
    pub title: String,

    #[rel(foreign_key, to = "User", related_name = "posts", on_delete = "CASCADE")]
    pub author: ForeignKeyField<User>,

    #[field(auto_now_add = true)]
    pub published_at: DateTime<Utc>,
}
```

The `on_delete` option controls referential integrity:

| Value | Behavior |
|-------|----------|
| `CASCADE` | Delete related rows when the referenced row is deleted |
| `PROTECT` | Prevent deletion of the referenced row |
| `SET_NULL` | Set the foreign key to `NULL` (field must be `Option<ForeignKeyField<T>>`) |
| `SET_DEFAULT` | Set the foreign key to its default value |
| `DO_NOTHING` | Take no action (may violate constraints) |

### ManyToMany

A many-to-many relationship creates a join table automatically.

```rust
#[model(table_name = "articles")]
#[derive(Debug, Clone)]
pub struct Article {
    #[field(primary_key = true)]
    pub id: i64,

    #[field(max_length = 200)]
    pub title: String,

    #[rel(many_to_many, to = "Tag", related_name = "articles")]
    pub tags: ManyToManyField<Article, Tag>,
}

#[model(table_name = "tags")]
#[derive(Debug, Clone)]
pub struct Tag {
    #[field(primary_key = true)]
    pub id: i64,

    #[field(max_length = 50, unique = true)]
    pub name: String,
}
```

### Model with `app_label` (Polls Example)

Models that belong to a specific app use the `app_label` attribute:

```rust
#[model(table_name = "questions", app_label = "polls")]
#[derive(Debug, Clone)]
pub struct Question {
    #[field(primary_key = true)]
    pub id: i64,

    #[field(max_length = 200)]
    pub question_text: String,

    #[field(auto_now_add = true)]
    pub pub_date: DateTime<Utc>,
}

#[model(table_name = "choices", app_label = "polls")]
#[derive(Debug, Clone)]
pub struct Choice {
    #[field(primary_key = true)]
    pub id: i64,

    #[rel(foreign_key, to = "Question", related_name = "choices", on_delete = "CASCADE")]
    pub question: ForeignKeyField<Question>,

    #[field(max_length = 200)]
    pub choice_text: String,

    #[field(default = 0)]
    pub votes: i32,
}
```

## Module Organization Pattern

Models should be defined in the app's `models.rs` file and re-exported from the app entry point:

```rust
// src/apps/polls.rs — App entry point
pub mod models;
pub mod views;
pub mod serializers;
pub mod urls;

#[cfg(test)]
mod tests;

// Re-export models for convenient access
pub use models::{Question, Choice};
```

```rust
// src/apps/polls/models.rs — Model definitions
use reinhardt::db::prelude::*;
use chrono::{DateTime, Utc};

#[model(table_name = "questions", app_label = "polls")]
#[derive(Debug, Clone)]
pub struct Question {
    // ... fields
}

#[model(table_name = "choices", app_label = "polls")]
#[derive(Debug, Clone)]
pub struct Choice {
    // ... fields
}
```

## Model Info Companion Struct (0.2.x)

In 0.2.x, every `#[model]` automatically generates a `{Model}Info` companion struct — a plain data carrier suitable for API DTOs, view layers, and tests. The macro provides bidirectional `From<Model>` / `From<ModelInfo>` conversions out of the box.

**Key behaviors:**

- **Opt-out:** Pass `info = false` to the model attribute: `#[model(info = false)]` to suppress Info struct generation entirely.
- **Field exclusion:** Annotate individual fields with `#[field(skip_info = true)]` to exclude sensitive data (e.g., password hashes) from the Info struct.
- **Serde derives:** Serde derives on the model are mirrored onto the Info struct.
- **Relationship handling:** Marker types (e.g., `ForeignKeyField<T>`, `ManyToManyField<A, B>`) are excluded from the Info struct. Plain `*_id` fields are included only when they are intentionally denormalized or external scalar fields; they must not stand in for a Reinhardt relationship.

```rust
// 0.2.x: Auto-generated UserInfo struct
#[model(app_label = "accounts")]
#[derive(Debug, Clone)]
pub struct User {
    #[field(primary_key = true)]
    pub id: i64,

    #[field(max_length = 150)]
    pub username: String,

    #[field(skip_info = true)]  // excluded from UserInfo
    pub password_hash: String,

    #[field(null = true)]
    pub email: Option<String>,
}
// The macro generates:
// pub struct UserInfo { pub id: i64, pub username: String, pub email: Option<String> }
// impl From<User> for UserInfo { ... }
// impl From<UserInfo> for User { ... } (requires defaults for skipped fields)
```

## Scoped Keys, Versions, and Ordering

Model-level uniqueness must include the owning scope whenever rows can repeat
across parents. For example, a content chunk key should include the project or
document identity, not only the relative path, sequence number, and content hash.

For versioned authoring models, keep the database state consistent with the
domain concept of "accepted" or "current":

- Accepting a new version must clear the previous accepted marker for the same target, or an equivalent unique constraint must enforce the invariant.
- Operation payloads such as split, merge, and retake candidates must be applied to the target graph, not merely marked accepted.
- Reorder commands must contain the exact sibling ID set once each. Reject partial lists, duplicate IDs, unknown IDs, and cross-parent IDs before updating positions.

## Custom Manager Attribute (rc.23+)

Opt a model into a user-supplied custom manager by passing `manager = <Path>` to the `#[model]` attribute (#3981). The macro emits a `HasCustomManager` impl that wires the model to the named `CustomManager` implementor; see `queryset-api.md` for the trait surface and veto hooks.

### Row-Level Access Control

```rust
use reinhardt::db::prelude::*;

pub struct DocumentAccessManager;

impl CustomManager<Document> for DocumentAccessManager {
    async fn before_save(&self, doc: &Document) -> Result<(), DbError> {
        ensure_current_user_can_edit(doc)?;
        Ok(())
    }

    async fn before_delete(&self, pk: &Uuid) -> Result<(), DbError> {
        ensure_current_user_can_delete(*pk).await?;
        Ok(())
    }
}

#[model(table_name = "documents", app_label = "docs", manager = DocumentAccessManager)]
#[derive(Debug, Clone)]
pub struct Document {
    #[field(primary_key = true)]
    pub id: Option<Uuid>,

    #[field(max_length = 200)]
    pub title: String,

    #[field]
    pub body: String,
}
```

### Default Tenant Filter

```rust
pub struct TenantScopedManager;

impl CustomManager<Project> for TenantScopedManager {
    async fn before_bulk_update(&self, models: &[Project]) -> Result<(), DbError> {
        // Reject cross-tenant bulk updates atomically.
        let tenant_partition = current_tenant_partition()?;
        if models.iter().any(|p| p.tenant_partition != tenant_partition) {
            return Err(DbError::PermissionDenied);
        }
        Ok(())
    }
}

#[model(table_name = "projects", app_label = "core", manager = TenantScopedManager)]
#[derive(Debug, Clone)]
pub struct Project {
    #[field(primary_key = true)]
    pub id: Option<Uuid>,

    // This denormalized routing key is not a model relationship.
    #[field]
    pub tenant_partition: Uuid,

    #[field(max_length = 200)]
    pub name: String,
}
```

`Project::objects()` continues to return the inherent `Manager<Project>` — the custom manager is the secondary, opt-in access path (#3981).
