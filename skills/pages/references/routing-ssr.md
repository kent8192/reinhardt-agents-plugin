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

## ClientLauncher Lifecycle Hooks (rc.23+)

`ClientLauncher` is a declarative builder that replaces the hand-rolled WASM entry-point pattern (panic hook, router init, history listener, link interception, render Effect). Downstream apps reduce to a single chain:

```rust
use reinhardt::pages::app::ClientLauncher;

#[wasm_bindgen(start)]
pub fn main() -> Result<(), JsValue> {
    ClientLauncher::new(init_router)
        .mount("#app")
        .intercept_links(true)
        .before_launch(|| {
            state::init_app_state();
        })
        .after_launch(|| {
            log!("SPA ready");
        })
        .on_path("/dashboard", |ctx| {
            // ctx: PathCtx — fires whenever current_path matches exactly
            connect_dashboard_websocket();
        })
        .on_path_pattern("/users/{id}/", |ctx| {
            // fires when the pattern matches and bound params change
            let id = ctx.params.get("id").cloned().unwrap_or_default();
            log!("entered user {id}");
        })
        .launch();
    Ok(())
}
```

Builder surface:

| Method | Purpose |
|--------|---------|
| `mount(selector)` | CSS selector of the DOM root |
| `intercept_links(bool)` | Install document-level click handler for `<a href="/...">` (default `true`) |
| `before_launch(FnOnce)` | Run after panic hook / scheduler, before Router init |
| `after_launch(FnOnce)` | Run after first mount; navigations triggered here re-render |
| `on_path(path, Fn)` | Subscribe to exact-path matches |
| `on_path_pattern(pattern, Fn)` | Subscribe to pattern matches with param-diff detection |
| `launch()` | Runs Phase A (setup) → Phase B (initial mount) → Phase C (persistent `Router::on_navigate` subscriptions) |

Source: PR (#3997). Internal architecture migrated from reactive `Effect` auto-tracking to explicit `Router::on_navigate` callbacks in (#4114).

### SPA Link Interception (rc.23 → rc.29 fix)

`.intercept_links(true)` installs a document-level click listener that walks the DOM from `event.target` up to the enclosing `<a>` and routes internal `href="/..."` links through `Router::push` instead of triggering a full page reload.

- Modifier keys (Cmd/Ctrl/Shift/Alt), `target="_blank"`, `download`, `rel=external`, and protocol-relative URLs are excluded automatically.
- Apps that already wire their own SPA handler can opt out with `.intercept_links(false)`.
- rc.29 fix: earlier rc.23–rc.28 versions cast `event.target` directly to `Element`, so clicks on the inner `Text` node of `<a>label</a>` or `<a><span>label</span></a>` slipped through and triggered full-page navigation. The DOM walk now handles non-`Element` targets (`Text`, nested children) by traversing parent nodes until an `<a>` is found. `Router::push` errors are also no longer silently swallowed — they emit a `console.warn` (`nav_diag!` in debug builds).

Source: (#3997, #4344).

## SPA Navigation Improvements (rc.26+)

rc.26 restored end-to-end SPA navigation in `ClientLauncher::launch()`: `Router::push` now reliably re-fires the launcher's render pipeline so each route mounts its own view instead of the boot-time view. The fix hoists `current_path` / `current_params` `Signal` clones out of the `with_router(|r| ...)` borrow before subscription, ensuring the launcher tracks both Signals as direct subscribers (#4078).

rc.26 also migrated `ClientLauncher::launch`, `on_path`, and `on_path_pattern` from reactive `Effect` / `Signal` auto-tracking to explicit `Router::on_navigate` callbacks. Public API surface (`ClientLauncher::launch`, `on_path`, `on_path_pattern`, `Router::current_path`, `Router::current_params`) is unchanged, but the render pipeline now runs in three explicit phases:

- **Phase A — Setup**: panic hook, scheduler, `before_launch` hooks, `Router` init, popstate registration, DOM root resolution, link interceptor install.
- **Phase B — Initial mount (inline, no Effect)**: `Router::render_current` → clear `innerHTML` → `view.mount`.
- **Phase C — Persistent subscriptions**: register render listener via `Router::on_navigate` *before* draining `after_launch` (so navigations from `after_launch` re-render), then register one `on_navigate` listener per `on_path` / `on_path_pattern` entry.

After this migration `ClientLauncher::launch` contains zero `Effect::new` calls, eliminating the auto-tracking fragility class that produced repeated SPA navigation regressions.

Source: (#4078, #4114).

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

## --with-pages URL Submodule Layout (rc.29 fix)

`reinhardt-admin startapp --with-pages <app>` (and the workspace variant) now scaffolds the canonical `urls/` submodule layout established in rc.19 instead of a flat `urls.rs` that returned only `ServerRouter::new()`. The generated app gains both a server endpoint surface and a client-side SPA router scaffold out of the box:

```
<app>/
└── urls.rs                  # aggregator declaring submodules
└── urls/
    ├── server_urls.rs       # #[url_patterns(InstalledApp::<App>, mode = server)]
    └── client_router.rs     # #[url_patterns(InstalledApp::<App>, mode = client)]
```

The aggregator uses `#[cfg(server)]` / `#[cfg(client)]` (matching the cfg aliases declared by the scaffold-generated `build.rs`, not `wasm` / `native`). `ws_urls.rs` is intentionally not scaffolded — WebSocket routing remains opt-in.

This fixes rc.19-era drift where the template emitted only the flat `urls.rs` and forced consumers to rewrite the module by hand before they could add a client-side route.

Source: (#4357).

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

## Version Differences (0.2.x)

### Removed Named Route Helpers

In 0.2.x, the following standalone functions are **removed**:

- `named_route()`
- `named_route_params()`
- `named_route_result()`
- `named_route_path()`
- `named_page()`

All named-route registration now goes through `ClientRouter::route*` methods, which require `name` as a **mandatory first argument**:

```rust
// 0.1.x
Router::new()
    .route("/users/{id}/", || user_detail_page())
    .named_route("user_detail", "/users/{id}/", || user_detail_page())

// 0.2.x — name is the mandatory first argument on all route* methods
Router::new()
    .route("user_detail", "/users/{id}/", || user_detail_page())
```

### SPA Navigation via `reinhardt::pages::navigate`

In 0.2.x, prefer `reinhardt::pages::navigate` for SPA navigation instead of manually calling `window.location.set_href` or constructing `History` API calls:

```rust
use reinhardt::pages::navigate;

// Preferred — uses the registered router internally
navigate("/users/42/");
```

This function integrates with the router's subscription system and ensures all `on_path` / `on_path_pattern` listeners fire correctly.

### `register_globally` for SPA Client Initialization

In 0.2.x, `register_globally` replaces the manual `wasm_bindgen(start)` dispatch pattern for SPA client initialization. Instead of manually wiring up the router, history listener, and link interception, call `register_globally` once:

```rust
// 0.1.x — manual setup in #[wasm_bindgen(start)]
router::init_global_router();
router::with_router(|r| r.setup_history_listener());
setup_link_interception(&document);

// 0.2.x — single call replaces manual dispatch
ClientLauncher::new(init_router)
    .mount("#app")
    .register_globally()
    .launch();
```

`register_globally` registers the router, history listener, and link interceptor in one step, making the SPA entry point more concise and less error-prone.
