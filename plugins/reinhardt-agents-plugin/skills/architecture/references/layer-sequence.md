# Feature Implementation Layer Sequence

Step-by-step guide for implementing a complete feature in reinhardt. Each layer builds on the previous one.

---

## Layer 1: Model

Define the data model using the `#[model]` macro.

**Steps:**

1. Create model file: `src/<app>/models/<entity>.rs`
2. Define struct with `#[model]` attribute
3. Add fields with appropriate types and attributes
4. Re-export from `src/<app>/models.rs` via `pub use`
5. Generate migration: `cargo run --bin manage -- makemigrations`
6. Apply migration: `cargo run --bin manage -- migrate`

**Example:**

```rust
use reinhardt::prelude::*;

#[model]
pub struct Product {
    #[field(primary_key = true)]
    pub id: Option<Uuid>,

    #[field(max_length = 200)]
    pub name: String,

    #[field(null = true)]
    pub description: Option<String>,

    #[field(auto_now_add = true)]
    pub created_at: Option<NaiveDateTime>,
}
```

**Checklist:**

- [ ] `#[model]` macro applied
- [ ] Primary key defined (`Option<Uuid>` for auto-generated)
- [ ] `Option<T>` used for nullable fields
- [ ] Timestamps with `auto_now_add` / `auto_now`
- [ ] Module re-exported in parent `models.rs`
- [ ] Migration generated and applied

---

## Layer 2: Serializer

Define serializers for API input/output using `ModelSerializer` or custom serializers.

**Steps:**

1. Create serializer file or add to existing serializer module
2. Define serializer struct with `#[derive(Serialize, Deserialize, Schema)]`
3. For CRUD: use `ModelSerializer` pattern
4. For custom: define explicit fields

**Example:**

```rust
use reinhardt::rest::prelude::*;

#[derive(ModelSerializer)]
#[serializer(model = Product)]
pub struct ProductSerializer {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub created_at: NaiveDateTime,
}

#[derive(Deserialize, Validate, Schema)]
pub struct ProductCreateInput {
    pub name: String,
    pub description: Option<String>,
}
```

**Checklist:**

- [ ] Read serializer defined (for API responses)
- [ ] Write serializer/input defined (for API requests)
- [ ] Validation rules applied where needed
- [ ] Nested serializers for relations (if applicable)

---

## Layer 3: Shared Service or Endpoint-Local Flow

Create an injectable service only for stable capabilities or dependency bundles
shared by multiple endpoints. For endpoint-specific validation, DTO assembly,
persistence ordering, generation flows, outline edits, and response shaping,
keep the code in the `server_fn` / HTTP endpoint or a small private helper
beside it. DI is for common dependency injection and swappability, not a
mandatory abstraction layer for every use case.

Do not split a `#[server_fn]` only to move lines into `server/`, `service/`, or
`services/`. A new file is justified when it owns a smaller contract, isolates a
domain invariant for focused tests, or serves more than one endpoint. If the
extracted function still takes the endpoint input and returns the endpoint
response after running the same persistence/provider sequence, it is still the
endpoint workflow.

**Steps:**

1. Decide whether the logic is reused by multiple endpoints
2. Name the smaller contract, shared dependency, or invariant that extraction would isolate
3. If yes, create a service file: `src/<app>/services/<capability>.rs`
4. Define service struct with only common dependencies as fields
5. Register with DI using `#[injectable]`
6. If no, keep the flow in the endpoint or a nearby private helper

**Example:**

```rust
use reinhardt::prelude::*;

#[injectable_key]
struct PrimaryDatabase;

#[injectable(scope = "request")]
pub struct ProductCatalog {
    #[inject]
    db: Depends<PrimaryDatabase, DatabaseConnection>,
}

impl ProductCatalog {
    pub async fn get_by_id(&self, id: Uuid) -> Result<Product, AppError> {
        let product = Product::objects()
            .get(id, &*self.db)
            .await
            .map_err(|_| AppError::NotFound("Product not found".into()))?;
        Ok(product)
    }
}
```

**Checklist:**

- [ ] Service exists only when the capability or dependency bundle is reused across endpoints
- [ ] Endpoint-specific flows remain in the endpoint or a private helper beside it
- [ ] No file-only extraction from `#[server_fn]`; each extracted helper/service has a narrower contract, shared consumer, or independently testable invariant
- [ ] Service struct defined with injected common dependencies
- [ ] `#[injectable]` applied when a service is justified
- [ ] `#[injectable_key]` / `FactoryOutput<K, T>` used if the provider output type is not unique
- [ ] Returns reusable domain results; endpoint-specific DTO and response assembly stays outside the service
- [ ] Error handling uses domain error types
- [ ] No HTTP concerns (status codes, headers) in service
- [ ] No thick `OutlineService` / `ManuscriptService` / `DocumentService` facade that only hides one endpoint workflow
- [ ] Mutable operations enforce domain invariants before writing: accepted/current version uniqueness, exact sibling reorder lists, scoped searches, and idempotent re-index/regenerate behavior where applicable

---

## Layer 4: API Routes

Create views and URL routing for the feature.

**Steps:**

1. Define view functions or ViewSet
2. Configure URL routes
3. Apply authentication and permission guards

**Example:**

```rust
use reinhardt::prelude::*;
use reinhardt::rest::prelude::*;

#[get("/{id}")]
async fn get_product(
    path: Path<Uuid>,
    #[inject] catalog: ProductCatalog,
) -> Result<Json<ProductSerializer>, AppError> {
    let product = catalog.get_by_id(path.into_inner()).await?;
    Ok(Json(ProductSerializer::from_model(&product)))
}

#[post("/")]
async fn create_product(
    Json(input): Json<ProductCreateInput>,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
) -> Result<Json<ProductSerializer>, AppError> {
    input.validate()?;
    let product = build_product(input)?;
    let saved = Product::objects()
        .create_with_conn(&*db, &product)
        .await?;
    Ok(Json(ProductSerializer::from_model(&saved)))
}

fn build_product(input: ProductCreateInput) -> Result<Product, AppError> {
    Ok(Product {
        id: None,
        name: input.name,
        description: input.description,
        created_at: None,
    })
}

pub fn product_routes(cfg: &mut ServiceConfig) {
    cfg.service(
        scope("/products")
            .service(get_product)
            .service(create_product)
    );
}
```

**Checklist:**

- [ ] View functions defined with correct HTTP method decorators
- [ ] URL routes configured and mounted
- [ ] Authentication applied (if required)
- [ ] Permission guards applied (if required)
- [ ] Error mapping works (service errors → HTTP responses)

---

## Layer 5: Admin

Register the model in the admin panel.

**Steps:**

1. Define admin configuration with `#[admin]` macro
2. Register in the admin site

**Example:**

```rust
use reinhardt::admin::prelude::*;

#[admin(model = Product)]
pub struct ProductAdmin {
    list_display: vec!["id", "name", "created_at"],
    search_fields: vec!["id", "name"],
    readonly_fields: vec!["id", "created_at"],
    ordering: vec!["-created_at"],
    list_per_page: 25,
}
```

**Checklist:**

- [ ] `#[admin]` macro applied with model reference
- [ ] `list_display` configured (id first, max 6 fields)
- [ ] `search_fields` includes id
- [ ] `readonly_fields` includes id and auto-generated fields
- [ ] `ordering` specified
- [ ] `list_per_page` set

---

## Layer 6: Tests

Write tests at three levels: unit, integration, and API.

**Steps:**

1. **Unit tests** — test shared service logic or endpoint-local helpers
2. **Integration tests** — test with real database via TestContainers
3. **API tests** — test HTTP endpoints end-to-end

**Unit test example (endpoint-local helper):**

```rust
#[rstest]
fn test_build_product_success() {
    // Arrange
    let input = ProductCreateInput {
        name: "Test Product".into(),
        description: None,
    };

    // Act
    let result = build_product(input);

    // Assert
    assert!(result.is_ok());
    let product = result.unwrap();
    assert_eq!(product.name, "Test Product");
}
```

**Integration test example (DB):**

```rust
#[rstest]
#[tokio::test]
async fn test_product_round_trip(
    #[future] shared_db_pool: Arc<DatabasePool>,
    product_table: (),
) {
    // Arrange
    let db = shared_db_pool.await;
    let product = Product {
        id: None,
        name: "Integration Test".into(),
        description: Some("A test product".into()),
        created_at: None,
    };

    // Act
    let saved = Product::objects(&db).create(product).await.unwrap();
    let fetched = Product::objects(&db).get(saved.id.unwrap()).await.unwrap();

    // Assert
    assert_eq!(fetched.name, "Integration Test");
    assert_eq!(fetched.description, Some("A test product".into()));
}
```

**API test example:**

```rust
#[rstest]
#[tokio::test]
async fn test_create_product_api(
    #[future] api_client: APIClient,
) {
    // Arrange
    let client = api_client.await;
    let body = serde_json::json!({
        "name": "API Test Product",
        "description": "Created via API"
    });

    // Act
    let response = client.post("/products/", Some(body)).await;

    // Assert
    assert_eq!(response.status(), 201);
    let json = response.json::<serde_json::Value>().await;
    assert_eq!(json["name"], "API Test Product");
}
```

**Checklist:**

- [ ] Unit tests for shared service business logic or endpoint-local helpers
- [ ] Integration tests with TestContainers for DB operations
- [ ] API tests for HTTP endpoint behavior
- [ ] All tests use `#[rstest]`, not `#[test]`
- [ ] AAA pattern with standard labels (`// Arrange`, `// Act`, `// Assert`)
- [ ] Assertions use `assert_eq!` / `assert_ne!` / `assert!(matches!(...))` — not loose checks

---

## Layer 7: Signals (Optional)

Add async side-effects for post-commit operations.

**Steps:**

1. Connect signal receiver for model events
2. Implement receiver as idempotent async function
3. Optionally enqueue background tasks

**Example:**

```rust
use reinhardt::signals::{post_save, connect_receiver};

// In app setup
connect_receiver!(
    post_save::<Product>(),
    |product: Arc<Product>, _ctx| async move {
        // Enqueue notification task
        let task = NotifyProductCreated::new(product.id.unwrap());
        TaskQueue::enqueue(task).await?;
        Ok(())
    },
    dispatch_uid = "product_post_save_notify"
);
```

**Checklist:**

- [ ] Signal receiver connected with `connect_receiver!`
- [ ] `dispatch_uid` set for deduplication
- [ ] Receiver is idempotent (safe to call multiple times)
- [ ] Arguments are serializable (IDs, not model instances)
- [ ] No cascading signal triggers
- [ ] Tests verify receiver behavior in isolation

---

## Quick Decision Guide

| Question | Answer |
|----------|--------|
| Need custom query logic? | Put in service, use `reinhardt-query` |
| Need auth on endpoint? | Apply guard in route config |
| Need async side-effect? | Use signal + task (Layer 7) |
| Need admin access? | Register with `#[admin]` (Layer 5) |
| Which test layer first? | Unit (service) — fastest feedback |
