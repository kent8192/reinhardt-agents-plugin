# Signal Types Reference

All signal types available in `reinhardt-core::signals`.

---

## Model Signals

Triggered during ORM model lifecycle events. Generic over the model type `T`.

| Signal | Function | Trigger | Parameters |
|--------|----------|---------|------------|
| Pre-save | `pre_save::<T>()` | Before a model instance is saved | `Arc<T>` |
| Post-save | `post_save::<T>()` | After a model instance is saved | `Arc<T>` |
| Pre-delete | `pre_delete::<T>()` | Before a model instance is deleted | `Arc<T>` |
| Post-delete | `post_delete::<T>()` | After a model instance is deleted | `Arc<T>` |
| Pre-init | `pre_init::<T>()` | At model initialization start | `Arc<PreInitEvent>` |
| Post-init | `post_init::<T>()` | At model initialization end | `Arc<PostInitEvent>` |
| M2M changed | `m2m_changed::<T, U>()` | Many-to-many relationship modified | `Arc<M2MChangeEvent>` |
| Class prepared | `class_prepared()` | When model class is prepared | `Arc<ClassPreparedEvent>` |

### M2MAction Variants

The `M2MChangeEvent` includes an `M2MAction` enum:

- `PreAdd` — before adding relations
- `PostAdd` — after adding relations
- `PreRemove` — before removing relations
- `PostRemove` — after removing relations
- `PreClear` — before clearing all relations
- `PostClear` — after clearing all relations

---

## Database Events

Low-level database operation signals. Use `DbEvent` as the signal parameter.

| Signal | Function | Trigger |
|--------|----------|---------|
| Before insert | `before_insert()` | Before INSERT query |
| After insert | `after_insert()` | After INSERT query |
| Before update | `before_update()` | Before UPDATE query |
| After update | `after_update()` | After UPDATE query |
| Before delete | `before_delete()` | Before DELETE query |
| After delete | `after_delete()` | After DELETE query |

---

## Transaction Signals

Lifecycle events for database transactions. Use `TransactionContext` as the parameter.

| Signal | Function | Trigger |
|--------|----------|---------|
| Begin | `transaction::on_begin()` | Transaction started |
| Commit | `transaction::on_commit()` | Transaction committed |
| Rollback | `transaction::on_rollback()` | Transaction rolled back |
| Savepoint | `transaction::on_savepoint()` | Savepoint created |
| Savepoint release | `transaction::on_savepoint_release()` | Savepoint released |

### TransactionContext Fields

```rust
pub struct TransactionContext {
    pub transaction_id: String,
    pub savepoint_depth: usize,
    pub savepoint_name: Option<String>,
    pub is_nested: bool,
}
```

---

## Request Signals

HTTP request lifecycle events.

| Signal | Function | Parameter Type |
|--------|----------|----------------|
| Request started | `request_started()` | `RequestStartedEvent` |
| Request finished | `request_finished()` | `RequestFinishedEvent` |
| Request exception | `got_request_exception()` | `GotRequestExceptionEvent` |

---

## Management Signals

| Signal | Function | Parameter Type |
|--------|----------|----------------|
| Setting changed | `setting_changed()` | `SettingChangedEvent` |
| Pre-migrate | `pre_migrate()` | `MigrationEvent` |
| Post-migrate | `post_migrate()` | `MigrationEvent` |

---

## Connecting Receivers

Use the `connect_receiver!` macro for all signal connections:

```rust
use reinhardt::signals::{post_save, connect_receiver};

// Basic connection
connect_receiver!(post_save::<Product>(), my_receiver);

// With priority (lower = earlier execution)
connect_receiver!(post_save::<Product>(), my_receiver, priority = 10);

// With dispatch_uid for deduplication
connect_receiver!(post_save::<Product>(), my_receiver, dispatch_uid = "product_notify");

// With sender filtering
connect_receiver!(post_save::<Product>(), my_receiver, sender = Product);

// All options combined
connect_receiver!(
    post_save::<Product>(),
    my_receiver,
    sender = Product,
    dispatch_uid = "product_notify",
    priority = 10
);
```

### Receiver Function Signature

`connect_receiver!` passes the signal payload to its receiver.

```rust
async fn my_receiver(instance: Arc<Product>) -> Result<(), SignalError> {
    // Handle the signal
    Ok(())
}
```

---

## Synchronous Signals

For non-async contexts, use `SyncSignal`:

```rust
use reinhardt::signals::dispatch::SyncSignal;

let signal = SyncSignal::new();
signal.connect(Arc::new(|sender, kwargs| {
    // Handle synchronously
    "ok".to_string()
}), None, Some("my_uid".to_string())).unwrap();

let results = signal.send(None, &HashMap::new());
```

---

## Advanced Features

| Feature | Module | Purpose |
|---------|--------|---------|
| Batching | `signals::batching` | Group multiple signal sends |
| Throttling | `signals::throttling` | Rate-limit signal firing |
| DLQ | `signals::dlq` | Dead letter queue for failed handlers |
| History | `signals::history` | Track signal execution history |
| Replay | `signals::replay` | Replay past signals |
| Profiler | `signals::profiler` | Performance profiling |
| Middleware | `signals::middleware` | Intercept/transform signals |
| Debugger | `signals::debugger` | Debug signal flows |
