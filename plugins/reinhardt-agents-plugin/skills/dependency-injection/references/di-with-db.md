# DI with Database and Auth Reference

## DatabaseConnection Injection

`DatabaseConnection` is available from the DI registry when the database feature
is enabled. In 0.3.x, examples that consume it through `Depends` assume a keyed
provider such as `PrimaryDatabase`. Register the provider before injecting it:

```rust
use reinhardt::di::prelude::*;
use reinhardt::db::prelude::*;

#[injectable_key]
struct PrimaryDatabase;

#[injectable(scope = "singleton")]
async fn create_primary_database(
    #[inject] settings: DbSettings,
) -> FactoryOutput<PrimaryDatabase, DatabaseConnection> {
    let db = DatabaseConnection::connect(&settings.database_url).await.unwrap();
    FactoryOutput::new(db)
}
```

```rust
use reinhardt::db::prelude::*;
use reinhardt::di::prelude::*;
use reinhardt::CurrentUser;
use reinhardt::views::prelude::*;

#[get("/users/{id}/", name = "user_retrieve")]
pub async fn get_user(
    Path(id): Path<i64>,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
) -> ViewResult<Response> {
    let user = User::objects()
        .filter(User::id.eq(id))
        .get(&*db)
        .await
        .map_err(|_| AppError::NotFound("User not found".into()))?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(user))?))
}
```

### Transaction Support

```rust
#[post("/transfers/", name = "transfer_create")]
pub async fn transfer_funds(
    Json(data): Json<TransferRequest>,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
) -> ViewResult<Response> {

    // Begin a transaction
    let tx = db.begin().await?;

    Account::objects()
        .filter(Account::id.eq(data.from_id))
        .update(Account::balance.sub(data.amount))
        .execute(&tx)
        .await?;

    Account::objects()
        .filter(Account::id.eq(data.to_id))
        .update(Account::balance.add(data.amount))
        .execute(&tx)
        .await?;

    tx.commit().await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&json!({ "status": "completed" }))?))
}
```

## CurrentUser Injection

`CurrentUser<T>` extracts the authenticated user from the request. It reads the authentication token or session state and resolves the user model.

```rust
use reinhardt::auth::prelude::*;
use reinhardt::di::prelude::*;
use reinhardt::views::prelude::*;

#[get("/profile/", name = "user_profile")]
pub async fn get_profile(
    #[inject] AuthInfo(state): AuthInfo,
) -> ViewResult<Response> {
    let user_id = state.user_id();
    let profile = Profile::objects().filter(Profile::user_id.eq(user_id)).get().await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&ProfileResponse::from(profile))?))
}
```

### Full User Model with CurrentUser<T>

`CurrentUser<T>` resolves the full user model from the auth token or session:

```rust
#[delete("/admin/users/{id}/", name = "admin_user_delete")]
pub async fn delete_user(
    Path(id): Path<i64>,
    #[inject] CurrentUser(admin): CurrentUser<User>,
) -> ViewResult<Response> {
    if !admin.is_staff {
        return Err(AppError::Authentication("Admin access required".into()));
    }

    let user = User::objects().get(id).await
        .map_err(|_| AppError::NotFound("User not found".into()))?;
    user.delete().await?;

    Ok(Response::new(StatusCode::NO_CONTENT))
}
```

### Optional Authentication

Use `Option<CurrentUser<T>>` for endpoints that work for both authenticated and anonymous users:

```rust
#[get("/posts/", name = "post_list")]
pub async fn list_posts(
    #[inject] auth: Option<CurrentUser<User>>,
) -> ViewResult<Response> {
    let mut query = Post::objects().filter(Post::is_published.eq(true));

    // Authenticated users see their own drafts too
    if let Some(CurrentUser(user)) = &auth {
        query = query.or_filter(Post::author_id.eq(user.id));
    }

    let posts = query.all().await?;
    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&posts)?))
}
```

## Session Injection

> **Note**: JWT is the verified production pattern (confirmed in the reinhardt-cloud dashboard). Session-based types should be verified against `reinhardt/crates/reinhardt-auth/src/sessions/` before use.

`Session` provides access to the current request's session key-value store (when using session-based auth).

```rust
use reinhardt::auth::prelude::*;
use reinhardt::di::prelude::*;
use reinhardt::views::prelude::*;

#[get("/cart/", name = "cart_get")]
pub async fn get_cart(
    #[inject] session: Session,
) -> ViewResult<Response> {
    let cart: Option<Cart> = session.get("cart").await?;
    let body = match cart {
        Some(cart) => json::to_vec(&cart)?,
        None => json::to_vec(&json!({ "items": [] }))?,
    };
    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(body))
}

#[post("/cart/items/", name = "cart_add_item")]
pub async fn add_to_cart(
    Json(item): Json<CartItem>,
    #[inject] session: Session,
) -> ViewResult<Response> {
    let mut cart: Cart = session
        .get("cart")
        .await?
        .unwrap_or_default();

    cart.add(item);
    session.set("cart", &cart).await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&cart)?))
}
```

## Combining Multiple Injections

Handlers can receive any combination of injectable types:

```rust
#[post("/orders/", name = "order_create")]
pub async fn create_order(
    #[inject] AuthInfo(state): AuthInfo,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
    #[inject] email_service: EmailService,
    #[inject] session: Session,
) -> ViewResult<Response> {
    let cart: Cart = session
        .get("cart")
        .await?
        .ok_or_else(|| AppError::Validation("Cart is empty".into()))?;

    // Create order in a transaction
    let tx = db.begin().await?;
    let order = Order::create_from_cart(&cart, state.user_id(), &tx).await?;
    tx.commit().await?;

    // Clear cart from session
    session.remove("cart").await?;

    // Send confirmation email
    email_service.send_order_confirmation(&order, state.user_id()).await?;

    Ok(Response::new(StatusCode::CREATED)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&OrderResponse::from(order))?))
}
```

## Avoid CRUD-only Injectable Repositories

Do not create injectable repository types just to wrap direct
`Model::objects()` calls such as `find_by_email`, `find_active`, `create`, or
`deactivate`. Keep route-specific CRUD visible in the handler or `server_fn`
beside local `NotFound` mapping, ownership filters, ordering, and DTO
conversion. Inject the shared database connection, not a semantic wrapper
around one query.

```rust
#[get("/users/", name = "user_list")]
pub async fn list_users(
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
) -> ViewResult<Response> {
    let users = User::objects()
        .filter(User::is_active.eq(true))
        .order_by(User::username.asc())
        .all(&*db)
        .await?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&users)?))
}

#[get("/users/by-email/{email}/", name = "user_by_email")]
pub async fn get_user_by_email(
    Path(email): Path<String>,
    #[inject] db: Depends<PrimaryDatabase, DatabaseConnection>,
) -> ViewResult<Response> {
    let user = User::objects()
        .filter(User::email.eq(email))
        .first(&*db)
        .await?
        .ok_or_else(|| AppError::NotFound("User not found".into()))?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(user))?))
}
```

### Injectable Services with Database Access

An injectable service is appropriate when it owns reusable domain behavior
beyond CRUD: transaction boundaries, cross-model orchestration, provider calls,
external side effects, stable business operations, or stable test override
points. The service may use direct ORM internally because its public contract is
the domain operation, not a repository lookup.

```rust
/// Use `#[injectable]` with `#[inject]` fields for automatic dependency resolution.
#[injectable(scope = "singleton")]
pub struct UserRegistrationService {
    #[inject]
    db: Depends<PrimaryDatabase, DatabaseConnection>,
    #[inject]
    email: EmailService,
}

impl UserRegistrationService {
    pub async fn register(&self, username: &str, email: &str) -> Result<User, ApiError> {
        if User::objects()
            .filter(User::email.eq(email))
            .first(&*self.db)
            .await?
            .is_some()
        {
            return Err(ApiError::conflict("Email already registered"));
        }

        let tx = self.db.begin().await?;
        let user = User::objects()
            .create(|u| {
                u.username = username.to_string();
                u.email = email.to_string();
            })
            .execute(&tx)
            .await?;
        AuditLog::objects()
            .create(|entry| {
                entry.user_id = user.id;
                entry.action = "user_registered".to_string();
            })
            .execute(&tx)
            .await?;
        tx.commit().await?;

        self.email.send_welcome(&user).await?;
        Ok(user)
    }
}
```
