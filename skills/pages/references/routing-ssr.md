# Routing, SSR & Hydration Reference

## Client-Side Router

Django-style URL patterns with History API integration.

### Setup

Routes take closures that return `Page`:

```rust
use reinhardt::pages::router::Router;

fn init_router() -> Router {
    Router::new()
        .route("/", || dashboard_page())
        .route("/login", || login_page())
        .route("/users/", || user_list_page())
        .route("/users/{id}/", || user_detail_page())
        .named_route("user_detail", "/users/{id}/", || user_detail_page())
        .not_found(|| not_found_page())
}
```

### Thread-Local Router (Recommended Pattern)

Store the router in a `thread_local!` for SPA access:

```rust
use std::cell::RefCell;
use reinhardt::pages::router::Router;

thread_local! {
    static ROUTER: RefCell<Option<Router>> = const { RefCell::new(None) };
}

/// Initialize the global router instance. Must be called once at startup.
pub fn init_global_router() {
    ROUTER.with(|r| {
        *r.borrow_mut() = Some(init_router());
    });
}

/// Access the global router within a closure.
///
/// # Panics
///
/// Panics if `init_global_router` has not been called.
pub fn with_router<F, R>(f: F) -> R
where
    F: FnOnce(&Router) -> R,
{
    ROUTER.with(|r| {
        f(r.borrow()
            .as_ref()
            .expect("Router not initialized. Call init_global_router() first."))
    })
}
```

### SPA Navigation

Use standard HTML `<a>` tags with `href` in `page!` macro. SPA link interception is set up separately to avoid full page reloads:

```rust
// In page! macro — use standard <a> tags
page!(|| {
    nav {
        a { href: "/", class: "nav-link", "Overview" }
        a { href: "/users/", class: "nav-link", "Users" }
        a { href: "/login", class: "nav-link", "Login" }
    }
})()
```

#### SPA Link Interception (Required for Client-Side Navigation)

Set up a global click handler to intercept internal links and use `router.push()` instead of full page reloads:

```rust
fn setup_link_interception(document: &web_sys::Document) {
    let closure = Closure::wrap(Box::new(move |event: web_sys::MouseEvent| {
        // Walk DOM to find enclosing <a> tag
        let target = event.target().unwrap();
        let mut el = target.dyn_into::<web_sys::Element>().ok();
        while let Some(element) = el {
            if element.tag_name() == "A" {
                if let Some(href) = element.get_attribute("href") {
                    // Only intercept internal links (starting with "/")
                    if href.starts_with('/') {
                        event.prevent_default();
                        router::with_router(|r| {
                            let _ = r.push(&href);
                        });
                    }
                }
                return;
            }
            el = element.parent_element();
        }
    }) as Box<dyn FnMut(_)>);

    document
        .add_event_listener_with_callback("click", closure.as_ref().unchecked_ref())
        .expect("failed to add click listener");
    closure.forget();
}
```

#### Programmatic Navigation

```rust
router::with_router(|r| {
    let _ = r.push("/users/42/");
});
```

### Named Routes (Reverse URL)

```rust
// reverse() returns Result — handle the error
let url = router.reverse("user_detail", &[("id", "42")]).unwrap();
```

### Route Parameters

Use `PathParams<T>` as an extractor with destructuring:

```rust
use reinhardt::pages::router::PathParams;

// PathParams<T> is a generic wrapper — destructure in the function signature
fn user_detail(PathParams(id): PathParams<i64>) -> Page {
    // id is i64, extracted from the URL
    // ...
}
```

### Route Guards

```rust
use reinhardt::pages::router::{guard, guard_or};

// Redirect to login if not authenticated
let protected_route = guard(is_authenticated, "/login");
```

### PathPattern

Django-style URL patterns:

```rust
use reinhardt::pages::prelude::PathPattern;

let pattern = PathPattern::new("/users/{id}/posts/{post_id}/");

// matches() returns Option<(HashMap<String, String>, Vec<String>)>
if let Some((params, _)) = pattern.matches("/users/42/posts/7/") {
    // params.get("id") == Some(&"42".to_string())
    // params.get("post_id") == Some(&"7".to_string())
}
```

## WASM Entry Point (Recommended Pattern)

The recommended SPA setup pattern combines router initialization, link interception, and reactive rendering:

```rust
use wasm_bindgen::prelude::*;
use reinhardt::pages::reactive::Effect;

#[wasm_bindgen(start)]
pub fn main() -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    state::init_app_state();

    // Initialize the SPA router and register browser history listener
    router::init_global_router();
    router::with_router(|r| r.setup_history_listener());

    let window = web_sys::window().expect("no global window");
    let document = window.document().expect("no document");

    // Set up global click handler for SPA link interception
    setup_link_interception(&document);

    // Set up reactive rendering — re-renders #app when route changes
    let path_signal = router::with_router(|r| r.current_path().clone());
    let doc = document.clone();
    let effect = Effect::new(move || {
        let _path = path_signal.get(); // Subscribe to path changes
        let app = doc.get_element_by_id("app").expect("no #app element");
        let page = router::with_router(|r| r.render_current());
        app.set_inner_html(&page.render_to_string());
    });
    // Keep the effect alive for the lifetime of the page
    std::mem::forget(effect);

    Ok(())
}
```

## Server-Side Rendering (SSR)

### SsrRenderer

```rust
use reinhardt::pages::prelude::*;

// Simple rendering
let html = SsrRenderer::render(&my_component);

// With options
let html = SsrRenderer::with_options(SsrOptions::default())
    .render(&my_component);

// Full page rendering (takes component only)
let mut renderer = SsrRenderer::with_options(SsrOptions::default());
let page_html = renderer.render_page(&my_component);
```

### Head Section in SSR

```rust
let page_head = head!(|| {
    title { "My App" }
    meta { name: "description", content: "..." }
});

let page = page! {
    #head: page_head,
    || { div { "Content" } }
}();

// SsrRenderer includes the head in the HTML output
let html = SsrRenderer::render(&page);
```

## Hydration

Client-side activation of server-rendered HTML.

### Setup

```rust
use reinhardt::pages::prelude::*;

// Initialize hydration state (call once on WASM startup)
init_hydration_state();

// Hydrate a component
hydrate(&my_component);

// Check completion
if is_hydration_complete() {
    // All components hydrated
}

// Callback on completion
on_hydration_complete(|| {
    log!("Hydration complete");
});
```

### Island Hydration

Selective hydration of interactive sections within static HTML. Only marked "islands" are hydrated on the client, reducing JavaScript and improving performance.

## Static File Resolution

```rust
use reinhardt::pages::prelude::*;

// Initialize (once, on startup)
init_static_resolver(static_manifest);

// Resolve hashed URL
let css_url = resolve_static("css/main.css");
// Returns: "/static/css/main.abc123.css"

// Check if initialized
if is_initialized() {
    // Safe to resolve
}
```

Compatible with reinhardt's collectstatic system for cache-busted asset URLs.

## cfg_aliases Setup

Required in `build.rs` for platform-conditional code:

```rust
// build.rs
use cfg_aliases::cfg_aliases;

fn main() {
    println!("cargo::rustc-check-cfg=cfg(wasm)");
    println!("cargo::rustc-check-cfg=cfg(native)");

    cfg_aliases! {
        wasm: { target_arch = "wasm32" },
        native: { not(target_arch = "wasm32") },
    }
}
```

```toml
# Cargo.toml
[build-dependencies]
cfg_aliases = "0.2"
```

Then use `#[cfg(wasm)]` and `#[cfg(native)]` instead of `#[cfg(target_arch = "wasm32")]`.
