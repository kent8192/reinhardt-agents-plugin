# Reinhardt Feature Flags Reference

## Feature Presets

Reinhardt provides curated feature presets for common project types. Select a preset as a starting point, then add or remove individual features as needed.

| Preset | Description | Use Case |
|--------|-------------|----------|
| `minimal` | `core` + `di` + `server` | Lightweight microservice with no database or auth |
| `standard` | `minimal` + `database` + `db-postgres` + REST + auth + middleware + sessions + pages | **Default.** Typical full-stack backend with PostgreSQL |
| `api-only` | `minimal` + REST + auth + pages (no database preset) | Stateless API backend |
| `full` | All features enabled | Development, exploration, maximum capability |
| `graphql-server` | `minimal` + auth + graphql + database | GraphQL-focused API server |
| `websocket-server` | `minimal` + auth + websockets + cache | Real-time WebSocket server |
| `cli-tools` | database + migrations + tasks + mail | Background jobs and CLI tools |
| `test-utils` | test + testcontainers + database | Test infrastructure |

**Note:** `standard` is the **default** feature set. Use `default-features = false` in `Cargo.toml` to select a different preset or build a custom combination.

## Database Features

Enable exactly one database backend feature. Each activates `reinhardt-db` with the appropriate driver via the base `database` feature.

| Feature | Database | Notes |
|---------|----------|-------|
| `db-postgres` | PostgreSQL | Recommended for production. Best ecosystem support. |
| `db-mysql` | MySQL / MariaDB | Compatible with MySQL 8.0+ and MariaDB 10.6+. |
| `db-sqlite` | SQLite | File-based. Good for development, prototyping, and embedded use. |
| `db-cockroachdb` | CockroachDB | PostgreSQL wire-compatible. For distributed SQL workloads. |

The base `database` feature enables ORM, migrations, contenttypes, and query builder. Database backend features (`db-*`) automatically include `database`.

## Authentication Features

Auth features can be combined (e.g., JWT for API clients + Session for admin panel). All `auth-*` features automatically include the base `auth` feature.

| Feature | Description |
|---------|-------------|
| `auth` | Base authentication framework. Required by all `auth-*` features. |
| `auth-jwt` | JSON Web Token authentication. Stateless, suitable for APIs and mobile clients. |
| `auth-session` | Cookie-based session authentication. Requires a session backend. |
| `auth-oauth` | OAuth 2.0 / OpenID Connect provider integration. |
| `auth-token` | Persistent token-based authentication (database-backed API keys). |
| `argon2-hasher` | Argon2id password hashing (recommended). Adds `argon2` dependency. |

## Individual Component Features

### Core Infrastructure

| Feature | Description |
|---------|-------------|
| `core` | Core framework types, configuration, and application lifecycle. Always required. |
| `conf` | Settings configuration framework (TOML-based, environment profiles). |
| `di` | Dependency injection container (`InjectionContext`, `#[inject]`, `#[injectable]`). |
| `server` | HTTP server (hyper-based) with graceful shutdown and signal handling. |
| `middleware` | Middleware pipeline (logging, CORS, security headers, compression, sessions). |
| `commands` | Management command framework (`reinhardt-admin` CLI integration). |
| `messages` | Messages framework for flash messages and notifications. |

### API & Web

| Feature | Description |
|---------|-------------|
| `rest` | REST framework: serializers, parsers, renderers, content negotiation. |
| `api` | API views, ViewSets, routers, and pagination support. Includes `rest`. |
| `forms` | Form handling and validation (HTML form processing). |
| `graphql` | GraphQL schema, queries, mutations via `async-graphql` integration. |
| `pages` | Full-stack Pages support: WASM components, SSR, hydration, server functions. |
| `websockets` | WebSocket support for real-time communication. |
| `openapi` | OpenAPI schema generation from REST views. |
| `openapi-router` | OpenAPI router with automatic schema serving. Includes `openapi`. |
| `browsable-api` | Browsable API interface for REST endpoints (development tool). |
| `client-router` | WASM client/server unified routing for Pages applications. |
| `grpc` | gRPC support via tonic integration. |

### Data & Caching

| Feature | Description |
|---------|-------------|
| `database` | Base database support: ORM, migrations, contenttypes, query builder. |
| `cache` | Cache framework with pluggable backends. |
| `redis-backend` | Redis cache and session backend. Requires a running Redis instance. |
| `sessions` | Server-side session framework. Requires a session backend (DB, Redis, or cookie). |
| `session-redis` | Redis-backed session storage. Includes `sessions` and `middleware`. |

### Utilities

| Feature | Description |
|---------|-------------|
| `i18n` | Internationalization: message catalogs, locale detection, translation macros. |
| `mail` | Email sending framework with template support. |
| `admin` | Auto-generated admin interface for registered models. |
| `static-files` | Static file serving and collection (CSS, JS, images). |
| `storage` | File storage abstraction (local filesystem, S3, etc.). |
| `shortcuts` | Convenience functions for common patterns. |
| `tasks` | Background task execution framework. |
| `tasks-durable` | **0.4.x:** SQLite-backed durable jobs. Includes `tasks`; use when work must survive restarts or expose status, retries, and cancellation. |
| `dentdelion` | Plugin system for creating and consuming reinhardt plugins. |
| `deeplink` | Mobile deep linking support. |
| `dispatch` | Event dispatch system. |

### Durable Job Queues (0.4.x)

Enable `tasks-durable` when a background operation must survive process
restarts or provide a UI/API with queryable progress, retries, and
cancellation. It is additive to the ordinary `tasks` queue rather than a
replacement for short-lived work.

```toml
[dependencies]
reinhardt = { version = "0.4.0-alpha.1", features = ["tasks-durable"] }
```

For a server function or handler that receives the shared durable queue through
DI, enable both features:

```toml
reinhardt = { version = "0.4.0-alpha.1", features = ["tasks-durable", "di"] }
```

The facade feature is named `tasks-durable`. Applications that depend directly
on `reinhardt-tasks` instead use its `durable` feature, plus `di` when they need
`DurableQueueKey`. `SqliteDurableJobStore` requires a SQLite connection URL;
keep that durable-store setting separate from a generic application database URL
when the application uses PostgreSQL, MySQL, or CockroachDB.

### Pages-Specific

| Feature | Description |
|---------|-------------|
| `pages-web-sys-full` | Full `web-sys` bindings for Pages WASM applications. |
| `websockets-pages` | WebSocket integration with Pages components. |
| `uuid` | UUID type support for Pages. |
| `chrono` | Chrono datetime type support for Pages. |

### Fine-Grained Middleware

| Feature | Description |
|---------|-------------|
| `middleware-cors` | CORS middleware only. |
| `middleware-compression` | Response compression middleware only. |
| `middleware-security` | Security headers middleware only. |
| `middleware-rate-limit` | Rate limiting middleware only. |
| `middleware-auth-jwt` | JWT authentication middleware only. Includes `auth-jwt`. |

### Testing

| Feature | Description |
|---------|-------------|
| `test` | Test utilities: `ReinhardtTestCase`, request factories, assertion helpers. |
| `testcontainers` | TestContainers integration for database testing with real database instances. |
| `server-fn-test` | Server function testing utilities for Pages applications. |

## Cargo.toml Examples

### API-Only with PostgreSQL + JWT

```toml
[dependencies]
reinhardt = {
    version = "...",
    default-features = false,
    features = [
        "core",
        "di",
        "server",
        "api",
        "middleware",
        "commands",
        "db-postgres",
        "auth-jwt",
        "argon2-hasher",
    ]
}

[dev-dependencies]
reinhardt = {
    version = "...",
    features = ["test", "testcontainers"]
}
```

### Full-Stack with Pages

```toml
[dependencies]
reinhardt = {
    version = "...",
    default-features = false,
    features = [
        "core",
        "conf",
        "di",
        "server",
        "api",
        "forms",
        "pages",
        "client-router",
        "middleware",
        "sessions",
        "commands",
        "db-postgres",
        "auth-session",
        "argon2-hasher",
        "cache",
        "redis-backend",
        "i18n",
        "admin",
        "static-files",
    ]
}

[dev-dependencies]
reinhardt = {
    version = "...",
    features = ["test", "testcontainers", "server-fn-test"]
}
```

### Minimal Microservice

```toml
[dependencies]
reinhardt = {
    version = "...",
    default-features = false,
    features = [
        "core",
        "di",
        "server",
    ]
}

[dev-dependencies]
reinhardt = {
    version = "...",
    features = ["test"]
}
```

### GraphQL Server

```toml
[dependencies]
reinhardt = {
    version = "...",
    default-features = false,
    features = [
        "core",
        "di",
        "server",
        "graphql",
        "auth",
        "db-postgres",
    ]
}
```
