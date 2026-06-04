# DI with Database and Auth Reference

## DatabaseConnection Injection

`DatabaseConnection` is automatically available as an injectable type when the database feature is enabled. It provides a connection from the pool for the current request.

```rust
use reinhardt::db::prelude::*;
use reinhardt::di::prelude::*;
use reinhardt::views::prelude::*;

#[get("/users/{id}/", name = "user_retrieve")]
pub async fn get_user(
    Path(id): Path<i64>,
    #[inject] db: Depends<DatabaseConnection>,
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
    #[inject] db: Depends<DatabaseConnection>,
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

## AuthUser Injection

`AuthUser<T>` extracts the authenticated user from the request. It reads the authentication token (JWT, session, etc.) and resolves the user model.

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

### Full User Model with AuthUser<T>

`AuthUser<T>` resolves the full user model from the auth token:

```rust
#[delete("/admin/users/{id}/", name = "admin_user_delete")]
pub async fn delete_user(
    Path(id): Path<i64>,
    #[inject] reinhardt::AuthUser(admin): reinhardt::AuthUser<User>,
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

Use `Option<AuthUser<T>>` for endpoints that work for both authenticated and anonymous users:

```rust
#[get("/posts/", name = "post_list")]
pub async fn list_posts(
    #[inject] auth: Option<reinhardt::AuthUser<User>>,
) -> ViewResult<Response> {
    let mut query = Post::objects().filter(Post::is_published.eq(true));

    // Authenticated users see their own drafts too
    if let Some(reinhardt::AuthUser(user)) = &auth {
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
    #[inject] session: Depends<Session>,
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
    #[inject] session: Depends<Session>,
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
    #[inject] db: Depends<DatabaseConnection>,
    #[inject] email_service: Depends<EmailService>,
    #[inject] session: Depends<Session>,
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

## Custom Repository Pattern with Injectable

Define repository types that encapsulate database access and inject them into handlers.

```rust
use reinhardt::db::prelude::*;
use reinhardt::di::prelude::*;
use async_trait::async_trait;
use std::sync::Arc;

/// Register as singleton via `#[injectable]` macro with `#[inject]` fields.
#[injectable(scope = Singleton)]
pub struct UserRepository {
    #[inject]
    pool: Depends<DatabaseConnection>,
}

impl UserRepository {
    pub async fn find_by_email(&self, email: &str) -> Result<Option<User>, QueryError> {
        User::objects()
            .filter(User::email.eq(email))
            .first(&*self.pool)
            .await
    }

    pub async fn find_active(&self) -> Result<Vec<User>, QueryError> {
        User::objects()
            .filter(User::is_active.eq(true))
            .order_by(User::username.asc())
            .all(&*self.pool)
            .await
    }

    pub async fn create(&self, username: &str, email: &str) -> Result<User, QueryError> {
        User::objects()
            .create(|u| {
                u.username = username.to_string();
                u.email = email.to_string();
            })
            .execute(&*self.pool)
            .await
    }

    pub async fn deactivate(&self, user_id: i64) -> Result<(), QueryError> {
        User::objects()
            .filter(User::id.eq(user_id))
            .update(User::is_active.set(false))
            .execute(&*self.pool)
            .await?;
        Ok(())
    }
}
```

### Using the Repository in Handlers

```rust
#[get("/users/", name = "user_list")]
pub async fn list_users(
    #[inject] user_repo: Depends<UserRepository>,
) -> ViewResult<Response> {
    let users = user_repo.find_active().await?;
    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&users)?))
}

#[get("/users/by-email/{email}/", name = "user_by_email")]
pub async fn find_by_email(
    Path(email): Path<String>,
    #[inject] user_repo: Depends<UserRepository>,
) -> ViewResult<Response> {
    let user = user_repo
        .find_by_email(&email)
        .await?
        .ok_or_else(|| AppError::NotFound("User not found".into()))?;

    Ok(Response::new(StatusCode::OK)
        .with_header("Content-Type", "application/json")
        .with_body(json::to_vec(&UserResponse::from(user))?))
}
```

### Service Layer on Top of Repository

```rust
/// Use `#[injectable]` with `#[inject]` fields for automatic dependency resolution.
#[injectable(scope = Singleton)]
pub struct UserService {
    #[inject]
    repo: Depends<UserRepository>,
    #[inject]
    email: Depends<EmailService>,
}

impl UserService {
    pub async fn register(&self, username: &str, email: &str) -> Result<User, ApiError> {
        // Check for duplicates
        if self.repo.find_by_email(email).await?.is_some() {
            return Err(ApiError::conflict("Email already registered"));
        }

        // Create user
        let user = self.repo.create(username, email).await?;

        // Send welcome email
        self.email.send_welcome(&user).await?;

        Ok(user)
    }
}
```
