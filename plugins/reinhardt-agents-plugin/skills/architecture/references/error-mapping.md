# Service Error to HTTP Response Mapping

Services return application errors. Map them centrally at the HTTP boundary.
The following pattern uses the 0.4.0-alpha.20 `Response` API; Reinhardt does
not provide a `ResponseError` trait, `HttpResponse::build`, or a
`rest::prelude` module.

## Application Error Adapter

```rust
use hyper::StatusCode;
use reinhardt::{Error, http::Response};
use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    Validation(String),
    #[error("{0}")]
    PermissionDenied(String),
    #[error("{0}")]
    Conflict(String),
    #[error("{0}")]
    Unauthorized(String),
    #[error(transparent)]
    Framework(#[from] Error),
}

impl AppError {
    pub fn status_code(&self) -> StatusCode {
        match self {
            Self::NotFound(_) => StatusCode::NOT_FOUND,
            Self::Validation(_) => StatusCode::BAD_REQUEST,
            Self::PermissionDenied(_) => StatusCode::FORBIDDEN,
            Self::Conflict(_) => StatusCode::CONFLICT,
            Self::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            Self::Framework(error) => StatusCode::from_u16(error.status_code())
                .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
        }
    }

    pub fn error_response(&self) -> reinhardt::Result<Response> {
        let detail = match self {
            Self::Framework(_) => match self.status_code() {
                StatusCode::BAD_REQUEST => "Invalid request",
                StatusCode::UNAUTHORIZED => "Authentication required",
                StatusCode::FORBIDDEN => "Permission denied",
                StatusCode::NOT_FOUND => "Resource not found",
                StatusCode::CONFLICT => "Request conflict",
                StatusCode::SERVICE_UNAVAILABLE => "Service unavailable",
                _ => "Internal server error",
            },
            Self::NotFound(message)
            | Self::Validation(message)
            | Self::PermissionDenied(message)
            | Self::Conflict(message)
            | Self::Unauthorized(message) => message,
        };
        Response::new(self.status_code())
            .with_json(&serde_json::json!({ "detail": detail }))
    }
}

pub fn http_result<T: Serialize>(
    result: Result<T, AppError>,
    success_status: StatusCode,
) -> reinhardt::Result<Response> {
    match result {
        Ok(value) => Response::new(success_status).with_json(&value),
        Err(error) => error.error_response(),
    }
}
```

Declare `hyper`, `serde`, `serde_json`, and `thiserror` in the
application manifest for these imports. A handler returning
`ViewResult<Response>` can call `http_result(operation.await, StatusCode::OK)`.
This adapter is application-owned; a service returning `Result<T, AppError>`
does not automatically register a custom HTTP error handler.

Keep domain messages safe for clients. Match portable `database_kind()`
categories when mapping persistence failures, preserve the original framework
error for diagnostics, and return generic text for internal causes.

## Testing Error Mapping

```rust
#[rstest]
#[tokio::test]
async fn test_not_found_returns_404(api_client: APIClient) {
    // Arrange
    let nonexistent_id = Uuid::new_v4();

    // Act
    let response = api_client
        .get(&format!("/products/{nonexistent_id}"))
        .await
        .unwrap();

    // Assert
    assert_eq!(response.status_code(), 404);
    let body = response.json::<serde_json::Value>().unwrap();
    assert_eq!(body["detail"], "Product not found");
}
```

Use the exact application's safe message in the assertion. Also exercise an
internal framework error and assert the complete generic response body so
database or authentication diagnostics cannot leak.
