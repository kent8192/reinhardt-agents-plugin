# Reinhardt Derive Macros Reference

All derive macros are re-exported through the `reinhardt` facade crate.

---

## Model & ORM

### `#[derive(Model)]`

**Crate:** `reinhardt-core/macros`

Auto-generate `Model` trait implementation and migration registration.

```rust
#[derive(Model, Clone, Debug, Serialize, Deserialize)]
pub struct Post {
    pub id: Option<Uuid>,
    pub title: String,
    pub content: String,
}
```

> **Note:** Prefer using `#[model]` attribute macro, which auto-derives `Model` along with other traits.

### `#[derive(QueryFields)]`

**Crate:** `reinhardt-core/macros`

Generate type-safe field lookups for ORM queries.

```rust
#[derive(QueryFields)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    pub email: String,
    pub age: i32,
}

// Generated: User::id(), User::username(), User::email(), User::age()
// Usage:
let users = User::objects()
    .filter(User::age().gte(18))
    .order_by(User::username(), true)
    .all().await?;
```

### `#[derive(OrmReflectable)]`

**Crate:** `reinhardt-core/macros`

ORM reflection for association proxies.

```rust
#[derive(OrmReflectable)]
pub struct UserProfile {
    pub user_id: Uuid,
    pub bio: String,
}
```

---

## Validation

### Shared DTO validation with `#[dto]` **(0.4.0; #5543)**

For a request or form DTO shared by native/server and WASM/client code, prefer
[`#[dto]`](attribute-macros.md#dto) over manually deriving `Validate`. The
attribute emits Reinhardt's shared `Validate` implementation; `Serialize`,
`Deserialize`, `Debug`, `Clone`, and optional OpenAPI `Schema` remain explicit
derives.

Keep `#[dto]` above any explicit or legacy native-only `Validate` derive so it
can avoid duplicates or normalize the legacy form. Shared DTOs must have named
fields and use unconditional `#[validate(...)]` attributes with `email`, `url`,
`length`, or `range` rules. Revalidate after deserialization on the server;
client validation is not an authorization or business-rule boundary.

### `#[derive(Validate)]`

**Crate:** `reinhardt-core/macros`

Struct-level validation from field attributes.

```rust
#[derive(Validate)]
pub struct CreateUserRequest {
    #[validate(length(min = 3, max = 50))]
    pub username: String,

    #[validate(email)]
    pub email: String,

    #[validate(url)]
    pub website: Option<String>,

    #[validate(range(min = 0, max = 150))]
    pub age: i32,

    #[validate(length(min = 8))]
    pub password: String,
}

// Usage:
let request = CreateUserRequest { /* ... */ };
request.validate()?; // Returns Result<(), ValidationErrors>
```

Use `Validate` directly on server-only request/input types and on versions
through 0.3.x. For shared 0.4.0 DTOs, use `#[dto]` as described above. For
response DTOs that match a model, prefer the `{Model}Info` companion generated
by `#[model]` instead of creating a parallel serializer struct with the same
fields.

**Validation Rules:**

| Rule | Description | Example |
|------|-------------|---------|
| `email` | Valid email format | `#[validate(email)]` |
| `url` | Valid URL format | `#[validate(url)]` |
| `length(min, max)` | String length range | `#[validate(length(min = 3, max = 50))]` |
| `range(min, max)` | Numeric range | `#[validate(range(min = 0, max = 100))]` |

---

## DTO-Derived Client Forms (0.4.0)

### `#[derive(ClientForm)]`

**Crate:** `reinhardt-pages/macros`

Generate a typed `use_form` companion from a non-generic, named request DTO.
The default generated names are `<Request>ClientForm`,
`<Request>ClientFormValues`, and `<Request>ClientFormField`. This is opt-in and
does not replace `form!` for independently designed or unsupported UI schemas.

```rust,ignore
#[reinhardt::dto]
#[derive(Clone, serde::Serialize, serde::Deserialize, ClientForm)]
#[client_form(name = ProjectEditorForm, validate, server_fn = crate::server::save_project)]
pub struct ProjectRequest {
    pub title: Option<String>,
    pub visibility: Visibility,
    #[client_form(skip)]
    pub tenant_id: Option<String>,
}
```

| `#[client_form(...)]` option | Effect |
|------------------------------|--------|
| `name = FormStem` | Overrides the generated companion name stem. |
| `validate` | Maps DTO `Validate` errors to generated form field/form errors. |
| `server_fn = path` | Generates a typed async submit helper for WASM. It requires DTO `Serialize`, a matching marker request, `DeserializeOwned` response, and `Display + From<ServerFnError>` error types. |
| Field `skip` | Keeps an `Option<T>` or `Default` field out of the editable form while preserving its hidden/default value. |

Supported editable fields are strings, optional strings, primitive numeric
types, booleans, and `ClientFormChoices` enums with their supported `Option`
forms. Whitespace-only optional strings reconstruct as `None`. Collections,
maps, generic fields, generic DTOs, and unsupported nested shapes intentionally
fail to derive.

For an exported DTO, every editable field must be public. A generated
`server_fn` helper cannot use serde-skipped request fields because the browser
payload must deserialize exactly like the native request. The `form.submit(...)`
helper is WASM-only; use the shared `use_form` async runtime directly in native
tests.

### `#[derive(ClientFormChoices)]`

**Crate:** `reinhardt-pages/macros`

Generate typed choices for a fieldless, externally tagged enum used by
`ClientForm`. Choice strings must have matching serde serialization and
deserialization names. Matching variant rename values and `snake_case`,
`kebab-case`, or `camelCase` `rename_all` rules are supported; data variants,
tagged/untagged representations, directional renames that produce different
wire names, and colliding aliases or choice strings are rejected at compile time.

```rust,ignore
#[derive(Clone, Default, PartialEq, ClientFormChoices)]
#[serde(rename_all = "snake_case")]
pub enum Visibility {
    #[default]
    Private,
    TeamOnly,
}
```

See `../../pages/references/client-form-bindings.md` for the runtime, validation,
submission, and testing workflow.

---

## API Documentation

### `#[derive(Schema)]`

**Crate:** `reinhardt-rest/openapi-macros` (also available in `reinhardt-core/macros`)

Auto-generate OpenAPI 3.0 schema definitions.

```rust
#[derive(Schema, Serialize)]
#[schema(title = "User Response", description = "User data returned by API")]
pub struct UserResponse {
    #[schema(description = "User unique identifier", read_only)]
    pub id: Uuid,

    #[schema(description = "Username", example = "alice")]
    pub username: String,

    #[schema(description = "Email address", format = "email")]
    pub email: String,

    #[schema(deprecated)]
    pub legacy_field: Option<String>,
}
```

**Container Attributes (`#[schema(...)]`):**

| Attribute | Description |
|-----------|-------------|
| `title = "..."` | Override schema title |
| `description = "..."` | Schema description |
| `example = "..."` | Example value |
| `deprecated` | Mark as deprecated |
| `nullable` | Allow null values |

**Field Attributes (`#[schema(...)]`):**

| Attribute | Description |
|-----------|-------------|
| `description = "..."` | Field description |
| `example = "..."` | Field example |
| `default` | Has default value |
| `deprecated` | Field deprecated |
| `read_only` | Read-only field |
| `write_only` | Write-only field |
| `format = "..."` | OpenAPI format (`email`, `uri`, `date-time`, etc.) |
| `minimum` / `maximum` | Numeric constraints |
| `exclusive_minimum` / `exclusive_maximum` | Exclusive numeric constraints |
| `multiple_of` | Multiple constraint |
| `min_length` / `max_length` | String length constraints |
| `pattern = "..."` | Regex pattern |
| `min_items` / `max_items` | Array item count |
| `unique_items` | Array uniqueness |
| `nullable` | Nullable field |
| `default_value = "..."` | Default value (JSON) |

---

## SQL Identifiers

### `#[derive(Iden)]`

**Crate:** `reinhardt-query/macros`

Generate SQL identifier names for use with the low-level query builder.

```rust
#[derive(Iden)]
pub enum Users {
    Table,
    Id,
    #[iden = "email_address"]
    Email,
    Username,
}

// Usage with reinhardt-query:
// Users::Table → "users"
// Users::Id → "id"
// Users::Email → "email_address"
// Users::Username → "username"
```

**Attributes:**

| Attribute | Description |
|-----------|-------------|
| `#[iden = "custom_name"]` | Custom SQL identifier |
| `#[iden("custom_name")]` | Alternative syntax |

---

## gRPC/GraphQL Integration

### `#[derive(GrpcGraphQLConvert)]`

**Crate:** `reinhardt-graphql/macros`

Auto-generate conversion between Protobuf and GraphQL types.

```rust
#[derive(GrpcGraphQLConvert)]
pub struct UserMessage {
    pub id: String,
    pub name: String,
}
```

### `#[derive(GrpcSubscription)]`

**Crate:** `reinhardt-graphql/macros`

Map gRPC streaming to GraphQL subscriptions.

```rust
#[derive(GrpcSubscription)]
pub struct UserEventSubscription {
    // ...
}
```

---

## App Configuration

### `#[derive(AppConfig)]`

**Crate:** `reinhardt-core/macros`

AppConfig factory generation (internal — used by `#[app_config]` attribute).

> **Note:** Prefer using the `#[app_config]` attribute macro.

### `#[derive(ApplyUpdate)]`

**Crate:** `reinhardt-core/macros`

ApplyUpdate trait generation (internal — used by `#[apply_update]` attribute).

> **Note:** Prefer using the `#[apply_update]` attribute macro.

## Dynamic References

For the latest derive macro definitions:

1. Read `reinhardt/crates/reinhardt-core/macros/src/lib.rs` for Model, QueryFields, Validate, Schema, OrmReflectable
2. Read `reinhardt/crates/reinhardt-query/macros/src/lib.rs` for Iden
3. Read `reinhardt/crates/reinhardt-rest/openapi-macros/src/lib.rs` for Schema (REST variant)
4. Read `reinhardt/crates/reinhardt-graphql/macros/src/lib.rs` for GrpcGraphQLConvert, GrpcSubscription
