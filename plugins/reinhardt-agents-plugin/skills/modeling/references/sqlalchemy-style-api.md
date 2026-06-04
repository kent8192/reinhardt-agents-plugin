# Reinhardt SQLAlchemy-Style API Reference

Reinhardt provides an alternative SQLAlchemy-inspired API alongside the Django-style `Model::objects()` API. This includes:

1. **`SelectQuery<T>`** — Fluent query builder (`select()`, `where_clause()`, `join()`)
2. **`Session`** — Unit of work with identity map (`add()`, `flush()`, `commit()`)

## When to Use Which API

| API | Style | Best For |
|-----|-------|----------|
| `Model::objects()` | Django | Standard CRUD, most application code |
| `SelectQuery<T>` | SQLAlchemy | Complex joins, type-safe queries, multi-table operations |
| `Session` | SQLAlchemy | Transaction-heavy workflows, identity map, batch operations |
| `reinhardt-query` | Low-level | Migrations, schema DDL, raw SQL generation |

---

## SelectQuery (SQLAlchemy-Style Query Builder)

`SelectQuery<T>` implements SQLAlchemy's `select()`/`where()`/`join()` query construction pattern.

**Module:** `reinhardt_db::orm::sqlalchemy_query`

### Basic Usage

```rust
use reinhardt_db::orm::sqlalchemy_query::{select, column, Column, SelectQuery};

// Create a SELECT query (mirrors SQLAlchemy's select())
let query = select::<User>();

// With columns
let query = select::<User>()
    .columns(vec![column("id"), column("name"), column("email")]);

// Column with table qualifier
let query = select::<User>()
    .columns(vec![
        Column::new("id").with_table("users"),
        Column::new("name").with_table("users"),
    ]);
```

### Filtering (WHERE)

```rust
use reinhardt_db::orm::Q;

// Single WHERE clause (mirrors SQLAlchemy's .where())
let query = select::<User>()
    .where_clause(Q::new("is_active", "=", "true"));

// Multiple WHERE clauses (AND combined)
let query = select::<User>()
    .where_clause(Q::new("is_active", "=", "true"))
    .where_clause(Q::new("age", ">=", "18"));

// Multiple at once
let query = select::<User>()
    .where_all(vec![
        Q::new("is_active", "=", "true"),
        Q::new("role", "=", "admin"),
    ]);

// Dict-style filter (mirrors SQLAlchemy's .filter_by())
let query = select::<User>()
    .filter_by(vec![("name", "Alice"), ("role", "admin")]);
```

### Joins

```rust
// String-based JOIN
let query = select::<User>()
    .join("posts", "users.id = posts.user_id")
    .join("comments", "users.id = comments.user_id");

// LEFT JOIN (mirrors SQLAlchemy's .outerjoin())
let query = select::<User>()
    .left_join("profiles", "users.id = profiles.user_id");

// Type-safe JOIN using TypedJoin (compile-time field validation)
use reinhardt_db::orm::typed_join::TypedJoin;

let query = select::<User>()
    .join_on(TypedJoin::on(User::id(), Post::user_id()))
    .join_on(TypedJoin::left_on(User::id(), Comment::user_id()));
```

**Type safety:** `TypedJoin` enforces at compile time that both join fields have the same type and that field names exist on their respective models.

### Ordering, Grouping, Pagination

```rust
// ORDER BY (mirrors SQLAlchemy's .order_by())
let query = select::<User>()
    .order_by("name", true)    // ASC
    .order_by("age", false);   // DESC

// Type-safe ORDER BY using Field
let query = select::<User>()
    .order_by_field(User::email(), true)   // ASC
    .order_by_field(User::age(), false);   // DESC

// GROUP BY
let query = select::<User>()
    .group_by(vec!["department"]);

// HAVING
let query = select::<User>()
    .group_by(vec!["department"])
    .having(Q::new("count", ">", "5"));

// LIMIT / OFFSET
let query = select::<User>()
    .limit(10)
    .offset(20);

// DISTINCT
let query = select::<User>()
    .distinct();
```

### Special Queries

```rust
// Select specific entities/columns (mirrors SQLAlchemy's .with_entities())
let query = select::<User>()
    .with_entities(vec![column("id"), column("name")]);

// COUNT query
let query = select::<User>()
    .where_clause(Q::new("is_active", "=", "true"))
    .count_query();
```

### SelectQuery Method Reference

| Method | SQLAlchemy Equivalent | Description |
|--------|----------------------|-------------|
| `select::<T>()` | `select(Model)` | Create query for model |
| `.columns(Vec<Column>)` | `select(col1, col2)` | Set columns |
| `.where_clause(Q)` | `.where()` | Add WHERE condition |
| `.where_all(Vec<Q>)` | `.where(and_())` | Multiple WHERE (AND) |
| `.filter_by(Vec<(&str, &str)>)` | `.filter_by()` | Dict-style filter |
| `.join(table, on)` | `.join()` | INNER JOIN |
| `.left_join(table, on)` | `.outerjoin()` | LEFT JOIN |
| `.join_on(TypedJoin)` | `.join()` (typed) | Type-safe JOIN |
| `.order_by(col, asc)` | `.order_by()` | ORDER BY |
| `.order_by_field(Field, asc)` | `.order_by()` (typed) | Type-safe ORDER BY |
| `.group_by(Vec<&str>)` | `.group_by()` | GROUP BY |
| `.having(Q)` | `.having()` | HAVING clause |
| `.limit(usize)` | `.limit()` | LIMIT |
| `.offset(usize)` | `.offset()` | OFFSET |
| `.distinct()` | `.distinct()` | DISTINCT |
| `.with_entities(Vec<Column>)` | `.with_entities()` | Select specific columns |
| `.count_query()` | `func.count()` | COUNT query |

---

## Session (Unit of Work Pattern)

`Session` provides SQLAlchemy-style session management with identity map, dirty tracking, and transaction support.

**Module:** `reinhardt_db::orm::session`

### Creating a Session

```rust
use reinhardt_db::orm::session::Session;
use reinhardt_db::orm::query_types::DbBackend;
use sqlx::AnyPool;
use std::sync::Arc;

let pool = AnyPool::connect("postgres://localhost/mydb").await?;
let mut session = Session::new(Arc::new(pool), DbBackend::Postgres).await?;
```

### Adding Objects (INSERT/UPDATE)

```rust
// Add new object (no PK -> INSERT on flush)
let new_user = User { id: None, name: "Alice".to_string() };
session.add(new_user).await?;

// Add existing object (has PK -> UPDATE on flush)
let user = User { id: Some(1), name: "Alice Updated".to_string() };
session.add(user).await?;
```

### Querying

```rust
// Get by primary key (checks identity map first, then DB)
let user: Option<User> = session.get(1).await?;

// List all objects of a type
let users: Vec<User> = session.list_all().await?;

// Create ORM query
let query = session.query::<User>();
```

### Deleting

```rust
// Mark object for deletion
let user = User { id: Some(1), name: "Alice".to_string() };
session.delete(user).await?;
```

### Flushing and Committing

```rust
// Flush: execute all pending INSERT/UPDATE/DELETE operations
session.flush().await?;

// Commit: flush + commit transaction
session.commit().await?;

// Rollback: discard all pending changes
session.rollback().await?;
```

### Transaction Management

```rust
// Begin explicit transaction
session.begin().await?;

// ... perform operations ...
session.add(user).await?;
session.delete(old_user).await?;

// Flush and commit
session.flush().await?;
session.commit().await?;

// Or rollback on error
// session.rollback().await?;
```

### Identity Map

The Session maintains an identity map that:

- **Caches loaded objects** by type + primary key
- **Tracks dirty objects** for automatic flush
- **Prevents duplicate loads** — `get()` checks the map before querying the DB
- **Tracks deletions** separately from updates

### Session Method Reference

| Method | SQLAlchemy Equivalent | Description |
|--------|----------------------|-------------|
| `Session::new(pool, backend)` | `Session()` | Create session |
| `.add(obj)` | `session.add()` | Track object for INSERT/UPDATE |
| `.get::<T>(pk)` | `session.get()` | Get by PK (identity map first) |
| `.list_all::<T>()` | `session.query().all()` | Get all objects of type |
| `.query::<T>()` | `session.query()` | Create query |
| `.delete(obj)` | `session.delete()` | Mark for deletion |
| `.flush()` | `session.flush()` | Execute pending ops |
| `.commit()` | `session.commit()` | Flush + commit |
| `.rollback()` | `session.rollback()` | Rollback transaction |
| `.begin()` | `session.begin()` | Begin transaction |
| `.close()` | `session.close()` | Close session |

### SessionError Types

| Variant | Description |
|---------|-------------|
| `DatabaseError(String)` | Database operation failed |
| `ObjectNotFound(String)` | Object not in session |
| `TransactionError(String)` | Transaction operation failed |
| `SerializationError(String)` | JSON serialization/deserialization failed |
| `InvalidState(String)` | Session in invalid state (e.g., closed) |
| `FlushError(String)` | Flush operation failed |

---

## Choosing Between APIs

### Use `Model::objects()` (Django-style) when

- Standard CRUD operations
- Simple filtering and ordering
- Relationship loading (`select_related`, `prefetch_related`)
- PostgreSQL-specific features (JSONB, arrays, full-text search)
- Most day-to-day application code

### Use `SelectQuery` (SQLAlchemy-style) when

- Complex multi-table JOINs with type safety
- Need compile-time validation of join fields
- Building queries programmatically with unknown structure
- Porting SQLAlchemy code to Reinhardt

### Use `Session` (SQLAlchemy-style) when

- Transaction-heavy workflows (multiple related operations)
- Need identity map for object caching within a request
- Batch operations that should be flushed together
- Porting SQLAlchemy unit-of-work patterns

### Use `reinhardt-query` (low-level) when

- Writing migrations (DDL operations)
- Schema management
- Need database-specific SQL generation
- Raw query builder access

## Dynamic References

For the latest API:

1. Read `reinhardt/crates/reinhardt-db/src/orm/sqlalchemy_query.rs` for `SelectQuery` implementation
2. Read `reinhardt/crates/reinhardt-db/src/orm/session.rs` for `Session` implementation
3. Read `reinhardt/crates/reinhardt-db/src/orm/typed_join.rs` for type-safe JOIN builder
4. Read `reinhardt/crates/reinhardt-db/src/orm/async_query.rs` for async query wrapper
