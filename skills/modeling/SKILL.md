---
name: modeling
description: Use when defining database models, working with QuerySets, or managing migrations in reinhardt-web applications
versions: ["0.1.x", "0.2.x", "0.3.x", "0.4.x"]
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
4. For 0.4.x generated columns, use the typed `SchemaExpr` contract in
   `references/model-patterns.md` before choosing a raw SQL escape hatch
5. Define relations (ForeignKey, ManyToMany, OneToOne) if needed
6. Implement `pub use` re-exports in the module entry file

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
3. Use `SchemaExpr` for portable generated-column DDL; reserve `generated_sql`
   for trusted, backend-specific expression bodies
4. NEVER use raw SQL strings — except the explicit `generated_sql` escape hatch
   when a trusted backend-specific generated expression is necessary

### Migrations

1. Read `references/migration-guide.md` for the full workflow
2. Generate migration: `cargo run --bin manage makemigrations <app_label>`
3. Review the generated migration file (declarative `Operation` variants)
4. For generated-column changes, review preserved expression/storage metadata,
   replacement operations, and backend-specific execution before applying
5. Apply: `cargo run --bin manage migrate`
6. For custom operations (indexes, data migrations), write hand-written migration files

## Important Rules

- ALWAYS use `Model::objects()` for application-level CRUD
- Keep simple `Model::objects()` CRUD visible at the endpoint/server_fn call site; do not hide one `get`, `filter`, `all`, `create`, `update`, or `delete` behind a semantic helper/service name
- Use `reinhardt-query` ONLY for migrations and schema DDL, NOT for application queries
- Migration commands are in the project-specific `manage` binary, NOT in `reinhardt-admin`
- `reinhardt-admin` is only for: `startproject`, `startapp`, `plugin`, `fmt`
- Build application filters from generated model field helpers such as `<Model>::field_name().eq(value)` / `<Model>::field_project().eq(value)` instead of untyped `Filter::new(...)` calls
- There is NO `sqlmigrate` or `showmigrations` command
- Migration files use declarative `Operation` variants — there are NO `up`/`down` methods
- Migration names are auto-generated from detected changes (`--name` is optional)
- Field types map to Rust types (String, i32, i64, bool, Option<T>, DateTime<Utc>)
- Put `#[field(...)]` on every scalar model field, even when no options are required
- Use `#[rel(...)]` for model relationships; do not represent foreign keys as unmanaged scalar IDs unless the scalar is intentionally denormalized
- ALL model struct fields that can be NULL must use `Option<T>`
- **(0.4.x)** Prefer `generated = SchemaExpr::...` for generated columns. Use
  `generated_sql = "..."` only for trusted backend-specific expressions that
  cannot use the portable DDL-safe subset.
- **(0.4.x)** Generated columns require exactly one storage mode, cannot also
  use a default or auto-increment, and must not combine `generated` with
  `generated_sql`.
- **(0.4.x)** Treat generated fields as read-only: they may be selected or
  filtered, but must not appear in create/update inputs or partial-update
  assignments.
- Scope unique or stable keys by their owning record (project, tenant, document, etc.) when data can be duplicated across parents
- For ordered sibling records, validate reorder inputs contain every sibling exactly once before updating positions
- For versioned models, enforce one accepted/current version per target by clearing the previous accepted marker or using an equivalent invariant
- In 0.3.x, generated `{Model}Info` relation fields expose relation-shaped payloads: `RelationInfo<T>` for one-to-one / foreign-key fields and `ManyToManyInfo<Source, Target>` for many-to-many fields
- Review serializers, API DTOs, browser tests, and fixtures that expected flattened `*_id` scalar fields after regenerating 0.3.x model info
- Use `QuerySet::update_fields([...])` for atomic conditional partial updates; empty assignments and predicate-less partial updates are rejected at the API boundary
- Regenerate and review migrations after relation metadata, field renames, or unique constraints change; 0.3.x migration generation is stricter about `RenameColumn` and replay drift

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
9. Read `reinhardt/crates/reinhardt-query/src/types/schema_expr.rs` for the
   current portable generated-column expression surface
