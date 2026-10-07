# Testing Signals and Tasks

Test observable effects, inject the test doubles into the object under test,
and verify retries against the same repository state.

## Receiver and Task Logic

The following application example assumes an application-owned
`SendOrderConfirmation::new(order_id, repository)` constructor and a
`MockOrderRepo` generated from the application's repository trait.
`get` returns `Option<OrderDto>`; `OrderDto` has `id` and
`notification_sent` fields. `mark_notified` records delivery.
Import those application types, `TaskExecutor`, `Arc`, `Uuid`,
`AtomicU32` / `Ordering`, `mockall::predicate::eq`, and
`rstest::rstest` in the test module.

```rust
#[rstest]
#[tokio::test]
async fn order_confirmation_uses_the_injected_repository() {
    // Arrange
    let order_id = Uuid::now_v7();
    let mut repository = MockOrderRepo::new();
    repository.expect_get()
        .with(eq(order_id))
        .times(1)
        .returning(|id| Ok(Some(OrderDto { id, notification_sent: false })));
    repository.expect_mark_notified()
        .with(eq(order_id))
        .times(1)
        .returning(|_| Ok(()));
    let repository = Arc::new(repository);
    let task = SendOrderConfirmation::new(order_id, Arc::clone(&repository));

    // Act
    task.execute().await.unwrap();

    // Assert
    // Dropping the last mock owner verifies both exact call expectations.
    drop(task);
    drop(repository);
}
```

Construct the mutable mock before putting it in `Arc`. An unused mock does
not verify the task's behavior. Exact call expectations fail if the repository
is bypassed, the wrong order is used, or delivery is recorded twice.

### Idempotency for Retried Tasks

```rust
#[rstest]
#[tokio::test]
async fn order_confirmation_records_delivery_once() {
    // Arrange
    let order_id = Uuid::now_v7();
    let recorded = Arc::new(AtomicU32::new(0));
    let read_count = Arc::clone(&recorded);
    let write_count = Arc::clone(&recorded);
    let mut repository = MockOrderRepo::new();
    repository.expect_get()
        .with(eq(order_id))
        .times(2)
        .returning(move |id| Ok(Some(OrderDto {
            id,
            notification_sent: read_count.load(Ordering::SeqCst) > 0,
        })));
    repository.expect_mark_notified()
        .with(eq(order_id))
        .times(1)
        .returning(move |_| {
            write_count.fetch_add(1, Ordering::SeqCst);
            Ok(())
        });
    let task = SendOrderConfirmation::new(order_id, Arc::new(repository));

    // Act
    task.execute().await.unwrap();
    task.execute().await.unwrap();

    // Assert
    assert_eq!(recorded.load(Ordering::SeqCst), 1);
}
```

The application's implementation must read the injected repository and skip
already delivered orders. If delivery crosses a separate external system,
also verify its idempotency key or transaction/outbox contract; marking a
repository flag alone does not prove crash-safe delivery.

### Missing-Order Error

```rust
#[rstest]
#[tokio::test]
async fn order_confirmation_rejects_missing_orders() {
    // Arrange
    let order_id = Uuid::now_v7();
    let mut repository = MockOrderRepo::new();
    repository.expect_get().with(eq(order_id)).times(1).returning(|_| Ok(None));
    repository.expect_mark_notified().times(0);
    let task = SendOrderConfirmation::new(order_id, Arc::new(repository));

    // Act
    let error = task.execute().await.unwrap_err();

    // Assert
    match error {
        TaskError::ExecutionFailed(message) => assert_eq!(message, "Order not found"),
        other => panic!("Unexpected task error: {other}"),
    }
}
```

The exact error message belongs to this application contract; use the
application's actual message when adapting the example.

## Signal Dispatch

A fresh signal isolates middleware and connection state from other tests:

```rust
use reinhardt::core::signals::{Signal, SignalSpy};
use rstest::rstest;

#[rstest]
#[tokio::test]
async fn signal_dispatch_is_observed() {
    // Arrange
    let signal = Signal::<i32>::new_with_string("test_order_saved");
    let spy = SignalSpy::<i32>::new();
    signal.add_middleware(spy.clone());

    // Act
    signal.send(42).await.unwrap();

    // Assert
    assert_eq!(spy.call_count(), 1);
}
```

This verifies dispatch through middleware. To verify a receiver's business
effect, connect the receiver and assert its injected dependency's state.
Tests using the global `post_save::<T>()` registry must use
`#[serial(signals)]` and restore any registered connections/middleware;
prefer an owned signal for isolated tests.

## Persistent Enqueue Boundary

A real queue assertion verifies that accepted work exists with an initial
event. This is a queue boundary test; a full application integration test must
inject the same queue into the order flow, call that flow, and inspect the
resulting job and payload.

```rust
use reinhardt::tasks::{
    DurableQueue, JobEventKind, JobSpec, JobState, SqliteDurableJobStore,
};

#[rstest]
#[tokio::test]
async fn enqueue_records_pending_work() {
    // Arrange
    let store = SqliteDurableJobStore::new("sqlite::memory:").await.unwrap();
    let queue = DurableQueue::new(store);

    // Act
    let queued = queue.enqueue(JobSpec::new("send_email")).await.unwrap();
    let persisted = queue.status(queued.id).await.unwrap();
    let events = queue.events(queued.id).await.unwrap();

    // Assert
    assert_eq!(persisted.state, JobState::Queued);
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].kind, JobEventKind::Enqueued);
}
```

## Testing Durable Job Queues (0.4.x)

`ImmediateBackend` and `DummyBackend` test ordinary `TaskQueue` behavior; they
do not prove persistence, claims, or lifecycle events. Test durable jobs with a
real `SqliteDurableJobStore` and one focused lifecycle per test:

```rust
use reinhardt::tasks::{
    DurableQueue, JobEventKind, JobSpec, JobState, SqliteDurableJobStore,
};
use rstest::rstest;
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

1. **Test the retry contract** — idempotent receivers/tasks run twice against the same state; non-retryable tasks document and test their explicit policy
2. **Use `#[rstest]`** — never plain `#[test]`
3. **AAA pattern** with standard labels
4. **Mock external dependencies** — don't send real emails/webhooks in tests
5. **Test error paths** — not found, already processed, network failure
6. **Use `ImmediateBackend` or `DummyBackend` only for ordinary enqueue acceptance** — neither executes nor captures tasks; use a custom backend when behavior must be asserted
7. **Use `SqliteDurableJobStore` for durable jobs** — ordinary backends cannot prove durable persistence or lifecycle transitions
