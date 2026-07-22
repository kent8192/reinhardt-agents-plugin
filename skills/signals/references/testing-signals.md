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
use reinhardt::core::signals::{SignalSpy, post_save};

#[rstest]
#[tokio::test]
async fn test_post_save_triggers_receiver() {
    // Arrange
    let spy = SignalSpy::<Product>::new();
    let signal = post_save::<Product>();
    signal.add_middleware(spy.clone());

    // Act
    signal.send(product).await.unwrap();

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

## Testing Durable Job Queues (0.4.x)

`ImmediateBackend` and `DummyBackend` test ordinary `TaskQueue` behavior; they
do not prove persistence, claims, or lifecycle events. Test durable jobs with a
real `SqliteDurableJobStore` and one focused lifecycle per test:

```rust
use reinhardt::tasks::{
    DurableQueue, JobEventKind, JobSpec, JobState, SqliteDurableJobStore,
};
use rstest::*;
use serde_json::json;

#[rstest]
#[tokio::test]
async fn durable_job_records_lifecycle_events() {
    // Arrange
    let store = SqliteDurableJobStore::new("sqlite::memory:").await.unwrap();
    let queue = DurableQueue::new(store);
    let queued = queue.enqueue(JobSpec::new("send_email")).await.unwrap();

    // Act
    let claim = queue.claim_next().await.unwrap().unwrap();
    let completed = queue.succeed(claim, &json!({"sent": true})).await.unwrap();
    let events = queue.events(queued.id).await.unwrap();

    // Assert
    assert_eq!(completed.state, JobState::Succeeded);
    assert_eq!(events.len(), 3);
    assert_eq!(events[0].kind, JobEventKind::Enqueued);
    assert_eq!(events[1].kind, JobEventKind::Claimed);
    assert_eq!(events[2].kind, JobEventKind::Succeeded);
}
```

Cover these durable-specific contracts:

1. `Queued` → `Running` → terminal state, returned `JobSnapshot`, and ordered events
2. Retry scheduling and exhaustion, including `retry_after` and attempt count
3. Queued and running cancellation; a running cancellation request is a flag, not an immediate terminal state
4. Lease renewal, expired-claim recovery, and stale-claim completion conflicts
5. Restart persistence by creating a new queue over the same file-backed store

For isolated tests, `SqliteDurableJobStore::new("sqlite::memory:")` creates the
store safely. When constructing from a pool, do not use a private in-memory
SQLite pool with multiple connections; use a shared-memory or file-backed store
instead.

---

## Test Backend for Ordinary Tasks

Use `DummyBackend` or `ImmediateBackend` only when the unit test needs a
successful ordinary-queue enqueue without a real broker:

```rust
// In test setup
let backend = DummyBackend::new();
let queue = TaskQueue::new();
let _task_id = queue.enqueue(Box::new(task), &backend).await?;
```

Both built-in backends discard the supplied task and return an ID; the current
`ImmediateBackend` does not invoke `TaskExecutor` or retain work for later
assertions. Test task execution by calling `TaskExecutor::execute` directly,
and use a custom `TaskBackend` test double when an assertion needs to inspect
the enqueued task or backend state.

For an equivalent no-op backend in a focused enqueue test:

```rust
let backend = ImmediateBackend::new();
let queue = TaskQueue::new();
let _task_id = queue.enqueue(Box::new(task), &backend).await?;
```

---

## Rules for Signal/Task Tests

1. **ALWAYS test idempotency** — call the receiver/task twice
2. **Use `#[rstest]`** — never plain `#[test]`
3. **AAA pattern** with standard labels
4. **Mock external dependencies** — don't send real emails/webhooks in tests
5. **Test error paths** — not found, already processed, network failure
6. **Use `ImmediateBackend` or `DummyBackend` only for ordinary enqueue acceptance** — neither executes nor captures tasks; use a custom backend when behavior must be asserted
7. **Use `SqliteDurableJobStore` for durable jobs** — ordinary backends cannot prove durable persistence or lifecycle transitions
