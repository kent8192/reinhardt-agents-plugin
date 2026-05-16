# Testing Guide for Reinhardt Pages

## 3-Layer Test Architecture

### Layer 1: Server Function Unit Tests

Direct testing of server functions without HTTP overhead.

```rust
use reinhardt::pages::testing::ServerFnTestContext;

#[tokio::test]
async fn test_get_user() {
    // Arrange
    let ctx = ServerFnTestContext::new(singleton)
        .with_database(pool)
        .build();

    // Act
    let result = get_user(1).await;

    // Assert
    assert!(result.is_ok());
    assert_eq!(result.unwrap().username, "alice");
}
```

### Layer 2: WASM Component Tests with MockServiceWorker

Test WASM components with MSW-style mocked HTTP responses. MockServiceWorker intercepts `window.fetch` at the WASM level.

```rust
use reinhardt::test::msw::{MockServiceWorker, MockResponse, rest};
use reinhardt::test::fixtures::wasm::msw::msw_worker;
use wasm_bindgen_test::*;
use rstest::*;

wasm_bindgen_test_configure!(run_in_browser);

#[rstest]
#[wasm_bindgen_test]
async fn test_user_list_component(#[future] msw_worker: MockServiceWorker) {
    // Arrange
    let worker = msw_worker.await;
    let users = vec![User { id: 1, username: "alice".into() }];
    worker.handle(rest::get("/api/users").respond(MockResponse::json(&users)));

    // Act: render component
    // ...

    // Assert
    worker.calls_to("/api/users").assert_called();
}
```

### Layer 3: End-to-End Tests

Full integration tests with real server and WASM frontend.

```rust
use reinhardt::pages::testing::e2e;
```

## MockServiceWorker API

### Setup & Lifecycle

```rust
use reinhardt::test::msw::{MockServiceWorker, UnhandledPolicy};

// Default: unhandled requests cause errors
let worker = MockServiceWorker::new();

// Or: unhandled requests pass through to real fetch
let worker = MockServiceWorker::with_policy(UnhandledPolicy::Passthrough);

// Start intercepting (overrides window.fetch)
worker.start().await;

// Stop intercepting (restores original window.fetch)
worker.stop().await;

// Clear handlers and recorded requests
worker.reset();

// Clear handlers only, keep recordings
worker.reset_handlers();

// Drop impl auto-restores fetch
```

### UnhandledPolicy

| Policy | Description |
|--------|-------------|
| `UnhandledPolicy::Error` | Default — rejected Promise with TypeError |
| `UnhandledPolicy::Passthrough` | Delegates to original `window.fetch` |
| `UnhandledPolicy::Warn` | `console.warn` + passthrough |

### REST Handlers

```rust
use reinhardt::test::msw::{rest, MockResponse};

// Fixed response
worker.handle(rest::get("/api/users").respond(MockResponse::json(&users)));
worker.handle(rest::post("/api/users").respond(MockResponse::json(&new_user)));
worker.handle(rest::put("/api/users/:id").respond(MockResponse::empty()));
worker.handle(rest::delete("/api/users/:id").respond(MockResponse::empty().with_status(204)));
worker.handle(rest::patch("/api/users/:id").respond(MockResponse::json(&updated)));

// Dynamic response
worker.handle(rest::get("/api/users/:id").respond_with(|req| {
    let id = req.params.get("id").unwrap();
    MockResponse::json(&User { id: id.parse().unwrap(), username: "alice".into() })
}));

// One-time response (consumed after first match)
worker.handle(rest::get("/api/users").once().respond(MockResponse::json(&users)));

// Delayed response
worker.handle(rest::get("/api/slow").delay(Duration::from_millis(500)).respond(MockResponse::json(&data)));

// Network error simulation
worker.handle(rest::get("/api/fail").network_error());
```

### MockResponse

```rust
use reinhardt::test::msw::MockResponse;

MockResponse::json(&data)            // Status 200, content-type: application/json
MockResponse::text("hello")          // Status 200, content-type: text/plain
MockResponse::empty()                // Status 200, empty body
    .with_status(404)                // Override status code
    .with_header("x-custom", "val") // Add header
```

### Type-Safe Server Function Mocking

```rust
// Mock a server function by its marker type
worker.handle_server_fn::<login::marker>(|args| {
    Ok(AuthResponse { success: true, user: Some(UserInfo { username: args.username }) })
});

// With DI context
use reinhardt::test::msw::TestContext;

let ctx = TestContext::new()
    .insert(MockDb { users: vec!["alice".into()] });

worker.handle_server_fn_with_context::<get_users::marker>(ctx, |args, ctx| {
    let db = ctx.get::<MockDb>();
    Ok(db.users.clone())
});
```

### Call Recording & Assertions

```rust
// Query calls by URL pattern
worker.calls_to("/api/users").assert_called();
worker.calls_to("/api/users").assert_not_called();
worker.calls_to("/api/users").assert_count(3);
worker.calls_to("/api/users").count();           // -> usize
worker.calls_to("/api/users").first();           // -> Option<RecordedRequest>
worker.calls_to("/api/users").last();            // -> Option<RecordedRequest>
worker.calls_to("/api/users").nth(1);            // -> Option<RecordedRequest>
worker.calls_to("/api/users").all();             // -> Vec<RecordedRequest>

// Type-safe server function call assertions
worker.calls_to_server_fn::<login::marker>().assert_called();
worker.calls_to_server_fn::<login::marker>().assert_count(1);
worker.calls_to_server_fn::<login::marker>().last_args();                    // -> Option<Args>
worker.calls_to_server_fn::<login::marker>().assert_called_with(&expected);  // Args: PartialEq + Debug

// All recorded calls
let all = worker.all_calls(); // -> Vec<RecordedRequest>
```

### rstest Fixtures

```rust
use reinhardt::test::fixtures::wasm::msw::{msw_worker, msw_worker_passthrough};

// Auto-started with UnhandledPolicy::Error
#[rstest]
#[wasm_bindgen_test]
async fn test_strict(#[future] msw_worker: MockServiceWorker) {
    let worker = msw_worker.await;
    // Unhandled requests will error
}

// Auto-started with UnhandledPolicy::Passthrough
#[rstest]
#[wasm_bindgen_test]
async fn test_lenient(#[future] msw_worker_passthrough: MockServiceWorker) {
    let worker = msw_worker_passthrough.await;
    // Unhandled requests pass through to real fetch
}
```

## Feature Flags for Testing

| Feature | Description |
|---------|-------------|
| `testing` | Core testing utilities |
| `msw` | MockServiceWorker + MockableServerFn trait |
| `debug-hooks` | Debug hooks (`use_debug_value`) |

```toml
# Cargo.toml
[dependencies]
reinhardt = { workspace = true, features = ["pages", "test", "msw"] }

[dev-dependencies]
wasm-bindgen-test = "0.3"
```

## Deprecated APIs

> **Since v0.1.0-rc.16**: The following APIs are deprecated. Use `MockServiceWorker` instead.

| Deprecated | Replacement |
|------------|-------------|
| `mock_server_fn(path, &data)` | `worker.handle_server_fn::<T>(...)` or `worker.handle(rest::post(...).respond(...))` |
| `mock_server_fn_error(path, status, msg)` | `worker.handle(rest::post(path).respond(MockResponse::text(msg).with_status(status)))` |
| `mock_server_fn_custom(path, response)` | `worker.handle(rest::post(path).respond(...))` |
| `MockFetch` | `MockServiceWorker` |
| `assert_server_fn_called(path)` | `worker.calls_to(path).assert_called()` |
| `assert_server_fn_not_called(path)` | `worker.calls_to(path).assert_not_called()` |
| `assert_server_fn_called_with(path, body)` | `worker.calls_to_server_fn::<T>().assert_called_with(&args)` |
| `assert_server_fn_call_count(path, n)` | `worker.calls_to(path).assert_count(n)` |
| `clear_mocks()` | `worker.reset()` (or Drop auto-cleanup) |

## cfg_aliases in Tests

Ensure `build.rs` is set up for `wasm`/`native` aliases (see routing-ssr.md). Both test targets use the same aliases.

## Testing Standards

- ALL tests MUST use `rstest` (per project standards)
- Follow AAA pattern: `// Arrange`, `// Act`, `// Assert`
- Server function unit tests: `#[tokio::test]` with rstest
- WASM component tests: `#[wasm_bindgen_test]` with rstest
- Use `MockServiceWorker` fixtures (`msw_worker`) — cleanup is automatic via Drop
- Use `reinhardt-query` for SQL in tests, NEVER raw SQL
