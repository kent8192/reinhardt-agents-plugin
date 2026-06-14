---
name: signals
description: Use when working with reinhardt signals and background tasks - covers model signals, transaction-aware signals, reliable async side-effects, and task queue integration
versions: ["0.1.x", "0.2.0"]
---

# Reinhardt Signals & Async Side-Effects

Guide developers through using reinhardt's signal system (`reinhardt-core::signals`) and task system (`reinhardt-tasks`) for event-driven architecture and reliable async processing.

## When to Use

- User adds post-save/post-delete side-effects
- User implements background job processing
- User needs transaction-aware event handling
- User mentions: "signal", "post_save", "pre_delete", "side-effect", "async task", "background job", "event", "notification", "webhook", "task queue", "reliable signal", "transaction-aware"

## Workflow

### Adding a Model Signal Receiver

1. **Choose signal type** — read `references/signal-types.md`
2. **Connect receiver** — use `connect_receiver!` macro
3. **Implement receiver** — async function following idempotency rules
4. **Test** — verify receiver behavior in isolation

### Reliable Async Side-Effect Pattern

For side-effects that must happen after a DB transaction commits:

1. **Understand the pattern** — read `references/reliable-pattern.md`
2. **Connect transaction-aware signal** — use `on_commit()` signal
3. **Enqueue task in receiver** — use `TaskQueue::enqueue()`
4. **Implement task** — `TaskExecutor` trait with idempotent `execute()`
5. **Test** — read `references/testing-signals.md`

### Background Task Processing

For standalone background jobs (not signal-triggered):

1. **Define task** — implement `Task` + `TaskExecutor` traits
2. **Configure queue** — `TaskQueue` with appropriate backend
3. **Enqueue** — `TaskQueue::enqueue(task).await`
4. **Monitor** — use `TaskMetrics` for observability

## Important Rules

- Signal arguments MUST be serializable — pass IDs, not model instances
- Receivers MUST be idempotent — they may execute more than once (at-least-once delivery)
- Receivers MUST NOT trigger other signals — no cascading chains
- ALWAYS set `dispatch_uid` on `connect_receiver!` for deduplication
- Use transaction-aware signals (`on_commit`) for post-commit side-effects, not `post_save` directly
- Test receivers in isolation with mocked dependencies
- ALL code comments must be in English

## Cross-Domain References

- Model definitions: `../modeling/references/model-patterns.md`
- DI for task services: `../dependency-injection/references/di-patterns.md`
- Testing patterns: `../testing/references/rstest-patterns.md`
- Architecture integration: `../architecture/references/layer-sequence.md`

## Dynamic References

For the latest API:

1. Read `reinhardt/crates/reinhardt-core/src/signals.rs` for signal types and `connect_receiver!` macro
2. Read `reinhardt/crates/reinhardt-core/src/signals/model_signals.rs` for pre/post save/delete
3. Read `reinhardt/crates/reinhardt-core/src/signals/transaction.rs` for transaction-aware signals
4. Read `reinhardt/crates/reinhardt-tasks/src/lib.rs` for task system types
5. Read `reinhardt/crates/reinhardt-tasks/src/task.rs` for `Task` and `TaskExecutor` traits
