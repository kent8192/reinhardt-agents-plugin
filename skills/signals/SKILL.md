---
name: signals
description: Use when working with reinhardt signals and background tasks - covers model signals, transaction-aware signals, reliable async side-effects, and task queue integration
versions: ["0.1.x", "0.2.x", "0.3.x", "0.4.x"]
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
3. **Enqueue task in receiver** — use the current `TaskQueue` API with the app-configured backend
4. **Implement task** — `TaskExecutor` trait with idempotent `execute()`
5. **Test** — read `references/testing-signals.md`

### Background Task Processing

For standalone jobs that do not need persisted lifecycle state or externally
queryable status:

1. **Define task** — implement `Task` + `TaskExecutor` traits
2. **Configure queue** — `TaskQueue` with appropriate backend
3. **Enqueue** — use the current `TaskQueue` API with the configured backend
4. **Monitor** — use `TaskMetrics` for observability

### Durable Job Processing (0.4.x)

Use the durable queue for work that must survive restarts, be retried or
cancelled, or expose progress to a polling/server-function UI:

1. **Enable features** — use facade feature `tasks-durable`; add `di` for
   server-function injection
2. **Configure storage** — create one long-lived `SqliteDurableJobStore` and
   `DurableQueue`; do not rebuild either per request
3. **Enqueue a spec** — create a `JobSpec`, then return its `JobSnapshot` from
   status APIs rather than exposing mutable storage records
4. **Process a claim** — workers call `claim_next`, retain the returned
   `JobClaim`, and complete it with `succeed`, `fail_retryable`, `fail_final`,
   or `cancel`
5. **Monitor lifecycle** — read `status` and ordered `events`; renew long
   claims before their lease expires

## Important Rules

- Signal arguments MUST be serializable — pass IDs, not model instances
- Receivers MUST be idempotent — they may execute more than once (at-least-once delivery)
- Receivers MUST NOT trigger other signals — no cascading chains
- ALWAYS set `dispatch_uid` on `connect_receiver!` for deduplication
- Use transaction-aware signals (`on_commit`) for post-commit side-effects, not `post_save` directly
- Test receivers in isolation with mocked dependencies
- ALL code comments must be in English
- For 0.3.x task/signal services registered through DI, use `#[injectable]` provider functions and keyed `FactoryOutput<K, T>` when the output type is not a unique dependency identity
- Keep shared signal/task modules cfg-clean when used by Pages apps; rely on documented 0.3 inert provider stubs rather than broad call-site `#[cfg]`
- Signal payloads should remain stable IDs or explicit DTOs; do not accidentally expose 0.3 `{Model}Info` relation-shaped payload changes as signal contracts
- For durable jobs, enqueue only after the domain transaction commits; durable enqueue is not automatically part of that transaction
- Treat `request_cancel` for a running durable job as cooperative: it records a cancellation request, while the worker or lease recovery performs the terminal transition
- Complete durable jobs only through the `JobClaim` returned by the atomic claim operation; do not reconstruct claims from an ID or status snapshot

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
6. For 0.4 durable jobs, read `reinhardt/crates/reinhardt-tasks/src/durable.rs`
7. Read `reinhardt/Cargo.toml` for facade feature wiring such as `tasks-durable`
