# Testing Signals and Tasks

Patterns for testing signal receivers and background tasks in reinhardt.

---

## Testing Signal Receivers

### Principle

Test receivers in isolation — mock dependencies, verify behavior, don't rely on the full signal dispatch chain.

### Basic Receiver Test

```rust
use rstest::*;

#[rstest]
#[tokio::test]
async fn test_order_confirmation_receiver() {
    // Arrange
    let order_id = Uuid::new_v4();
    let mock_repo = Arc::new(MockOrderRepo::new());
    mock_repo.expect_get()
        .returning(move |id| Ok(OrderDto { id, notification_sent: false, /* ... */ }));
    mock_repo.expect_mark_notified()
        .returning(|_| Ok(()));

    let task = SendOrderConfirmation::new(order_id);

    // Act
    let result = task.execute().await;

    // Assert
    assert!(result.is_ok());
}
```

### Testing Idempotency

Every receiver/task test MUST verify idempotency — call `execute()` twice and verify it succeeds both times without duplicating side-effects:

```rust
#[rstest]
#[tokio::test]
async fn test_order_confirmation_is_idempotent() {
    // Arrange
    let order_id = Uuid::new_v4();
    let call_count = Arc::new(AtomicU32::new(0));
    let count_clone = call_count.clone();

    let mock_repo = Arc::new(MockOrderRepo::new());
    mock_repo.expect_get()
        .returning(move |id| {
            let sent = count_clone.load(Ordering::SeqCst) > 0;
            Ok(OrderDto { id, notification_sent: sent, /* ... */ })
        });
    mock_repo.expect_mark_notified()
        .returning(move |_| {
            call_count.fetch_add(1, Ordering::SeqCst);
            Ok(())
        });

    let task = SendOrderConfirmation::new(order_id);

    // Act — execute twice
    let result1 = task.execute().await;
    let result2 = task.execute().await;

    // Assert — both succeed, side-effect runs only once
    assert!(result1.is_ok());
    assert!(result2.is_ok());
}
```

### Testing Signal Connection

To verify a signal actually triggers the receiver, use `SignalSpy`:

```rust
use reinhardt::signals::middleware::SignalSpy;

#[rstest]
#[tokio::test]
async fn test_post_save_triggers_receiver() {
    // Arrange
    let spy = SignalSpy::new();
    let signal = post_save::<Product>();
    // Connect spy as middleware
    // ... (see middleware module docs)

    // Act
    signal.send(Arc::new(product)).await;

    // Assert
    assert_eq!(spy.call_count(), 1);
}
```

---

## Testing Background Tasks

### Unit Test (Task Logic)

```rust
#[rstest]
#[tokio::test]
async fn test_task_execution() {
    // Arrange
    let task = MyTask::new(/* params */);

    // Act
    let result = task.execute().await;

    // Assert
    assert!(result.is_ok());
}
```

### Testing Task Error Handling

```rust
#[rstest]
#[tokio::test]
async fn test_task_handles_not_found() {
    // Arrange
    let task = SendOrderConfirmation::new(Uuid::new_v4()); // Nonexistent order

    // Act
    let result = task.execute().await;

    // Assert
    assert!(matches!(result, Err(TaskError::ExecutionFailed(_))));
}
```

### Testing with Real DB (Integration)

For integration tests that verify the full signal → task flow with a real database, use TestContainers:

```rust
#[rstest]
#[tokio::test]
async fn test_order_creation_enqueues_task(
    #[future] shared_db_pool: Arc<DatabasePool>,
    order_table: (),
) {
    // Arrange
    let db = shared_db_pool.await;
    let service = OrderService::new(db.clone());
    let input = CreateOrderInput { /* ... */ };

    // Act
    let order = service.create_order(input).await.unwrap();

    // Assert — verify task was enqueued
    // (implementation depends on task backend — use ImmediateBackend for testing)
}
```

---

## Test Backend for Tasks

Use `ImmediateBackend` in tests to execute tasks synchronously:

```rust
// In test setup
let backend = ImmediateBackend::new();
let queue = TaskQueue::new(backend);
```

Or use `DummyBackend` to capture enqueued tasks without executing:

```rust
let backend = DummyBackend::new();
let queue = TaskQueue::new(backend);
// ... enqueue tasks ...
// Assert on what was enqueued
```

---

## Rules for Signal/Task Tests

1. **ALWAYS test idempotency** — call the receiver/task twice
2. **Use `#[rstest]`** — never plain `#[test]`
3. **AAA pattern** with standard labels
4. **Mock external dependencies** — don't send real emails/webhooks in tests
5. **Test error paths** — not found, already processed, network failure
6. **Use `ImmediateBackend` or `DummyBackend`** — never connect to real Redis/SQS in unit tests
