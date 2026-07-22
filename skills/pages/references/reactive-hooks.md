# Reactive System & Hooks Reference

## Core Primitives

### Signal

A reactive value with automatic dependency tracking.

```rust
use reinhardt::pages::prelude::*;

let count = Signal::new(0);

// Read value (registers dependency)
let value = count.get();

// Set value (notifies dependents)
count.set(5);

// Update in place
count.update(|n| *n += 1);
```

#### `Signal<T>: Send + Sync` on native (rc.25+)

Since v0.1.0-rc.25, `Signal<T>` uses `Arc<RwLock<T>>` on native targets so it
implements `Send + Sync`. On `wasm32` it stays `Rc<RefCell<T>>` to keep the
zero-cost reactive hot path on the SPA side.

This unblocks holding signals in DI-resolved types: `ClientRouter` (and
`UnifiedRouter` with the `client-router` feature) is now `Send + Sync`, so
`InjectionContext::resolve` accepts router newtypes that contain reactive
state. Cross-thread mutation is sound but does not notify subscribers
registered on another thread (the runtime remains `thread_local!`); SSR
reverse URL resolution only reads static metadata, so this is safe. (#4068)

### Effect

A side effect that reruns when dependencies change.

```rust
let count = Signal::new(0);
let name = Signal::new("Alice".to_string());

Effect::new(move || {
    println!("{}: count = {}", name.get(), count.get());
});
// Prints: "Alice: count = 0"

count.set(5);
// Prints: "Alice: count = 5"
```

### Memo

A cached derived computation.

```rust
let count = Signal::new(0);
let doubled = Memo::new(move || count.get() * 2);

assert_eq!(doubled.get(), 0);
count.set(5);
assert_eq!(doubled.get(), 10);
```

## Context System

Share data through the component tree without prop drilling.

```rust
use reinhardt::pages::prelude::*;

// Provide context
let theme = Signal::new("dark".to_string());
provide_context("theme", theme.clone());

// Consume context (anywhere in the subtree)
let theme: Signal<String> = get_context("theme").unwrap();
```

| Function | Description |
|----------|-------------|
| `create_context(key, value)` | Create a new context |
| `provide_context(key, value)` | Provide a context value |
| `get_context::<T>(key)` | Get a context value |
| `remove_context(key)` | Remove a context |

## Hooks API

### State Hooks

| Hook | Signature | Description |
|------|-----------|-------------|
| `use_state` | `use_state(initial: T) -> (Signal<T>, SetState<T>)` | Local reactive state (takes value, not closure) |
| `use_reducer` | `use_reducer(reducer, init) -> (Signal<S>, Dispatch<A>)` | State with reducer pattern |
| `use_shared_state` | `use_shared_state(initial: T) -> (SharedSignal<T>, SharedSetState<T>)` | Shared state across components |
| `use_optimistic` | `use_optimistic(initial: T) -> OptimisticState<T>` | Optimistic UI updates |

```rust
// use_state takes a value directly (NOT a closure)
let (count, set_count) = use_state(0);
set_count(5);
```

### Effect Hooks

| Hook | Signature | Description |
|------|-----------|-------------|
| `use_effect` | `use_effect(closure, deps)` | Side effect (async-safe) |
| `use_layout_effect` | `use_layout_effect(closure, deps)` | Synchronous effect before paint |

```rust
use_effect(
    {
        let count = count.clone();
        move || {
            // Runs when dependencies change
            log!("Count is: {}", count.get());
            None::<fn()>
        }
    },
    (count.clone(),),
);
```

**When to use `use_layout_effect`**: DOM measurements, preventing visual flicker.
**When to use `use_effect`** (preferred): Data fetching, subscriptions, logging.

### Derived Value Hooks

| Hook | Signature | Description |
|------|-----------|-------------|
| `use_memo` | `use_memo(closure, deps) -> Memo<T>` | Cached computation |
| `use_callback` | `use_callback(closure, deps) -> Callback<EventArg, ()>` | Stable event callback |
| `use_callback_with` | `use_callback_with(closure, deps) -> Callback<Args, Ret>` | Generic stable callback |
| `use_deferred_value` | `use_deferred_value(signal) -> Signal<T>` | Deferred update for low-priority UI |

### Ref and Identity Hooks

| Hook | Signature | Description |
|------|-----------|-------------|
| `use_ref` | `use_ref(init) -> Ref<T>` | Mutable reference (no re-render on change) |
| `use_id` | `use_id() -> String` | Unique ID for accessibility |
| `use_id_with_prefix` | `use_id_with_prefix(prefix) -> String` | Unique ID with custom prefix |

### Async Hooks

| Hook | Signature | Description |
|------|-----------|-------------|
| `use_transition` | `use_transition() -> TransitionState` | Non-blocking state updates |
| `use_action` | `use_action(action_fn) -> Action<T, E>` | Async action with loading/error state |
| `use_action_state` | *(deprecated)* | Use `use_action` instead |

```rust
let save_action = use_action(|data: FormData| async move {
    save_to_server(data).await
});

// Trigger
save_action.dispatch(form_data);

// Check state
match save_action.phase().get() {
    ActionPhase::Idle => { /* ready */ },
    ActionPhase::Pending => { /* loading */ },
    ActionPhase::Resolved(result) => { /* done */ },
}
```

### Async UI Handler Patterns

Use `use_action` for button/form mutations whose pending, success, and error
state should be visible in the component tree. Do not fire an async task and
drop its result from a route component; the `Action` phase is the UI contract
that disables controls, renders errors, and prevents duplicate submissions.

Use `use_resource` for async reads and derived text, including labels,
diagnostics, previews, or server-translated copy that depends on the current
route, selected version, locale, or loaded DTO. Prefer a stable fallback while
the `Resource` is loading or failed.

Use `use_callback` / `use_callback_with` for event handlers that dispatch the
current form values, selected rows, selected versions, or route parameters into
an `Action`. Avoid fixture IDs such as `Uuid::nil()`, `"sample-project"`, or
hardcoded version IDs once the route has real server state available.

```rust
let save_action = use_action(|input: SaveSettingsRequest| async move {
    save_project_settings(input).await
});

let save_click = use_callback(
    {
        let save_action = save_action.clone();
        let project_id = project_id.clone();
        let form = form.clone();
        move |_| {
            save_action.dispatch(SaveSettingsRequest {
                project_id: project_id.get(),
                title: form.title(),
                idea: form.idea(),
                model: form.model(),
            });
        }
    },
    (save_action.clone(), project_id.clone(), form.clone()),
);
```

Keep `spawn_local` for low-level browser integration where no hook owns the
result, such as registering a raw DOM observer or adapting a JavaScript API.
If the result affects app state, prefer `Action` or `Resource` instead.

### External Integration Hooks

| Hook | Signature | Description |
|------|-----------|-------------|
| `use_sync_external_store` | `use_sync_external_store(subscribe, get_snapshot)` | Integrate external stores |
| `use_sync_external_store_with_server` | `...(subscribe, get_snapshot, get_server_snapshot)` | SSR-compatible variant |
| `use_websocket` | `use_websocket(url, options) -> WebSocketHandle` | Reactive WebSocket |
| `use_context` | `use_context(ctx: &Context<T>) -> Option<T>` | Read context value (takes `&Context<T>`, returns `Option`) |

### Debug Hooks

| Hook | Description |
|------|-------------|
| `use_debug_value` | Custom label in dev tools (requires `debug-hooks` feature) |

## Resource (WASM Only)

Async data loading with reactive dependencies.

```rust
#[cfg(wasm)]
{
    let user_id = Signal::new(1);
    let user = use_resource(
        {
            let user_id = user_id.clone();
            move || {
                let id = user_id.get();
                async move { fetch_user(id).await }
            }
        },
        (user_id.clone(),),
    );

    // Mount-only loading
    let current_user = use_resource(fetch_current_user, ());

    // Check state
    match user.state().get() {
        ResourceState::Loading => { /* show spinner */ },
        ResourceState::Ready(data) => { /* render data */ },
        ResourceState::Error(err) => { /* show error */ },
    }
}
```

## Platform Event Type

Platform-agnostic event type for cross-target code:

```rust
use reinhardt::pages::prelude::*;

fn handle_click(_event: Event) {
    // Works on both WASM and native
}
```

## Thread-Local State (Recommended Pattern)

For global app state, use `thread_local!` with `RefCell` instead of hooks:

```rust
use std::cell::RefCell;

pub struct AppState {
    pub is_loading: bool,
}

thread_local! {
    static APP_STATE: RefCell<AppState> = RefCell::new(AppState { is_loading: true });
}

pub fn with_app_state<F, R>(f: F) -> R
where
    F: FnOnce(&AppState) -> R,
{
    APP_STATE.with(|s| f(&s.borrow()))
}

pub fn with_app_state_mut<F, R>(f: F) -> R
where
    F: FnOnce(&mut AppState) -> R,
{
    APP_STATE.with(|s| f(&mut s.borrow_mut()))
}
```

## Auth State (Built-in)

Use the built-in reactive auth state for authentication:

```rust
use reinhardt::pages::auth::{AuthData, auth_state};

// Update auth state (e.g., after login)
auth_state().update(AuthData {
    is_authenticated: true,
    username: Some("alice".to_string()),
    email: Some("alice@example.com".to_string()),
    ..Default::default()
});
```

## Effect-Based Reactive Rendering

Use `Effect` to reactively re-render when Signals change:

```rust
use reinhardt::pages::reactive::Effect;

let path_signal = router::with_router(|r| r.current_path().clone());
let effect = Effect::new(move || {
    let path = path_signal.get();  // Subscribe to path changes
    let page = router::with_router(|r| r.render_current());
    app_el.set_inner_html(&page.render_to_string());
});
std::mem::forget(effect);  // Keep alive for page lifetime
```

## watch Blocks vs Hooks

The `page!` macro's `watch` block provides **reactive rendering** that automatically re-renders when Signal dependencies change. This is distinct from hooks.

### When to Use watch (Not Hooks)

| Scenario | Use | Not |
|----------|-----|-----|
| Conditionally show/hide elements based on Signal | `watch { if signal.get() { ... } }` | `use_effect` |
| Render different views based on state | `watch { match state.get() { ... } }` | `use_effect` + manual DOM |
| Reactive list rendering | `watch { for item in items.get() { ... } }` | `use_effect` |

### When Hooks Are Still Needed

| Scenario | Use |
|----------|-----|
| Side effects (API calls, logging, subscriptions) | `use_effect` |
| Expensive cached computations | `use_memo` |
| Async actions with loading/error state | `use_action` |
| State management | `use_state`, `use_reducer` |
| DOM refs and measurements | `use_ref`, `use_layout_effect` |

For forms, use `form!` for a hand-defined static schema, or (in
0.4.0-alpha.1+) use a `ClientForm`-derived companion when a supported DTO is the
canonical request contract. Both use `use_form` for current values,
dirty/touched markers, validation results, submit phase, and reset/submit
actions. For a generated client-form submit, let the form runtime own its
validation and async lifecycle; bind pending, success, and error UI to form
state instead of recreating it with a separate action. Use Signals, hooks, and
`watch {}` for surrounding display state, not as a second implementation of the
form runtime. See [DTO-Derived Client Form Bindings](client-form-bindings.md).

### Example: watch Replaces Manual Effect Rendering

```rust
// AVOID: using Effect for conditional rendering
let (show, _) = use_state(Signal::new(false));
use_effect(move || {
    if show.get() { /* manually update DOM */ }
});

// PREFER: watch block in page! macro
page!(|show: Signal<bool>| {
    div {
        watch {
            if show.get() {
                div { class: "alert", "Visible!" }
            }
        }
    }
})(show)
```

### watch Best Practices

- **Pass Signals directly** to `page!` — don't extract values before the macro
- **Clone Signals freely** — `Signal::clone()` is cheap (Rc-based)
- **One expression per watch** — each block must contain exactly one `if`, `match`, or `for`
- **Don't nest watch blocks** — use multiple sibling watch blocks instead

## Architecture Notes

- **Fine-grained reactivity**: Only DOM nodes depending on changed Signals update (not entire component trees)
- **Pull-based model**: Signals track dependencies automatically via `.get()` calls
- **Batching**: Multiple Signal changes batch into a single update cycle via micro-tasks
- **Memory management**: All reactive nodes auto-cleanup when dropped
- **`std::mem::forget`**: Use for Effects that should live for the entire page lifetime (e.g., routing)
- **watch compiles to `Page::reactive()`**: The reactive closure is tracked by the runtime and re-evaluated on Signal changes

## Version Differences (0.2.x)

### Effect Hooks

In 0.2.x, `use_effect` and `use_layout_effect` now take an **explicit dependencies value** as the second argument instead of relying on implicit dependency tracking via `.get()` calls:

```rust
// 0.1.x — implicit dependency tracking
use_effect(move || {
    log!("count changed: {}", count.get());
});

// 0.2.x — explicit dependency tuples
use_effect(
    {
        let count = count.clone();
        move || {
            log!("count changed: {}", count.get());
            None::<fn()>
        }
    },
    (count.clone(),),
);
```

```rust
// 0.1.x
use_layout_effect(move || {
    measure_element(&node_ref);
});

// 0.2.x
use_layout_effect(
    {
        let node_ref = node_ref.clone();
        move || {
            measure_element(&node_ref);
            None::<fn()>
        }
    },
    (node_ref.clone(),),
);
```

### Derived Value Hooks

In 0.2.x, `use_memo` and `use_callback`/`use_callback_with` are rewritten with explicit dependencies:

```rust
// 0.1.x — implicit dependency tracking
use_memo(move || count.get() * 2);

// 0.2.x — explicit dependencies
use_memo(
    {
        let count = count.clone();
        move || count.get() * 2
    },
    (count.clone(),),
);
```

```rust
// 0.1.x
use_callback(move |_| {
    set_count(count.get() + 1);
});

// 0.2.x
use_callback(
    {
        let count = count.clone();
        move |_| {
            set_count(count.get() + 1);
        }
    },
    (count.clone(),),
);
```

### Auto-wrapping in page! Macro

In 0.2.x, `{expr}`, `if`, and `for` inside `page!` are unconditionally wrapped in `Page::reactive` — no explicit wrapping is needed. Code that previously used `watch { ... }` or manual `Page::reactive(...)` continues to work, but the wrapping is now redundant.

### Reactive and ReactiveIf Clone

`Reactive` and `ReactiveIf` now implement `Clone` via `Arc<dyn Fn()>` in 0.2.x (previously they were not cloneable). This enables passing reactive nodes through more component composition patterns.

## Version Differences (0.3.x)

- `create_resource(fetcher)` is removed; use `use_resource(fetcher, ())`.
- `create_resource_with_deps(fetcher, deps)` is removed; use `use_resource(fetcher, deps)`.
- `use_effect_event` and `use_effect_event_with` are removed; use `use_callback` / `use_callback_with` or read non-dependency values with `.get_untracked()` inside the effect.
- Shared Pages modules should rely on documented inert native/WASM stubs instead of broad call-site `#[cfg]` workarounds.
