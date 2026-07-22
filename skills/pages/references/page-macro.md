# page! Macro Reference

## Basic Syntax

The `page!` macro has a direct body form for ordinary `Page`-returning
functions and explicit closure forms for reusable factories.

### 0.4.x: Direct Page Bodies

Use `page!({ ... })` for application screens and ordinary functions that
return a `Page`. It returns the `Page` immediately, so there is no trailing
`()`. Free value identifiers from the surrounding Rust scope are implicitly
captured and cloned into generated reactive and event closures. Every captured
value must implement `Clone`.

The direct form is `page!({ ... })`: do not add a `move` keyword to the macro
syntax. It supports captures used in expressions, attributes, event handlers,
component props and children, macro arguments, `#head`, and keyed `for` loops.

```rust
use reinhardt::pages::component::Page;
use reinhardt::pages::page;

pub fn greeting_page(name: String) -> Page {
    page!({
        div { class: "greeting", { name } }
    })
}
```

`Signal`, `Action`, `Resource`, `Callback`, `Page`, and typical application
handles are normally cheap to clone. A non-`Clone` capture is a compile error;
keep it outside the page body or pass a cloneable handle instead.

### Reusable Page Factories (Strict)

Use `page!(|| { ... })` or `page!(|props: Props| { ... })` only when a caller
needs a factory that it will invoke later. These forms return a closure and
retain strict capture validation: every value used in the body must be a
declared closure parameter or a local binding inside the body.

```rust
let greeting_factory = page!(|name: String| {
    div { class: "greeting", { name } }
});

let greeting = greeting_factory("Ada".to_string());
```

Migrate an existing body-only page that used surrounding values to
`page!({ ... })`. If that page was intentionally a no-argument factory, make
the factory explicit with `page!(|| { ... })` instead.

### Component Composition (Layout Pattern, 0.4.x)

Wrap content in a layout by accepting `Page` as a parameter:

```rust
pub fn auth_layout(title: &str, form_content: Page) -> Page {
    let title = title.to_string();
    page!({
        div { class: "min-h-screen flex items-center justify-center bg-gray-50",
            div { class: "w-full max-w-md",
                h2 { class: "text-xl font-semibold mb-6", { title } }
                { form_content }
            }
        }
    })
}

// Usage:
pub fn login_page() -> Page {
    let form_view = login_form.into_page();
    auth_layout("Sign in", form_view)
}
```

## Head Directive (SSR)

**(0.4.x)** Inject head content using `#head` for server-side rendering with a
direct page body:

```rust
let page_head = head!(|| {
    title { "Home - My App" }
    meta { name: "description", content: "Welcome" }
    link { rel: "stylesheet", href: resolve_static("css/main.css") }
});

page!(
    #head: page_head,
    {
        div { class: "container",
            h1 { "Welcome Home" }
        }
    }
)
```

## HTML Elements

### Structural Elements

| Element | Description |
|---------|-------------|
| `div` | Generic container |
| `span` | Inline container |
| `p` | Paragraph |
| `header`, `footer` | Header, footer section |
| `main` | Main content |
| `nav` | Navigation |
| `section`, `article` | Generic section, article content |
| `aside` | Sidebar content |

### Headings

`h1`, `h2`, `h3`, `h4`, `h5`, `h6`

### Text-Level Elements

| Element | Description |
|---------|-------------|
| `em`, `strong` | Emphasis, strong emphasis |
| `small`, `mark` | Small text, highlighted text |
| `b`, `i`, `u`, `s` | Bold, italic, underline, strikethrough |
| `code`, `kbd`, `samp`, `var` | Code, keyboard, sample, variable |
| `sub`, `sup` | Subscript, superscript |
| `br`, `wbr` | Line break, word break opportunity |
| `cite`, `abbr`, `time`, `dfn` | Citation, abbreviation, time, definition |
| `ins`, `del` | Inserted, deleted text |
| `q`, `blockquote` | Inline quote, block quote |

### List Elements

`ul`, `ol`, `li`, `dl`, `dt`, `dd`

### Table Elements

`table`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`, `caption`, `colgroup`, `col`

### Form Elements

`form`, `input`, `button`, `label`, `select`, `option`, `optgroup`, `textarea`

### Embedded Content

| Element | Description |
|---------|-------------|
| `img` | Image (requires `src` and `alt`) |
| `iframe` | Inline frame |
| `video`, `audio` | Video, audio player |
| `source`, `track` | Media source, text track |
| `canvas` | Drawing canvas |
| `picture` | Responsive image container |

### Other Elements

`a`, `hr`, `pre`, `figure`, `figcaption`, `details`, `summary`, `dialog`, `data`, `ruby`, `rt`, `rp`, `bdi`, `bdo`, `address`, `template`, `slot`

### Void Elements (Cannot Have Children)

`br`, `col`, `embed`, `hr`, `img`, `input`, `param`, `source`, `track`, `wbr`

## Attributes

Attributes use `key: value` syntax. Underscores convert to hyphens (`data_testid` → `data-testid`).

### Global Attributes

`id`, `class`, `style`, `title`, `lang`, `dir`, `tabindex`, `hidden`, `role`, `data_*`, `aria_*`

### Attribute Value Types

| Type | Syntax | Example |
|------|--------|---------|
| String literal | `attr: "value"` | `class: "container"` |
| Expression | `attr: expr` | `class: css_class` |
| Integer literal | `attr: number` | `tabindex: 0` |
| Boolean expression | `attr: expr` | `disabled: is_disabled` |

### Boolean Attributes (Expression Only — No Literals)

`disabled`, `required`, `readonly`, `checked`, `selected`, `autofocus`, `autoplay`, `controls`, `loop`, `muted`, `default`, `defer`, `formnovalidate`, `hidden`, `ismap`, `multiple`, `novalidate`, `open`, `reversed`

```rust
// CORRECT:
button { disabled: is_disabled, "Submit" }

// INCORRECT (compile error):
button { disabled: true, "Submit" }
```

### Enumerated Attributes

| Element | Attribute | Allowed Values |
|---------|-----------|----------------|
| `input` | `type` | `text`, `password`, `email`, `number`, `tel`, `url`, `search`, `checkbox`, `radio`, `submit`, `button`, `reset`, `file`, `hidden`, `date`, `datetime-local`, `time`, `week`, `month`, `color`, `range`, `image` |
| `button` | `type` | `submit`, `button`, `reset` |
| `form` | `method` | `get`, `post`, `dialog` |
| `form` | `enctype` | `application/x-www-form-urlencoded`, `multipart/form-data`, `text/plain` |

## Event Handlers

Events use `@event: handler` syntax. Handlers are auto-handled (active on WASM, no-op on native).

### Mouse Events

`@click`, `@dblclick`, `@mousedown`, `@mouseup`, `@mouseenter`, `@mouseleave`, `@mousemove`, `@mouseover`, `@mouseout`

### Keyboard Events

`@keydown`, `@keyup`, `@keypress`

### Form Events

`@input`, `@change`, `@submit`, `@focus`, `@blur`

### Touch Events

`@touchstart`, `@touchend`, `@touchmove`, `@touchcancel`

### Drag Events

`@dragstart`, `@drag`, `@drop`, `@dragenter`, `@dragleave`, `@dragover`, `@dragend`

### Other Events

`@load`, `@error`, `@scroll`, `@resize`

### Handler Syntax

Import framework types, app DTOs, route helpers, services, and shared
components at the top of the module before the `page!` expression. Do not bury
long `crate::apps::...` paths inside `page!`, event handlers, or small helper
functions; concise imports keep formatter output readable and make review
comments target the real UI behavior.

```rust
use crate::apps::writing::client::components::version_picker::VersionPicker;
use crate::apps::writing::server_fn::manuscript::{
    generate_outline,
    save_project_settings,
};

// Inline closure with event parameter
button { @click: |e| { handle_click(e); }, "Handle click" }

// Closure ignoring event
button { @click: |_| { do_something(); }, "Run action" }

// Function reference
button { @click: handle_click, "Handle click" }
```

Closures must have 0 or 1 parameter (compile error if more). Prefer named
`use_callback` handles for nontrivial work, and clone non-`Copy` callbacks or
actions at the attribute use site when the render closure also needs them:

```rust
// 0.4.x direct body
let save_click = use_callback(move |_| {
    save_action.dispatch(current_form_values());
}, (save_action.clone(), form_state.clone()));

page!({
    button { @click: save_click.clone(), "Save" }
})
```

## Child Nodes

```rust
// Text content
div { "Hello, World!" }

// Expressions
div { name }
div { format!("{}", count) }
div { { complex_expr } }

// Nested elements
div {
    h1 { "Title" }
    p { "Content" }
}
```

## Localized Child Nodes (0.4.x)

For catalog-backed UI text, enable the facade `pages` and `i18n` features and
render lazy translations directly inside `page!`. `t!` accepts a string literal
and optional named interpolation values; the resulting `TranslatedText` tracks
the current Pages locale when it renders.

```rust
use reinhardt::pages::t;

let display_name = "Ada".to_string();

page!(|display_name: String| {
    section {
        h1 { { t!("Workspace") } }
        p { { t!("Welcome, {name}", name = display_name) } }
    }
})(display_name)
```

Use `tn`, `tp`, or `tnp` for plural or contextual messages; `t!` intentionally
covers only simple messages and named interpolation. Set up the catalog and
`I18nContext` as described in `i18n.md`; do not wrap an already available
catalog translation in `use_resource` just to make it reactive.

## Conditional Rendering

```rust
// if
div {
    if condition {
        span { "Visible" }
    }
}

// if-else
div {
    if condition {
        span { "True" }
    } else {
        span { "False" }
    }
}

// if-else if-else
div {
    if count > 10 {
        span { "Greater" }
    } else if count == 10 {
        span { "Equal" }
    } else {
        span { "Less" }
    }
}
```

## List Rendering

```rust
// Simple for loop
ul {
    for item in items {
        li { item }
    }
}

// With destructuring
ul {
    for (index, item) in items.iter().enumerate() {
        li { { index.to_string() } ": " { item } }
    }
}
```

## Reactive watch Blocks

Use `watch` for Signal-dependent reactive rendering. Unlike static `if` conditions evaluated once at render time, `watch` blocks re-evaluate when Signal dependencies change.

```rust
// 0.4.x direct body with watch
page!({
    div {
        watch {
            if error.get().is_some() {
                div { class: "alert", { error.get().unwrap_or_default() } }
            }
        }
    }
})

// watch with match
watch {
    match state.get() {
        State::Loading => div { "Loading..." },
        State::Ready(data) => div { { data } },
        State::Error(msg) => div { class: "error", { msg } },
    }
}
```

### When to Use watch

| Scenario | Solution |
|----------|----------|
| Static condition on Copy type | Plain `if` |
| Dynamic Signal-dependent condition | `watch { if signal.get() { ... } }` |
| Multiple reactive branches | `watch { match state.get() { ... } }` |

**Best practices**: Pass Signals directly (don't extract values before `page!`). Clone freely. Single expression per `watch` block.

### 0.2.x: Automatic Reactive Wrapping

In 0.2.x, reactive expressions (`{expr}`, `if`, `for`) inside `page!` are **automatically wrapped** in `Page::reactive` — no explicit `watch { ... }` or manual `Page::reactive(...)` call is needed. Existing `watch` blocks still compile, but the wrapping is now redundant.

```rust
// 0.1.x — explicit watch needed for reactive re-rendering
page!(|count: Signal<i32>| {
    div {
        watch {
            if count.get() > 0 {
                span { "Positive" }
            }
        }
    }
})(count)

// 0.2.x — if/for/{expr} are auto-wrapped, watch is optional
page!(|count: Signal<i32>| {
    div {
        if count.get() > 0 {
            span { "Positive" }
        }
    }
})(count)
```

### 0.2.x: Bind Listener Typed Value Conversion

In 0.2.x, `bind listener_value` is added for typed value conversion in event listener bindings. This enables direct extraction of typed values from DOM events without manual parsing:

```rust
// 0.2.x — bind listener_value for typed extraction
label { for: "count", "Count" }
input {
    id: "count",
    type: "number",
    bind listener_value: count_signal,
}
```

## Component Calls

```rust
// Named arguments
MyButton(label: "Click me")
MyCard(title: "Card", content: "Content", class: "custom")

// With children
MyWrapper(class: "container") {
    p { "Child content" }
}
```

## Validation Rules (Compile-Time)

### Accessibility (0.4.0+)

`page!` rejects statically decidable accessibility violations at compile time.
Fix the markup rather than deferring a known violation to a runtime audit.

| Element or attribute | Requirement |
|----------------------|-------------|
| `img` | Must have `src` (string literal) and an `alt` attribute |
| Non-hidden `input` other than `submit`, `reset`, `button`, or `image`; `select`; `textarea` | Must have a non-empty `aria-label`, a static `aria-labelledby` that resolves to a non-hidden element with accessible content, a wrapping non-hidden `label` with accessible content, or a matching `label for` / `id` pair whose label has accessible content |
| `input type: "submit"`, `input type: "reset"` | Built-in accessible names are valid without `value` or ARIA attributes |
| `input type: "button"` | Must have a non-empty `value` or `aria-label`, or resolved `aria-labelledby` |
| `input type: "image"` | Must have a non-empty `alt` or valid ARIA name; generated image submit inputs copy `alt` into `aria-label` |
| `button`, interactive `a` | Must have text content, non-empty `aria-label`, a resolved `aria-labelledby`, or an `img` child with non-empty `alt`; a bare anchor without `href` or events is not interactive |
| `iframe` | Must have a non-empty `title` |
| Static `role` | Must be a concrete [WAI-ARIA 1.3 role](https://www.w3.org/TR/wai-aria-1.3/#role_definitions) |
| Static `tabindex` | Only `0` and `-1` are allowed; do not create a positive tab order |

Dynamic values are accepted when the macro cannot decide the requirement at
compile time. Keep their runtime accessibility behavior intentional and test it
at the component level.

```rust
page!(|| {
    label { for: "search", "Search" }
    input { id: "search", type: "search", name: "search" }

    button {
        aria_label: "Open settings",
        img { src: "/icons/settings.svg", alt: "Settings" }
    }

    iframe { src: "/preview", title: "Preview" }
})()
```

#### Intentional Opt-Outs

Use `a11y: off` only for one element whose intentional behavior relies on
runtime or external labeling. It is not inherited by children and accepts only
the `off` marker, which keeps the exception visible in source.

```rust
input {
    type: "range",
    name: "decorative-volume",
    a11y: off,
}
```

### Security

URL attributes (`href`, `src`, `action`, `formaction`) block dangerous schemes: `javascript:`, `data:`, `vbscript:`

### Element Nesting

| Rule | Description |
|------|-------------|
| Void elements | Cannot have children |
| Interactive elements | Cannot nest inside each other (`button`, `a`, `label`, `select`, `textarea`) |
| `select` | Can only contain `option` and `optgroup` |
| `ul`, `ol` | Can only contain `li` |
| `dl` | Can only contain `dt`, `dd`, and `div` |

## Complete Example (0.4.x)

```rust
use reinhardt::pages::prelude::*;

fn todo_app(todos: Signal<Vec<String>>, filter: Signal<String>) -> Page {
    page!({
        div {
            class: "todo-app",

            header {
                h1 { "My Todo App" }
                label { for: "new-todo", "Add a todo" }
                input {
                    id: "new-todo",
                    type: "text",
                    placeholder: "Add a todo...",
                    @input: |e| { /* handle input */ },
                }
            }

            nav {
                for filter_type in vec!["all", "active", "completed"] {
                    button {
                        @click: move |_| { /* set filter */ },
                        { filter_type }
                    }
                }
            }

            ul {
                class: "todo-list",
                watch {
                    if todos.get().is_empty() {
                        li { class: "empty", "No todos yet" }
                    }
                }
            }

            footer {
                aria_label: "Todo stats",
                data_testid: "footer",
                { format!("{} items", todos.get().len()) }
            }
        }
    })
}
```
