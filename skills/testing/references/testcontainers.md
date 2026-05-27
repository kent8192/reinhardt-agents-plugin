# TestContainers Reference

## Prerequisites

- **Docker Desktop** must be installed and running (NOT Podman)
- `DOCKER_HOST` must point to the Docker socket (not Podman socket)
- `.testcontainers.properties` in the project root forces Docker usage (already configured in reinhardt projects)

Verify Docker is available:

```bash
docker info | head -5
```

## Using `reinhardt-test` Fixtures (Recommended)

The `reinhardt-test` crate provides pre-built TestContainers fixtures. Use these instead of manually constructing `GenericImage` containers.

### PostgreSQL Container Fixture

```rust
use reinhardt_test::fixtures::postgres_container;
use rstest::*;
use serial_test::serial;

#[rstest]
#[serial(db)]
#[tokio::test]
async fn test_with_postgres(
    #[future] postgres_container: (
        ContainerAsync<GenericImage>,
        Arc<PgPool>,
        u16,
        String,
    ),
) {
    // Arrange — fixture provides container, pool, port, and connection URL
    let (_container, pool, _port, _url) = postgres_container.await;

    // Act — use pool for database operations
    sqlx::query("SELECT 1")
        .execute(pool.as_ref())
        .await
        .unwrap();
}
```

The `postgres_container` fixture returns a tuple of:
- `ContainerAsync<GenericImage>` — container handle (keep alive for test duration)
- `Arc<PgPool>` — connection pool with retry and timeout configuration
- `u16` — mapped host port
- `String` — database connection URL

### Shared PostgreSQL (Fast Isolation)

For faster test execution, use the shared database pattern with template databases:

```rust
use reinhardt_test::fixtures::shared_db_pool;
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_with_shared_db(
    #[future] shared_db_pool: (PgPool, String),
) {
    // Arrange — each test gets an isolated database cloned from template (~10-40ms)
    let (pool, _url) = shared_db_pool.await;

    // Act
    let result = sqlx::query("SELECT 1 as value")
        .fetch_one(&pool)
        .await
        .unwrap();

    // Assert
    assert_eq!(result.get::<i32, _>("value"), 1);
}
```

### Redis Container Fixture

```rust
use reinhardt_test::fixtures::redis_container;
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_with_redis(
    #[future] redis_container: (ContainerAsync<GenericImage>, String),
) {
    // Arrange
    let (_container, url) = redis_container.await;
    let client = redis::Client::open(url.as_str()).unwrap();
    let mut conn = client.get_multiplexed_async_connection().await.unwrap();

    // Act
    redis::cmd("SET")
        .arg("key")
        .arg("value")
        .exec_async(&mut conn)
        .await
        .unwrap();
    let result: String = redis::cmd("GET")
        .arg("key")
        .query_async(&mut conn)
        .await
        .unwrap();

    // Assert
    assert_eq!(result, "value");
}
```

## Table Setup via Migrations (Recommended)

Use the migration system to set up test tables. This ensures your test schema matches production.

### Using `PostgresTableCreator` Fixture

```rust
use reinhardt_test::fixtures::postgres_table_creator;
use reinhardt_testkit::fixtures::schema::{ColumnDefinition, FieldType, Operation};
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_with_table(
    #[future] postgres_table_creator: PostgresTableCreator,
) {
    // Arrange — define schema using Operations API
    let mut creator = postgres_table_creator.await;
    let schema = vec![
        Operation::CreateTable {
            name: "users".to_string(),
            columns: vec![
                ColumnDefinition::new("id", FieldType::Serial).primary_key(),
                ColumnDefinition::new("username", FieldType::Varchar(150)),
                ColumnDefinition::new("email", FieldType::Varchar(254)),
                ColumnDefinition::new("is_active", FieldType::Boolean),
            ],
            constraints: vec![],
            without_rowid: None,
            interleave_in_parent: None,
            partition: None,
        },
    ];
    creator.apply(schema).await.unwrap();
    let pool = creator.pool();

    // Act — insert and query data
    sqlx::query("INSERT INTO users (username, email, is_active) VALUES ($1, $2, $3)")
        .bind("testuser")
        .bind("test@example.com")
        .bind(true)
        .execute(pool)
        .await
        .unwrap();

    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users")
        .fetch_one(pool)
        .await
        .unwrap();

    // Assert
    assert_eq!(count.0, 1);
}
```

### Using `AdminTableCreator` (Admin Panel Tests)

Combines `PostgresTableCreator` with `AdminDatabase` for admin panel integration tests:

```rust
use reinhardt_test::fixtures::admin_migrations::AdminTableCreator;
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_admin_operations(
    #[future] admin_table_creator: AdminTableCreator,
) {
    // Arrange
    let mut creator = admin_table_creator.await;
    creator.apply(schema).await.unwrap();
    let admin_db = creator.admin_db();

    // Act — use admin_db for admin panel operations
    let models = admin_db.list_registered_models();

    // Assert
    assert!(!models.is_empty());
}
```

### Using Migration Executor (Real Migrations)

For testing actual migration files:

```rust
use reinhardt_test::fixtures::migrations::*;
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_migration_execution(
    #[future] postgres_container: (ContainerAsync<GenericImage>, Arc<PgPool>, u16, String),
) {
    let (_container, pool, _port, _url) = postgres_container.await;

    // Act — run migrations against test database
    let executor = DatabaseMigrationExecutor::new(pool.as_ref());
    executor.migrate_app("user").await.unwrap();

    // Assert — verify tables exist after migration
    let tables = executor.list_tables().await.unwrap();
    assert!(tables.contains(&"user_users".to_string()));
}
```

## Reinhardt Component Integration Tests

Tests should exercise reinhardt components, not just raw SQL:

### ORM Integration Test

```rust
use reinhardt_test::prelude::*;
use reinhardt_test::impl_test_model;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
struct User {
    id: Uuid,
    username: String,
    email: String,
    is_active: bool,
}

impl_test_model!(User, Uuid, "users", "auth", non_option_pk);

#[rstest]
#[serial(db)]
#[tokio::test]
async fn test_orm_query(
    #[future] postgres_table_creator: PostgresTableCreator,
) {
    // Arrange
    let mut creator = postgres_table_creator.await;
    creator.apply(user_schema()).await.unwrap();
    let pool = creator.pool();

    // Seed test data
    sqlx::query("INSERT INTO users (id, username, email, is_active) VALUES ($1, $2, $3, $4)")
        .bind(Uuid::new_v4())
        .bind("testuser")
        .bind("test@example.com")
        .bind(true)
        .execute(pool)
        .await
        .unwrap();

    // Act — use reinhardt ORM
    let found = User::objects()
        .filter(User::username.eq("testuser"))
        .get(pool)
        .await
        .unwrap();

    // Assert
    assert_eq!(found.username, "testuser");
    assert!(found.is_active);
}
```

### API View Integration Test

```rust
use reinhardt_test::prelude::*;
use reinhardt_test::fixtures::auth::*;

#[rstest]
#[tokio::test]
async fn test_user_api_view(
    api_client: APIClient,
    test_user: TestUser,
) {
    // Arrange
    let user_json = json!({
        "id": test_user.id.to_string(),
        "username": test_user.username,
    });
    api_client.force_authenticate(Some(user_json)).await;

    // Act
    let response = api_client.get("/api/users/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
    let users: Vec<UserResponse> = response.json().unwrap();
    assert!(!users.is_empty());
}
```

### Authentication Integration Test

```rust
use reinhardt_test::fixtures::auth::*;

#[rstest]
#[tokio::test]
async fn test_jwt_authentication(
    api_client: APIClient,
    jwt_auth: JwtAuth,
    test_user: TestUser,
) {
    // Arrange — generate JWT token using fixture
    let token = jwt_auth.generate_token(&test_user.username).unwrap();
    api_client
        .set_header("Authorization", &format!("Bearer {}", token))
        .await
        .unwrap();

    // Act
    let response = api_client.get("/api/protected/").await.unwrap();

    // Assert
    assert_eq!(response.status(), StatusCode::OK);
}
```

## Environment Configuration

Pool configuration can be tuned via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TEST_MAX_CONNECTIONS` | 5 | Maximum pool connections |
| `TEST_ACQUIRE_TIMEOUT_SECS` | 60 | Connection acquire timeout |
| `REDIS_CLUSTER_BASE_PORT` | 17000 | Base port for Redis cluster tests |

## Cargo.toml Dev-Dependencies

```toml
[dev-dependencies]
reinhardt = { version = "0.1.2", features = ["test", "testcontainers"] }  # For 0.2.x: "0.2.0-rc.2"
rstest = "0.23"
serial_test = "3"
tokio = { version = "1", features = ["full"] }
```

**Note:** `reinhardt-test` re-exports `testcontainers` types. You do NOT need to add `testcontainers` or `sqlx` as direct dev-dependencies unless you need features beyond what `reinhardt-test` provides.

## Best Practices

- **Use `reinhardt-test` fixtures** (`postgres_container`, `shared_db_pool`, `redis_container`) instead of manually constructing containers
- **Use `#[serial(db)]`** when tests share a database or modify global state
- **Hold the container handle** — dropping it stops the container
- **Use `shared_db_pool`** for faster test suites — each test gets an isolated database cloned from a template (~10-40ms per clone vs seconds for a new container)
- **Use migrations** to set up test schemas when possible, ensuring test and production schemas stay in sync
- **Use `PostgresTableCreator`** with the Operations API for ad-hoc table creation in tests
- **Clean up test data** between tests or use separate containers per test for isolation
- **Never hardcode ports** — the fixtures handle dynamic port assignment automatically
