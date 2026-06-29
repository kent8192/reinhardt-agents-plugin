# Reinhardt Serializer Patterns Reference

## Architecture Overview

Reinhardt's serializer system follows Django REST Framework's design philosophy with a two-layer architecture:

- **Core Layer (`reinhardt-core`)**: ORM-agnostic traits, field types, validation, arena allocation
- **REST Layer (`reinhardt-rest`)**: ORM-integrated serializers (`ModelSerializer`, `NestedSerializer`, etc.)

```text
reinhardt-rest::serializers
  ├── ModelSerializer<M>              (ORM model serialization)
  ├── HyperlinkedModelSerializer<M>   (HATEOAS URL generation)
  ├── NestedSerializer<M, R>          (read-only nested relationships)
  ├── WritableNestedSerializer<M, R>  (writable nested relationships)
  ├── ListSerializer<M>               (collection serialization)
  └── SerializerMethodField           (computed fields)

reinhardt-core::serializers
  ├── Serializer trait                (bidirectional serialization)
  ├── Deserializer trait              (one-way deserialization)
  ├── JsonSerializer<T>               (JSON implementation)
  ├── Field types                     (CharField, IntegerField, etc.)
  ├── Validation                      (field-level, object-level)
  ├── SerializationArena              (memory-efficient nested serialization)
  └── SerializationContext            (depth tracking, circular reference detection)
```

---

## Core Serializer Trait

The `Serializer` trait is the foundation for all serializers. It defines bidirectional conversion between `Input` and `Output` types.

```rust
use reinhardt_core::serializers::{Serializer, SerializerError};

pub trait Serializer {
    type Input;
    type Output;

    fn serialize(&self, input: &Self::Input) -> Result<Self::Output, SerializerError>;
    fn deserialize(&self, output: &Self::Output) -> Result<Self::Input, SerializerError>;
}
```

### JsonSerializer (Base Implementation)

For simple serde-based serialization without ORM integration:

```rust
use reinhardt_core::serializers::{Serializer, JsonSerializer};
use serde::{Serialize, Deserialize};

#[derive(Serialize, Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
}

let serializer = JsonSerializer::<LoginRequest>::new();

// Serialize to JSON string
let json = serializer.serialize(&request)?;

// Deserialize from JSON string
let request: LoginRequest = serializer.deserialize(&json_str)?;
```

**Use when:** Non-model data, simple request/response types, no ORM integration needed.

---

## ModelInfo and Validate for Model-Backed DTOs (0.2.x)

For model-backed request/response shapes, start from the generated
`{Model}Info` companion type instead of duplicating every model field in custom
serializer structs. Layer `Validate` / `#[validate(...)]` on explicit input
types when the API needs request-only constraints.

Use custom serializer structs only when the API boundary intentionally differs
from the model shape, such as redacting fields, flattening nested data, or
combining multiple models. In that case, document the boundary in the type name
and keep conversions centralized.

Checklist:

- Use `{Model}Info` for read DTOs when the public shape matches the model.
- Use `#[field(skip_info = true)]` on model fields that must not appear in info DTOs.
- Use `Validate` / `#[validate(...)]` on write DTOs for request-level constraints.
- Avoid hand-written serializers that merely mirror every model field.

---

## ModelSerializer

`ModelSerializer<M>` automatically generates serialization logic from ORM models using a builder pattern. It is the recommended approach for standard CRUD endpoints.

```rust
use reinhardt_rest::serializers::{ModelSerializer, Serializer};
use reinhardt_rest::serializers::introspection::{FieldIntrospector, FieldInfo};

// Basic usage
let serializer = ModelSerializer::<User>::new();

// With field configuration (builder pattern)
let serializer = ModelSerializer::<User>::new()
    .with_fields(vec!["id".into(), "username".into(), "email".into()])
    .with_read_only_fields(vec!["id".into()])
    .with_write_only_fields(vec!["password_hash".into()])
    .with_exclude(vec!["internal_flag".into()]);

// With field introspector for automatic field discovery
let mut introspector = FieldIntrospector::new();
introspector.register_field(FieldInfo::new("id", "Uuid").primary_key());
introspector.register_field(FieldInfo::new("username", "String"));
introspector.register_field(FieldInfo::new("email", "String").optional());

let serializer = ModelSerializer::<User>::new()
    .with_introspector(introspector)
    .with_read_only_fields(vec!["id".into()]);

// Serialize
let json_string = serializer.serialize(&user)?;

// Deserialize
let user: User = serializer.deserialize(&json_string)?;

// Synchronous validation (non-database)
serializer.validate(&user)?;

// Async validation with database checks (unique constraints)
serializer.validate_async(&connection, &user).await?;
```

### ModelSerializer Configuration

| Method | Description |
|--------|-------------|
| `.with_fields(Vec<String>)` | Explicit list of fields to include |
| `.with_exclude(Vec<String>)` | Fields to exclude from the model |
| `.with_read_only_fields(Vec<String>)` | Fields included in output but ignored on input |
| `.with_write_only_fields(Vec<String>)` | Fields accepted on input but excluded from output |
| `.with_introspector(FieldIntrospector)` | Automatic field discovery from model definition |
| `.with_nested_field(NestedFieldConfig)` | Configure nested relationship serialization |
| `.with_unique_validator(UniqueValidator)` | Add unique constraint validation |
| `.with_unique_together_validator(...)` | Add composite unique constraint validation |

### ModelSerializer Query Methods

| Method | Description |
|--------|-------------|
| `.field_names()` | Get all configured field names |
| `.required_fields()` | Get fields that are not optional |
| `.optional_fields()` | Get fields that are optional |
| `.primary_key_field()` | Get the primary key field info |
| `.is_nested_field(name)` | Check if a field is nested |
| `.meta()` | Access the MetaConfig |
| `.validators()` | Access the ValidatorConfig |

---

## HyperlinkedModelSerializer

Extends serialization with automatic URL field generation for HATEOAS-style REST APIs.

```rust
use reinhardt_rest::serializers::{HyperlinkedModelSerializer, UrlReverser, Serializer};
use std::sync::Arc;
use std::collections::HashMap;

// Implement UrlReverser for your router
struct MyUrlReverser;
impl UrlReverser for MyUrlReverser {
    fn reverse(&self, name: &str, params: &HashMap<String, String>) -> Result<String, String> {
        Ok(format!("/api/users/{}/", params.get("id").unwrap()))
    }
}

let reverser: Arc<dyn UrlReverser> = Arc::new(MyUrlReverser);

// Create with URL reverser
let serializer = HyperlinkedModelSerializer::<User>::new("user-detail", Some(reverser));

// Customize URL field name (default: "url")
let serializer = HyperlinkedModelSerializer::<User>::new("user-detail", None)
    .url_field_name("self_link");

// Serialized output includes the URL field:
// {"id": 1, "username": "alice", "url": "/api/users/1/"}
let json = serializer.serialize(&user)?;
```

**Use when:** Building HATEOAS/hypermedia-driven APIs where responses include navigable URLs.

---

## NestedSerializer

Embeds related model data inline (read-only). Works with data already loaded by the ORM layer.

```rust
use reinhardt_rest::serializers::{NestedSerializer, Serializer};

// Basic: serialize a post with its author
let serializer = NestedSerializer::<Post, Author>::new("author");

// Control nesting depth (default: 1)
let serializer = NestedSerializer::<Post, Author>::new("author")
    .depth(2);  // Serialize author and author's nested relationships

// Disable arena allocation (use heap allocation instead)
let serializer = NestedSerializer::<Post, Author>::new("author")
    .without_arena();

// Output: {"id": 1, "title": "My Post", "author": {"id": 1, "name": "Alice"}}
let json = serializer.serialize(&post)?;
```

**Important:** The ORM layer is responsible for loading related data:

```rust,ignore
// 1. Load data with relationships using ORM
let posts = Post::objects()
    .select_related("author")
    .all()
    .await?;

// 2. Serialize with NestedSerializer (data is already loaded)
let serializer = NestedSerializer::<Post, Author>::new("author");
let json = serializer.serialize(&post)?;
```

### WritableNestedSerializer

Extends `NestedSerializer` with create/update permission control for nested objects.

```rust
use reinhardt_rest::serializers::WritableNestedSerializer;

// Create with permissions
let serializer = WritableNestedSerializer::<Post, Comment>::new("comments")
    .allow_create(true)   // Allow creating nested instances
    .allow_update(true);  // Allow updating nested instances

// Extract nested data for manual ORM processing
let nested_data = serializer.extract_nested_data(&json_str)?;
if let Some(data) = nested_data {
    // Check if it's a create or update operation
    if WritableNestedSerializer::<Post, Comment>::is_create_operation(&data) {
        // Create new related object
    } else {
        // Update existing related object
    }
}
```

**Design principle:** The serializer validates JSON structure and permissions; the caller handles database operations within transactions.

### ListSerializer

Serializes collections of model instances.

```rust
use reinhardt_rest::serializers::{ListSerializer, Serializer};

let serializer = ListSerializer::<User>::new();

let users = vec![user1, user2, user3];
let json = serializer.serialize(&users)?;
// Output: [{"id": 1, ...}, {"id": 2, ...}, {"id": 3, ...}]
```

---

## SerializerMethodField

Adds computed fields that don't correspond to model fields.

```rust
use reinhardt_rest::serializers::{SerializerMethodField, MethodFieldProvider};
use reinhardt_rest::serializers::method_field::MethodFieldRegistry;
use serde_json::{json, Value};
use std::collections::HashMap;

// Create a method field
let field = SerializerMethodField::new("full_name");

// With custom method name
let field = SerializerMethodField::new("full_name")
    .method_name("compute_full_name");

// Retrieve value from a pre-computed context
let mut context = HashMap::new();
context.insert("full_name".to_string(), json!("John Doe"));
let value = field.get_value(&context)?;

// Use a registry for multiple method fields
let mut registry = MethodFieldRegistry::new();
registry.register("full_name", SerializerMethodField::new("full_name"));
registry.register("post_count", SerializerMethodField::new("post_count"));
```

**Use when:** Adding derived/computed values (e.g., full name from first + last, post count, formatted dates).

---

## Serializer Field Types

Fields from `reinhardt-core` provide validation for individual values.

| Field Type | Validation Options |
|------------|-------------------|
| `CharField` | `max_length`, `min_length`, `allow_blank`, `allow_null` |
| `IntegerField` | `min_value`, `max_value` |
| `FloatField` | `min_value`, `max_value` |
| `BooleanField` | `required`, `allow_null` |
| `EmailField` | Email format validation |
| `URLField` | URL format validation |
| `ChoiceField` | Validates against allowed choices list |
| `DateField` | ISO 8601 date format |
| `DateTimeField` | ISO 8601 datetime format |

All fields support: `required`, `allow_null`, `default`, and builder pattern configuration.

```rust
use reinhardt_rest::serializers::{CharField, IntegerField, EmailField};

let username = CharField::new()
    .max_length(150)
    .min_length(3)
    .required(true);

let age = IntegerField::new()
    .min_value(0)
    .max_value(200);

let email = EmailField::new()
    .required(true);
```

---

## Relation Fields

| Field Type | Representation | Example Output |
|------------|---------------|----------------|
| `PrimaryKeyRelatedField<T>` | Primary key | `{"author": 42}` |
| `SlugRelatedField<T>` | Slug/unique text field | `{"category": "technology"}` |
| `StringRelatedField<T>` | Display string (read-only) | `{"author": "john_doe"}` |
| `HyperlinkedRelatedField<T>` | URL | `{"author": "/api/authors/42/"}` |
| `IdentityField<T>` | Full nested object | `{"profile": {"id": 1, ...}}` |
| `ManyRelatedField<T>` | Collection of related objects | `{"tags": [1, 2, 3]}` |

```rust
use reinhardt_rest::serializers::{
    PrimaryKeyRelatedField, SlugRelatedField,
    HyperlinkedRelatedField, StringRelatedField,
    ManyRelatedField, IdentityField,
};

// Use as struct field types in your model/serializer structs
struct PostResponse {
    id: i64,
    title: String,
    author: PrimaryKeyRelatedField<User>,      // {"author": 42}
    category: SlugRelatedField<Category>,       // {"category": "tech"}
    tags: ManyRelatedField<Tag>,                // {"tags": [1, 2, 3]}
}
```

---

## Database Validators

```rust
use reinhardt_rest::serializers::{
    ModelSerializer, UniqueValidator, UniqueTogetherValidator,
};

let serializer = ModelSerializer::<User>::new()
    .with_unique_validator(UniqueValidator::new("username"))
    .with_unique_validator(UniqueValidator::new("email"))
    .with_unique_together_validator(
        UniqueTogetherValidator::new(vec!["first_name", "last_name"])
    );

// Async validation checks the database
serializer.validate_async(&connection, &user).await?;
```

---

## Meta Configuration

Two approaches for configuring serializer behavior:

### Builder-Based (MetaConfig)

```rust
use reinhardt_rest::serializers::meta::MetaConfig;

let config = MetaConfig::new()
    .with_fields(vec!["id".into(), "username".into(), "email".into()])
    .with_exclude(vec!["password_hash".into()])
    .with_read_only_fields(vec!["id".into()])
    .with_write_only_fields(vec!["password".into()]);

config.is_field_included("username"); // true
config.is_read_only("id");           // true
config.is_write_only("password");    // true
```

### Trait-Based (SerializerMeta)

```rust
use reinhardt_rest::serializers::meta::SerializerMeta;

struct UserSerializerMeta;

impl SerializerMeta for UserSerializerMeta {
    fn fields() -> Option<Vec<String>> {
        Some(vec!["id".into(), "username".into(), "email".into()])
    }

    fn read_only_fields() -> Vec<String> {
        vec!["id".into()]
    }

    fn exclude() -> Vec<String> {
        vec!["password_hash".into()]
    }
}
```

---

## Custom Serializer (Implementing the Trait)

For non-model serialization or complex validation logic:

```rust
use reinhardt_core::serializers::{Serializer, SerializerError};

struct LoginSerializer;

impl Serializer for LoginSerializer {
    type Input = LoginRequest;
    type Output = String;

    fn serialize(&self, input: &Self::Input) -> Result<Self::Output, SerializerError> {
        serde_json::to_string(input).map_err(|e| SerializerError::Serde {
            message: format!("Serialization error: {}", e),
        })
    }

    fn deserialize(&self, output: &Self::Output) -> Result<Self::Input, SerializerError> {
        let request: LoginRequest = serde_json::from_str(output)
            .map_err(|e| SerializerError::Serde {
                message: format!("Deserialization error: {}", e),
            })?;

        // Custom validation
        if request.username.is_empty() {
            return Err(SerializerError::required_field(
                "username".into(),
                "This field is required.".into(),
            ));
        }
        if request.password.len() < 8 {
            return Err(SerializerError::field_validation(
                "password".into(),
                request.password.clone(),
                "min_length".into(),
                "Password must be at least 8 characters.".into(),
            ));
        }

        Ok(request)
    }
}
```

---

## Error Types

```rust
use reinhardt_core::serializers::{SerializerError, ValidatorError};

// SerializerError variants:
SerializerError::Validation(ValidatorError)  // Validation failure
SerializerError::Serde { message }           // serde error
SerializerError::Other { message }           // Generic error

// ValidatorError variants:
ValidatorError::UniqueViolation { field_name, value, message }
ValidatorError::UniqueTogetherViolation { field_names, values, message }
ValidatorError::RequiredField { field_name, message }
ValidatorError::FieldValidation { field_name, value, constraint, message }
ValidatorError::DatabaseError { message, source }
ValidatorError::Custom { message }

// Convenience constructors on SerializerError:
SerializerError::unique_violation(field, value, msg)
SerializerError::required_field(field, msg)
SerializerError::field_validation(field, value, constraint, msg)
SerializerError::database_error(msg, source)
```

---

## Performance Features

```rust
use reinhardt_rest::serializers::{
    QueryCache, N1Detector, BatchValidator,
    PerformanceMetrics, IntrospectionCache,
};
use reinhardt_core::serializers::arena::SerializationArena;

// Arena allocation for nested structures (60-90% memory reduction)
let arena = SerializationArena::new();
let serialized = arena.serialize_model(&post, depth);
let json = arena.to_json(serialized);

// N+1 query detection
let detector = N1Detector::new();

// Query caching
let cache = QueryCache::new();

// Batch validation for multiple objects
let validator = BatchValidator::new();
```

---

## Content Negotiation

```rust
use reinhardt_rest::serializers::ContentNegotiator;

let negotiator = ContentNegotiator::new();
// Select parser based on request Content-Type header
```

---

## Pattern Selection Guide

| Scenario | Recommended Pattern |
|----------|-------------------|
| Standard CRUD endpoints | `ModelSerializer` |
| HATEOAS/hypermedia APIs | `HyperlinkedModelSerializer` |
| Detail views with nested data | `NestedSerializer` (read-only) |
| Creating/updating nested objects | `WritableNestedSerializer` |
| Collection endpoints | `ListSerializer` |
| Computed/derived fields | `SerializerMethodField` |
| Non-model data (login, config) | Custom `Serializer` impl or `JsonSerializer` |
| Simple serde round-trip | `JsonSerializer<T>` |

---

## ModelSerializer Meta Options (rc.23+ regression-fix)

Since v0.1.0-rc.23, `ModelSerializer<M>::serialize` / `deserialize` /
`validate` actually consult `MetaConfig` and the registered validators. In
prior releases the public builder methods were accepted but the
`Serializer` trait impl bypassed them entirely and fell through to a plain
`serde_json` round-trip, so configured constraints were silently ignored —
e.g. `password_hash` could leak despite `with_exclude`, and `id` could be
overwritten despite `with_read_only_fields` (#3993, resolves #3992).

### Honored Meta options

| Builder method | Direction | Behavior (rc.23+) |
|----------------|-----------|-------------------|
| `.with_fields(Vec<String>)` | serialize + deserialize | Only the listed fields survive the round-trip. |
| `.with_exclude(Vec<String>)` | serialize + deserialize | Listed keys are dropped from the output and stripped from input. |
| `.with_read_only_fields(Vec<String>)` | deserialize | Listed keys are stripped from deserialize input (cannot be set by clients) but remain in serialize output. |
| `.with_write_only_fields(Vec<String>)` | serialize | Listed keys are stripped from serialize output but accepted on deserialize input. |

`.with_exclude` and `.with_fields` are mutually exclusive in practice;
follow the existing MetaConfig precedence rules documented above.

### Synchronous validators now run

`ModelSerializer::validate` (sync) now executes any validators registered
via the new `ModelLevelValidator<M>` trait and the
`.with_model_validator(...)` builder. `validate_async` runs the sync
`validate` first so registered sync validators fail-fast before any
database round-trip.

New public surface (non-breaking additions):

- Trait: `ModelLevelValidator<M>`
- Builder: `ModelSerializer::<M>::with_model_validator(...)`
- `ValidatorConfig::validate` (sync) and
  `ValidatorConfig::add_sync_model_validator`

Validation failures surface as `SerializerError::Validation(...)`.

### `WritableNestedSerializer::serialize`

Previously emitted an output that silently ignored the parent. As of
rc.23 it uses the same arena path as `NestedSerializer::serialize` and
returns a complete parent JSON document. Nested *writes* still go through
`extract_nested_data` — the synchronous trait API does not perform lazy
loading; the caller drives the ORM.

Source: kent8192/reinhardt-web (#3993), resolves #3992.
