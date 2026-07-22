# Reinhardt Migration Guide

## Migration Workflow

The standard workflow for applying model changes to the database:

```text
Define/Modify Models -> Generate Migration -> Review -> Apply -> Verify
```

### Step 1: Define or Modify Models

Edit your model structs in `src/apps/<name>/models.rs`. See `model-patterns.md` for field types, relations, and attribute options.

### Step 2: Generate Migration

After modifying models, generate a migration file:

```bash
cargo run --bin manage makemigrations <app_label>
```

This compares the current model definitions against the last migration state and produces a new migration file in `migrations/<app_name>/`. The migration name (`--name`) is **automatically generated** from the detected changes (e.g., `add_field_bio_to_user`, `create_model_post`). You only need to specify `--name` when you want a custom name.

**Options:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview without writing files |
| `-n, --name <NAME>` | Custom migration name |
| `--check` | Check if migrations are missing (CI use) |
| `--empty` | Create empty migration (for hand-written operations) |
| `--merge` | Fix migration conflicts (create merge migration) |
| `--force-empty-state` | Force empty state when DB/TestContainers unavailable (dangerous) |
| `--migration-dir <PATH>` | Migration directory (default: `./migrations`) |

Migration files are named with a sequential number and description:

```text
migrations/
+-- polls/
    +-- 0001_initial.rs
    +-- 0002_add_choice_votes_default.rs
    +-- 0003_add_question_is_published.rs
```

### Step 3: Review the Generated Migration

**Always review migrations before applying.** Check that:

- The SQL operations match your intended changes
- No unintended columns are added, dropped, or modified
- Foreign key constraints and indexes are correct
- Default values are appropriate
- The migration is reversible (has both `up` and `down` operations)

> **Note:** There is no `sqlmigrate` command. To preview SQL, use `--plan` flag on the `migrate` command or review the generated migration file directly.

### Generated Columns (0.4.x)

The typed generated-column contract originated in
[PR #5586](https://github.com/kent8192/reinhardt-web/pull/5586) and its final
execution behavior was delivered in the merged cherry-pick
[PR #5615](https://github.com/kent8192/reinhardt-web/pull/5615).

- Generate a fresh migration after adding or changing a generated expression or
  its storage mode. Typed `SchemaExpr` tokens and explicit `generated_sql`
  values are preserved in migration state; do not replace that metadata with
  hand-written raw SQL.
- Review generated-column changes as replacements rather than assuming an
  in-place `ALTER`. The autodetector drops and recreates changed generated
  columns, keeps dependency order for generated-column chains, and repairs
  affected indexes and constraints.
- Test the generated migration on every target backend. SQLite cannot add a
  stored generated column with direct `ALTER TABLE ADD COLUMN`; the migration
  executor routes that case through table recreation, preserving columns,
  constraints, and indexes.
- A direct `ColumnDefinition { ... }` literal now needs `generated: None` for
  an ordinary column. Prefer constructors where possible so new metadata is
  initialized safely.

### Step 4: Apply the Migration

```bash
# Apply all pending migrations
cargo run --bin manage migrate

# Apply migrations for a specific app
cargo run --bin manage migrate <app_label>

# Apply up to a specific migration
cargo run --bin manage migrate <app_label> <migration_name>

# Preview migration plan without applying
cargo run --bin manage migrate --plan

# Mark as applied without running (for existing databases)
cargo run --bin manage migrate --fake

# Fake only the initial migration
cargo run --bin manage migrate --fake-initial
```

### Step 5: Verify

Run tests to verify models work correctly:

```bash
cargo nextest run --workspace --all-features
```

> **Note:** There is no `showmigrations` command. Check migration state by reviewing the `migrations/` directory or inspecting the `reinhardt_migrations` table in the database.

## CLI Summary

Reinhardt has **two CLI tools** with different purposes:

| Tool | Invocation | Commands |
|------|-----------|----------|
| **manage** (project-specific) | `cargo run --bin manage <command>` | `makemigrations`, `migrate`, `runserver`, `shell`, `check`, `collectstatic`, etc. |
| **reinhardt-admin** (global) | `reinhardt-admin <command>` | `startproject`, `startapp`, `plugin`, `fmt`, `fmt-all` |

Migration commands are **only available in the project-specific `manage` binary**, not in `reinhardt-admin`.

## Rollback Procedure

To revert a migration, migrate to the previous migration number:

```bash
# Roll back the last migration for an app
cargo run --bin manage migrate <app_label> <previous_migration_name>

# Roll back all migrations for an app (use with caution)
cargo run --bin manage migrate <app_label> zero
```

**Rules for rollback:**

- Only roll back migrations that have not been deployed to production
- Ensure the `down` method is implemented in the migration
- After rollback, update or remove the corresponding model changes
- Run tests after rollback to confirm consistency

## Migration File Format

Migration files are Rust source files that export a `pub fn migration() -> Migration` function. There are **no `up`/`down` methods** — operations are declarative, and rollback is auto-generated from the `Operation` variants.

### Auto-Generated Example

`makemigrations` generates files like this:

```rust
use reinhardt::db::migrations::FieldType;
use reinhardt::db::migrations::prelude::*;

pub fn migration() -> Migration {
    Migration {
        app_label: "auth".to_string(),
        name: "0001_initial".to_string(),
        operations: vec![Operation::CreateTable {
            name: "auth_users".to_string(),
            columns: vec![
                ColumnDefinition {
                    name: "id".to_string(),
                    type_definition: FieldType::Uuid,
                    not_null: true,
                    unique: false,
                    primary_key: true,
                    auto_increment: false,
                    default: None,
                    generated: None,
                },
                ColumnDefinition {
                    name: "username".to_string(),
                    type_definition: FieldType::VarChar(150),
                    not_null: true,
                    unique: true,
                    primary_key: false,
                    auto_increment: false,
                    default: None,
                    generated: None,
                },
                // ... more columns
            ],
            constraints: vec![Constraint::Unique {
                name: "auth_user_username_uniq".to_string(),
                columns: vec!["username".to_string()],
            }],
            without_rowid: None,
            interleave_in_parent: None,
            partition: None,
        }],
        dependencies: vec![],
        atomic: true,
        replaces: vec![],
        initial: Some(true),
        state_only: false,
        database_only: false,
        swappable_dependencies: vec![],
        optional_dependencies: vec![],
    }
}
```

### Migration Struct Fields

| Field | Type | Description |
|-------|------|-------------|
| `app_label` | `String` | App this migration belongs to |
| `name` | `String` | Migration name (e.g., `"0001_initial"`) |
| `operations` | `Vec<Operation>` | Declarative operations to apply |
| `dependencies` | `Vec<(String, String)>` | `(app_label, migration_name)` pairs that must run first |
| `atomic` | `bool` | Wrap in a transaction |
| `initial` | `Option<bool>` | `Some(true)` for initial migration, `None` to auto-infer |
| `replaces` | `Vec<(String, String)>` | Squashed migration support |
| `state_only` | `bool` | Update ProjectState without executing DB operations |
| `database_only` | `bool` | Execute DB operations without updating ProjectState |

### Migration Name Auto-Detection

The `--name` flag is optional. `makemigrations` automatically generates descriptive names from the operations:

| Operations | Generated Name |
|-----------|----------------|
| Single `CreateTable` with no deps | `initial` |
| `AddColumn { column: "bio", table: "users" }` | `add_bio_to_users` |
| `AddConstraint` on email | `add_email_unique` |
| Multiple operations | `{frag1}_{frag2}` (max 52 chars, truncated with `_and_more`) |
| No fragments extractable | `auto_{timestamp}` |

### Operation Variants

| Operation | Description |
|-----------|-------------|
| `CreateTable { name, columns, constraints, ... }` | Create a new table |
| `DropTable { name }` | Drop a table |
| `AddColumn { table, column, ... }` | Add a column to existing table |
| `DropColumn { table, column }` | Drop a column |
| `AlterColumn { table, column, old_definition, new_definition }` | Modify a column |
| `RenameTable { old_name, new_name }` | Rename a table |
| `RenameColumn { table, old_name, new_name }` | Rename a column |
| `AddConstraint { table, constraint_sql }` | Add a constraint (raw SQL) |
| `DropConstraint { table, constraint_name }` | Drop a constraint |
| `CreateIndex { table, columns, unique, index_type, where_clause, ... }` | Create an index |
| `DropIndex { table, columns }` | Drop an index |
| `RunSQL { sql, reverse_sql }` | Execute raw SQL |
| `RunRust { code, reverse_code }` | Execute Rust code |
| `AlterUniqueTogether { table, unique_together }` | Alter unique together constraints |
| `AlterModelOptions { table, options }` | Alter model-level options |

## Hand-Written Migration Files

For schema changes that cannot be expressed through model definitions (custom indexes, partial indexes, data migrations), write a migration file manually.

### Step 1: Generate an Empty Migration

```bash
cargo run --bin manage makemigrations <app_label> --empty --name "add_partial_index_active_users"
```

### Step 2: Fill in the Operations

Edit the generated file to add your custom operations:

```rust
use reinhardt::db::migrations::prelude::*;
use reinhardt::db::migrations::operations::IndexType;

pub fn migration() -> Migration {
    Migration {
        app_label: "myapp".to_string(),
        name: "0004_add_partial_index_active_users".to_string(),
        operations: vec![Operation::CreateIndex {
            table: "users".to_string(),
            columns: vec!["email".to_string()],
            unique: false,
            index_type: Some(IndexType::BTree),
            where_clause: Some("is_active = true".to_string()),
            concurrently: true,
            expressions: None,
            mysql_options: None,
            operator_class: None,
        }],
        dependencies: vec![
            ("myapp".to_string(), "0003_previous_migration".to_string()),
        ],
        atomic: true,
        replaces: vec![],
        initial: Some(false),
        state_only: false,
        database_only: false,
        swappable_dependencies: vec![],
        optional_dependencies: vec![],
    }
}
```

### Data Migration Example (RunSQL)

```rust
pub fn migration() -> Migration {
    Migration {
        app_label: "myapp".to_string(),
        name: "0005_backfill_display_names".to_string(),
        operations: vec![Operation::RunSQL {
            sql: "UPDATE users SET display_name = username WHERE display_name IS NULL".to_string(),
            reverse_sql: Some("UPDATE users SET display_name = NULL WHERE display_name = username".to_string()),
        }],
        dependencies: vec![
            ("myapp".to_string(), "0004_add_partial_index_active_users".to_string()),
        ],
        atomic: true,
        replaces: vec![],
        initial: Some(false),
        state_only: false,
        database_only: false,
        swappable_dependencies: vec![],
        optional_dependencies: vec![],
    }
}
```

### Cross-App Dependencies Example

```rust
// deployments/0003_add_cluster_id_fk.rs
pub fn migration() -> Migration {
    Migration {
        app_label: "deployments".to_string(),
        name: "0003_add_cluster_id_fk".to_string(),
        operations: vec![Operation::AddConstraint {
            table: "deployments".to_string(),
            constraint_sql: "CONSTRAINT deployments_cluster_id_fk FOREIGN KEY (cluster_id) \
                REFERENCES clusters(id) ON DELETE RESTRICT ON UPDATE CASCADE".to_string(),
        }],
        dependencies: vec![
            ("deployments".to_string(), "0002_add_user_id".to_string()),
            ("clusters".to_string(), "0001_initial".to_string()),
        ],
        atomic: true,
        replaces: vec![],
        initial: Some(false),
        state_only: false,
        database_only: false,
        swappable_dependencies: vec![],
        optional_dependencies: vec![],
    }
}
```

### When to Use Hand-Written Migrations

| Scenario | Approach |
|----------|----------|
| Add/remove/modify columns | Auto-generated (`makemigrations`) |
| Add/remove relations | Auto-generated (`makemigrations`) |
| Partial indexes (PostgreSQL) | Hand-written (`CreateIndex` with `where_clause`) |
| Concurrent index creation | Hand-written (`CreateIndex` with `concurrently: true`) |
| Expression indexes | Hand-written (`CreateIndex` with `expressions`) |
| GIN/GiST indexes | Hand-written (`CreateIndex` with `index_type`) |
| Data migrations (backfill, transform) | Hand-written (`RunSQL` / `RunRust`) |
| Custom constraints or triggers | Hand-written (`AddConstraint` / `RunSQL`) |
| Cross-app foreign keys | Hand-written (with `dependencies`) |

## Test with TestContainers

Use `reinhardt-testkit` to run migrations against a real database in tests.

### Recommended: `postgres_with_migrations_from_dir()`

The recommended pattern loads migration files from a directory and applies them to a fresh PostgreSQL container:

```rust
use reinhardt_testkit::fixtures::testcontainers::postgres_with_migrations_from_dir;
use rstest::*;
use std::sync::Arc;
use testcontainers::ContainerAsync;
use testcontainers::GenericImage;
use reinhardt_db::DatabaseConnection;

#[fixture]
async fn test_app() -> (ContainerAsync<GenericImage>, Arc<DatabaseConnection>) {
    let migrations_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("migrations");

    postgres_with_migrations_from_dir(&migrations_dir)
        .await
        .expect("Failed to start PostgreSQL with migrations")
}

#[rstest]
#[tokio::test(flavor = "multi_thread")]
#[serial(database)]
async fn test_user_creation(
    #[future] test_app: (ContainerAsync<GenericImage>, Arc<DatabaseConnection>),
) {
    // Arrange
    let (_container, _conn) = test_app.await;

    // Act
    let user = User { id: None, name: "Alice".to_string() };
    let created = User::objects().create(&user).await.unwrap();

    // Assert
    assert!(created.id.is_some());
}
```

### Under the Hood

`postgres_with_migrations_from_dir()` performs these steps:

1. Starts a PostgreSQL container via TestContainers
2. Connects via `DatabaseConnection::connect_postgres()`
3. Loads migrations using `FilesystemSource`
4. Applies them via `DatabaseMigrationExecutor::apply_migrations()`
5. Initializes ORM global state via `reinitialize_database()`

### Alternative: Type-Safe Migration Provider

For compile-time migration management, use the generic variant:

```rust
use reinhardt_testkit::fixtures::testcontainers::postgres_with_migrations_from;

let (container, conn) = postgres_with_migrations_from::<MyAppMigrations>()
    .await
    .expect("Failed to apply migrations");
```

### E2E Test Pattern (with Test Server)

For full end-to-end tests including HTTP layer (pattern from reinhardt-cloud):

```rust
#[fixture]
async fn test_app() -> (
    ContainerAsync<GenericImage>,
    Arc<DatabaseConnection>,
    TestServerGuard,
    APIClient,
) {
    let migrations_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("migrations");

    let (container, conn) = postgres_with_migrations_from_dir(&migrations_dir)
        .await
        .expect("Failed to start PostgreSQL with migrations");

    let router = routes().into_server();
    let server = test_server_guard(router).await;
    let client = api_client_from_url(&server.url);

    (container, conn, server, client)
}
```

**Important:** Always hold the `ContainerAsync` reference in your test — dropping it stops the container.

## Best Practices

1. **One logical change per migration** — Do not combine unrelated schema changes in a single migration. This makes rollback safer and history clearer.

2. **Always review before applying** — Auto-generated migrations may include unintended changes, especially after renaming fields or restructuring models.

3. **Never edit applied migrations** — Once a migration has been applied to any environment (including other developers' machines), create a new migration instead of modifying the existing one.

4. **Always use reinhardt-query in hand-written migrations** — Never write raw SQL strings. Use `reinhardt_query::Query` builders for all DDL and DML operations. This ensures database portability and type safety.

5. **Include both `up` and `down`** — Every migration should be reversible. If a `down` operation is truly impossible (e.g., dropping a column with data), document this clearly in the migration and return an error from `down`.

6. **Coordinate migrations in teams** — When multiple developers create migrations for the same app simultaneously, merge conflicts in migration numbering should be resolved by renumbering and re-testing. Use `--merge` flag for automatic conflict resolution.

7. **Use `--check` in CI** — Run `cargo run --bin manage makemigrations --check` in CI to detect missing migrations.

## Migration Auto-Detection Improvements (rc.23-29)

Several autodetector and macro-side bugs that caused silent schema drift have been fixed in the rc.23-29 cycle.

### AddConstraint / DropConstraint emission (rc.23, #3998)

Prior to rc.23, `MigrationAutodetector::generate_operations()` tracked added/removed non-PK constraints (e.g., `unique_together`, `Check`, non-FK declarations) on existing tables in `DetectedChanges.added_constraints` / `removed_constraints` but never iterated over those vectors. As a result, those constraints were silently dropped from the emitted migration and the model / DB schema would diverge with no warning — most visibly, `unique_together` declarations on already-migrated models never reached the database, leaving downstream `409 Conflict` mappings on duplicate inserts as dead code.

From rc.23, `makemigrations` correctly emits `Operation::AddConstraint` / `Operation::DropConstraint` for every detected change. Composite primary keys (`constraint_type == "primary_key"` with `fields.len() >= 2`) are explicitly skipped because they are still emitted via the dedicated `CreateCompositePrimaryKey` path. **Action required:** if you added `unique_together` (or any non-PK constraint) on an existing table between rc.0 and rc.22, regenerate the migration with `makemigrations` on rc.23+ and review the resulting diff.

### Non-integer PK `auto_increment` regression (rc.29, #4380)

Between the rc.23 macro refactor and rc.28, the `#[model]` field-registration loop stamped `auto_increment = true` on every primary key regardless of its Rust type. Combined with the SQLite emitter, this produced `"id" UUID PRIMARY KEY AUTOINCREMENT`, which SQLite rejects with `AUTOINCREMENT is only allowed on an INTEGER PRIMARY KEY`. The most visible symptom was `cargo run --bin manage migrate` failing on a fresh SQLite database for any project using `reinhardt-auth` (whose `AuthPermission { id: Uuid }` and `Group { id: Uuid }` both have `#[field(primary_key = true)]`).

rc.29 fixes this in two layers: (1) the macro only emits `auto_increment = "true"` from the integer-PK branch, so `Uuid` / `String` / custom-type PKs no longer carry the flag through `FieldState.params` → `ProjectState::to_database_schema` → `ColumnDefinition`; (2) defense-in-depth in the SQLite emitter's `column_to_sql` only pushes `PRIMARY KEY AUTOINCREMENT` when the column type has been widened to `INTEGER` — non-integer PKs now emit plain `PRIMARY KEY`. Integer PKs (`BigInteger` / `Integer` / `SmallInteger`) are unaffected. **Action required on rc.29 upgrade:** if you generated migrations for a `Uuid`-PK model on rc.23-28 and never applied them, regenerate them; applied migrations need no change.

## Version Differences (0.2.x)

The following breaking changes affect the migration API in 0.2.x:

### `Operation::to_reverse_sql` returns `Vec<String>`

In 0.1.x, `Operation::to_reverse_sql` returned a single `String`. In 0.2.x, it returns `Vec<String>` to support multi-statement SQL reverse operations (e.g., a single `CreateIndex` operation that requires dropping multiple dependent objects before the index itself). Callers that pattern-match or store the return value must be updated accordingly.

### `DatabaseConnection::get_database_url_from_env_or_settings` removed

In 0.1.x, `DatabaseConnection::get_database_url_from_env_or_settings(base_dir)` accepted a base directory path and resolved both environment variables and settings files internally. In 0.2.x, this method is removed. Use `DatabaseConnection::database_url_from(settings, env_override)` instead, passing a pre-built `ProjectSettings` instance and an optional environment variable override. This change decouples URL resolution from filesystem discovery, making it easier to test and to use non-standard settings sources.

```rust
// 0.1.x
let url = DatabaseConnection::get_database_url_from_env_or_settings(base_dir)?;

// 0.2.x
let settings = ProjectSettings::from_dir(base_dir)?;
let url = DatabaseConnection::database_url_from(&settings, Some("DATABASE_URL"))?;
```

## Dynamic References

For the latest migration API:

1. Read `reinhardt/crates/reinhardt-commands/src/cli.rs` for CLI command definitions
2. Read `reinhardt/crates/reinhardt-db/src/migrations/` for migration executor internals
3. Read `reinhardt/crates/reinhardt-testkit/src/fixtures/testcontainers.rs` for test fixture API
