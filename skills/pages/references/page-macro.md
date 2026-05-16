# page! Macro Reference

## Basic Syntax

The `page!` macro creates anonymous components with closure-style DSL. It returns a closure — invoke it with `()` to get a `Page`:

```rust
use reinhardt::pages::component::Page;
use reinhardt::pages::page;

// No parameters — note the double call: page!(|| { ... })()
pub fn hello_page() -> Page {
    page!(|| {
        div { "Hello, World!" }
    })()
}

// With parameters — pass arguments in the second call
pub fn greeting_page(name: String) -> Page {
    page!(|name: String| {
        div { class: "greeting", { name } }
    })(name)
}
```

### Component Composition (Layout Pattern)

Wrap content in a layout by accepting `Page` as a parameter:

```rust
pub fn auth_layout(title: &str, form_content: Page) -> Page {
    let title = title.to_string();
    page!(|title: String, form_content: Page| {
        div { class: "min-h-screen flex items-center justify-center bg-gray-50",
            div { class: "w-full max-w-md",
                h2 { class: "text-xl font-semibold mb-6", { title } }
                { form_content }
            }
        }
    })(title, form_content)
}

// Usage:
pub fn login_page() -> Page {
    let form_view = login_form.into_page();
    auth_layout("Sign in", form_view)
}
```

## Head Directive (SSR)

Inject head content using `#head` for server-side rendering:

```rust
let page_head = head!(|| {
    title { "Home - My App" }
    meta { name: "description", content: "Welcome" }
    link { rel: "stylesheet", href: resolve_static("css/main.css") }
});

page! {
    #head: page_head,
    || {
        div { class: "container",
            h1 { "Welcome Home" }
        }
    }
}()
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
| Integer literal | `attr: number` | `tabindex: 1` |
| Boolean expression | `attr: expr` | `disabled: is_disabled` |

### Boolean Attributes (Expression Only — No Literals)

`disabled`, `required`, `readonly`, `checked`, `selected`, `autofocus`, `autoplay`, `controls`, `loop`, `muted`, `default`, `defer`, `formnovalidate`, `hidden`, `ismap`, `multiple`, `novalidate`, `open`, `reversed`

```rust
// CORRECT:
button { disabled: is_disabled }

// INCORRECT (compile error):
button { disabled: true }
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

```rust
// Inline closure with event parameter
button { @click: |e| { handle_click(e); } }

// Closure ignoring event
button { @click: |_| { do_something(); } }

// Function reference
button { @click: handle_click }
```

Closures must have 0 or 1 parameter (compile error if more).

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
// watch with if
page!(|error: Signal<Option<String>>| {
    div {
        watch {
            if error.get().is_some() {
                div { class: "alert", { error.get().unwrap_or_default() } }
            }
        }
    }
})(error.clone())

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

### Accessibility

| Element | Requirement |
|---------|-------------|
| `img` | Must have `src` (string literal) and `alt` attributes |
| `button` | Must have text content or `aria-label`/`aria-labelledby` |

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

## Complete Example

```rust
use reinhardt::pages::prelude::*;

fn todo_app(todos: Signal<Vec<String>>, filter: Signal<String>) -> Page {
    page!(|todos: Signal<Vec<String>>, filter: Signal<String>| {
        div {
            class: "todo-app",

            header {
                h1 { "My Todo App" }
                input {
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
    })(todos, filter)
}
```
