# Service Error to HTTP Response Mapping

Standard conventions for mapping domain/service errors to HTTP responses in reinhardt applications.

---

## Principle

Services raise domain-specific errors. The API layer maps these to HTTP responses **centrally**, not inside each view function. This keeps services free of HTTP concerns.

## Standard Error Mapping

| Service Error | HTTP Status | Response Body |
|---|---|---|
| `NotFound(String)` | 404 Not Found | `{"detail": "<message>"}` |
| `ValidationError(String)` | 400 Bad Request | `{"detail": "<message>"}` |
| `PermissionDenied(String)` | 403 Forbidden | `{"detail": "<message>"}` |
| `Conflict(String)` | 409 Conflict | `{"detail": "<message>"}` |
| `Unauthorized(String)` | 401 Unauthorized | `{"detail": "<message>"}` |
| `Framework(reinhardt::Error)` | Category-dependent; otherwise 500 | Generic body for internal failures |

## Implementation Pattern

Define a central application error type:

```rust
use reinhardt::rest::prelude::*;
use reinhardt::core::exception::DatabaseErrorKind;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    NotFound(String),

    #[error("{0}")]
    ValidationError(String),

    #[error("{0}")]
    PermissionDenied(String),

    #[error("{0}")]
    Conflict(String),

    #[error("{0}")]
    Unauthorized(String),

    #[error(transparent)]
    Framework(#[from] reinhardt::Error),
}

impl ResponseError for AppError {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::NotFound(_) => StatusCode::NOT_FOUND,
            Self::ValidationError(_) => StatusCode::BAD_REQUEST,
            Self::PermissionDenied(_) => StatusCode::FORBIDDEN,
            Self::Conflict(_) => StatusCode::CONFLICT,
            Self::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            Self::Framework(error) => match error.database_kind() {
                Some(DatabaseErrorKind::UniqueViolation)
                | Some(DatabaseErrorKind::ForeignKeyViolation) => StatusCode::CONFLICT,
                Some(DatabaseErrorKind::NotNullViolation)
                | Some(DatabaseErrorKind::CheckViolation) => StatusCode::BAD_REQUEST,
                Some(DatabaseErrorKind::Connection)
                | Some(DatabaseErrorKind::Timeout) => StatusCode::SERVICE_UNAVAILABLE,
                Some(_) | None => StatusCode::INTERNAL_SERVER_ERROR,
            },
        }
    }

    fn error_response(&self) -> HttpResponse {
        let detail = match self {
            Self::Framework(_) => "Internal server error".to_string(),
            other => other.to_string(),
        };
        HttpResponse::build(self.status_code())
            .json(serde_json::json!({"detail": detail}))
    }
}
```

## Rules

- **NEVER** expose raw framework or database diagnostics to clients — use a generic message for internal failures
- **NEVER** construct HTTP responses inside service methods
- **ALWAYS** define `AppError` once per project, not per app
- Services use `AppError` variants; views return `Result<T, AppError>`
- In 0.4.x, preserve repository-owned framework errors with a named `#[from] reinhardt::Error` variant; do not expose `anyhow::Error` in application/framework boundaries
- Match portable `database_kind()` categories first. Treat optional vendor codes as diagnostics, not cross-database control flow
- Conversion traits (`From<OrmError>`, `From<AuthError>`) centralize ORM/auth error mapping

## Testing Error Mapping

```rust
#[rstest]
#[tokio::test]
async fn test_not_found_returns_404(#[future] api_client: APIClient) {
    // Arrange
    let client = api_client.await;
    let nonexistent_id = Uuid::new_v4();

    // Act
    let response = client.get(&format!("/products/{nonexistent_id}")).await;

    // Assert
    assert_eq!(response.status(), 404);
    let json = response.json::<serde_json::Value>().await;
    assert!(json["detail"].is_string());
}
```
