# Typed Page Events Reference (0.4.x)

Standard intrinsic `page!` event names carry their catalogued framework event
payload. Inferred closures usually need no annotation; external functions and
`Callback` values must accept the exact payload type for the event.

## Standard Event Payloads

| Intrinsic | Payload |
|-----------|---------|
| `@click` | `ClickEvent` |
| `@input` | `InputEvent` |
| `@change` | `ChangeEvent` |
| `@submit` | `SubmitEvent` |
| `@keydown`, `@keyup` | `KeyboardEvent` |
| `@pointerdown`, `@pointermove`, `@pointerup` | `PointerEvent` |
| `@focus`, `@blur` | `FocusEvent` |

Use the event catalog from the current Pages prelude for the complete list. Do
not annotate every inline closure preemptively; let the intrinsic event choose
the type unless a named function or callback needs an explicit signature.

```rust
fn handle_input(event: InputEvent) {
    if let Ok(value) = event.value() {
        // ...
        log_value(value);
    }
}

page!({
    input { @input: handle_input }
})
```

## Target Extraction and Snapshots

Target helpers return `Result<_, EventTargetError>` because the event target may
not be the expected element:

```rust
fn handle_form(event: InputEvent) -> Result<(), EventTargetError> {
    let current_target = event.current_target();
    let value = event.value()?;
    let checked = event.checked()?;
    let selected = event.selected_values()?;
    let files = event.files()?;
    let _snapshot = current_target;
    submit_snapshot(value, checked, selected, files)
}
```

`current_target()` is an owned snapshot. Capture that snapshot before an
`await`; do not borrow a live DOM target across the suspension point. `target`
and `current_target` are intentionally distinct when bubbling events are
handled.

## Escape Hatches

Use `raw_event_handler` with `platform::Event` for low-level integration that
needs a platform event, and use `@custom("event-name")` for a custom intrinsic
event. These paths deliberately give up the standard event payload catalog;
keep the cast/extraction boundary narrow and document the expected target.

Component `@event` props are different: they retain the event type declared by
the component API rather than being rewritten to a DOM intrinsic payload.

The removed `DummyEvent` is not a compatibility type. Native standard-event
tests use the same typed payloads as the browser surface.

## Testing Typed Events

Use `EventFixture` and `Screen::settle()` from the Pages testing utilities:

```rust
screen
    .get_by_label("Title")
    .dispatch(EventFixture::input().value("A new title"))?;
screen.get_by_role(Role::Button, "Save").dispatch(EventFixture::click())?;
screen.settle();

assert_eq!(screen.text("status"), "Saved");
```

The fixture also provides `submit`, `change`, `key_down`, and `pointer_move`,
plus setters for value, checked, selected values, files, and
`content_editable`. Cover target/current-target differences and call
`Screen::settle()` after nested async or reactive writes before asserting the
rendered state.
