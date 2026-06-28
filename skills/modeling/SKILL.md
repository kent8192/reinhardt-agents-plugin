---
name: modeling
description: Use when defining database models, working with QuerySets, or managing migrations in reinhardt-web applications
versions: ["0.1.x", "0.2.0"]
---

# Reinhardt Data Modeling

Guide developers through model definition, database operations, and migration management using reinhardt-db and reinhardt-query.

## When to Use

- User defines or modifies database models
- User works with QuerySet operations or ORM queries
- User generates or applies migrations
- User asks about SQLAlchemy-style queries or sessions
- User mentions: "model", "table", "migration", "QuerySet", "field", "relation", "ForeignKey", "ManyToMany", "database", "schema", "objects", "Manager", "Session", "select", "migrate", "makemigrations"

## Workflow

### Defining a Model

1. Read `references/model-patterns.md` for field types and relation patterns
2. Guide model struct definition with `#[model]` attribute
3. Choose appropriate field types and constraints
4. Define relations (ForeignKey, ManyToMany, OneToOne) if needed
5. Implement `pub use` re-exports in the module entry file

### ORM Operations (Django-style)

1. Read `references/queryset-api.md` for the `Model::objects()` API
2. Use `Model::objects()` for application-level CRUD (recommended)
3. Chain methods: `filter()`, `order_by()`, `limit()`, `select_related()`, etc.
4. Execute with `.all().await`, `.get().await`, `.count().await`, `.exists().await`

### SQLAlchemy-Style Operations

1. Read `references/sqlalchemy-style-api.md` for `SelectQuery` and `Session`
2. Use `select::<T>()` for complex multi-table JOINs with type safety
3. Use `Session` for transaction-heavy workflows with identity map

### Low-Level Query Building

1. Read `references/queryset-api.md` (Low-Level Query Builder section)
2. Use `reinhardt-query` for schema DDL, migrations, and raw query generation
3. NEVER use raw SQL strings — always use `reinhardt_query::Query` builders

### Migrations

1. Read `references/migration-guide.md` for the full workflow
2. Generate migration: `cargo run --bin manage makemigrations <app_label>`
3. Review the generated migration file (declarative `Operation` variants)
4. Apply: `cargo run --bin manage migrate`
5. For custom operations (indexes, data migrations), write hand-written migration files

## Important Rules

- ALWAYS use `Model::objects()` for application-level CRUD
- Use `reinhardt-query` ONLY for migrations and schema DDL, NOT for application queries
- Migration commands are in the project-specific `manage` binary, NOT in `reinhardt-admin`
- `reinhardt-admin` is only for: `startproject`, `startapp`, `plugin`, `fmt`
- There is NO `sqlmigrate` or `showmigrations` command
- Migration files use declarative `Operation` variants — there are NO `up`/`down` methods
- Migration names are auto-generated from detected changes (`--name` is optional)
- Field types map to Rust types (String, i32, i64, bool, Option<T>, DateTime<Utc>)
- ALL model struct fields that can be NULL must use `Option<T>`

## Cross-Domain References

For testing models with TestContainers, read `references/migration-guide.md` (Test with TestContainers section) and `../testing/references/testcontainers.md`.

## Dynamic References

For the latest model API and field types:

1. Read `reinhardt/crates/reinhardt-db/src/orm/model.rs` for Model trait and `objects()`
2. Read `reinhardt/crates/reinhardt-db/src/orm/manager.rs` for Manager API
3. Read `reinhardt/crates/reinhardt-db/src/orm/query.rs` for QuerySet implementation
4. Read `reinhardt/crates/reinhardt-db/src/orm/sqlalchemy_query.rs` for SelectQuery API
5. Read `reinhardt/crates/reinhardt-db/src/orm/session.rs` for Session API
6. Read `reinhardt/crates/reinhardt-db/src/migrations/operations.rs` for Operation variants
7. Read `reinhardt/crates/reinhardt-commands/src/cli.rs` for CLI command definitions
8. Grep for `#[model]` usage in `reinhardt/tests/` for real examples
