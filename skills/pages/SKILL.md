---
name: pages
description: Use when building WASM frontend pages with reinhardt-pages - covers page!/head!/form! macros, reactive hooks (Signal/Effect/useState), i18n, routing and nested layouts, async SSR/hydration, server functions, and API client
versions: ["0.1.x", "0.2.x", "0.3.x", "0.4.x"]
---

# Reinhardt Pages (WASM Frontend)

Guide developers through building WASM frontend applications using reinhardt-pages.

## When to Use

- User creates or modifies WASM frontend components
- User works with `page!`, `head!`, `form!` macros or `#[server_fn]`
- User sets up reactive state with Signal, Effect, Memo, or hooks
- User configures client-side routing, SSR, or hydration
<<<<<<< HEAD
- User mentions: "page", "head", "form", "server_fn", "server_fnset", "Signal", "useState", "useEffect", "watch", "i18n", "translation", "locale", "t!", "SSR", "hydration", "WASM", "frontend", "router", "ApiQuerySet", "Table", "prelude", "component"
=======
- User builds nested layout routes with `#[layout]` and `Outlet`
- User uses async SSR, `SsrStream`, or native resource hydration
- User mentions: "page", "head", "form", "server_fn", "bind:", "Signal", "useState", "useEffect", "watch", "EventFixture", "i18n", "translation", "locale", "t!", "SSR", "hydration", "SsrStream", "resource_timeout", "WASM", "frontend", "router", "ClientRouter", "Outlet", "ApiQuerySet", "Table", "prelude", "component", "layout"
>>>>>>> origin/main

## Workflow

### Creating a New Page

1. **Define Page Component** — read `references/page-macro.md`
2. **Add Head Section** — read `references/head-form-macros.md` (if SSR)
3. **Set Up Reactivity** — read `references/reactive-hooks.md`
4. **Add Pages I18n** — read `references/i18n.md` for localized UI, locale switching, or SSR/hydration translations
5. **Configure Routing** — read `references/routing-ssr.md` (if SPA)
6. **Add Server Functions** — read `references/head-form-macros.md` (`#[server_fn]` section)
7. **Connect API** — read `references/api-tables.md` (if data fetching)
8. **Test** — read `references/testing-guide.md`

### Creating a Form

1. **Define Form** — read `references/head-form-macros.md` (form! section)
2. **Add Server Function** — read `references/head-form-macros.md` (`#[server_fn]` section)
3. **Embed in Page** — read `references/page-macro.md`
4. **Test** — read `references/testing-guide.md`

## Important Rules

- Prefer explicit imports over prelude (e.g., `use reinhardt::pages::component::Page;`) — see reinhardt-cloud dashboard for the canonical import style
- Import app/framework types at the top of the module instead of repeating long fully qualified paths in components or server function signatures/bodies
- In route-backed UI, wire buttons and actions to route params, form values, loaded DTOs, selected rows/versions, and server return values; never leave demo fixture IDs, sample constants, or canned text in production route actions
- Build static form structure with `form!` and dynamic form state with `use_form`
- For user-facing relation inputs, show representative values such as `title`, `name`, or `slug`; do not ask users to type raw foreign-key primary keys unless the surface is internal/admin-only or no useful representative field exists
- Configure `cfg_aliases` in `build.rs` for `wasm`/`native` and `server`/`client` aliases
- Event handlers in `page!` are auto-handled across platforms (no manual `#[cfg(wasm)]` needed)
- Standard intrinsic events infer exact 0.4.x payload types such as `ClickEvent`, `InputEvent`, and `ChangeEvent`. Use `raw_event_handler` with `platform::Event` only for low-level or custom events; component event props keep their declared type.
- Target extraction helpers such as `value()`, `checked()`, `selected_values()`, and `files()` return `Result` and read an owned `current_target` snapshot that remains valid across `await`.
- Use `watch {}` for reactive conditionals (not static `if` with extracted Signal values)
- Use route reverse helpers for `href`, `action`, and `formaction` when named routes exist; avoid hardcoded paths
- For catalog-backed Pages UI in 0.4.x, enable both facade features `pages` and `i18n`, then use `I18nContext` with `t!` (or `tr` / `tn` / `tp` / `tnp`) instead of per-label asynchronous translation resources
- In 0.4.x, keep locale updates validated through `I18nContext::set_locale()` / `locale()`; do not depend on the removed writable `locale_signal()` accessor
- In 0.4.x, configure SSR Pages i18n through `SsrOptions::new().i18n_context(context)` so the renderer writes `pages.i18n` state and hydration restores the resolved catalogs before the first client render
- In 0.4.x, define nested SPA shells with `ClientRouter::routes`, `#[layout]`, and one plain `Outlet`; layout paths are absolute, child paths are relative, `children.index(...)` owns the layout base route, and layout and leaf names share one route namespace
- In 0.4.x, treat SSR rendering as asynchronous: use `render_page(...).await` for an `SsrStream` or `render_page_to_string(...).await` for buffered HTML, and configure `SsrOptions::resource_timeout(...)` when native `use_resource` calls must resolve during SSR
- In 0.4.x, native `use_resource` calls inside `SsrRenderer` can serialize resolved `Success` or `Error` state for hydration; use `use_resource_with_key` when a conditionally rendered resource needs a stable explicit hydration key
- Boolean attributes require expressions, not literals (`disabled: is_disabled`, NOT `disabled: true`)
- `img` elements require both `src` and `alt` (compile-time enforcement)
- `button` elements require text content or `aria-label`/`aria-labelledby`
- URL attributes (`href`, `src`, `action`, `formaction`) block dangerous schemes (`javascript:`, `data:`, `vbscript:`)
- ALL code comments must be in English
- Use `reinhardt-query` for any SQL construction, NEVER raw SQL
- In 0.4.x, `#[server_fn]` functions should inject shared self-keyed services as direct `T` / `Depends<T>`, or explicit application keys as `KeyedDepends<K, T>`; `Depends<K, T>` is a 0.3 migration spelling.
- Prefer DI services over utility-function clusters for business operations that own domain policy, state transitions, validation policy, orchestration dependencies, lifecycle scoping, or test overrides
- Reserve utility functions for pure codecs, DTO conversion, error mapping, provider-local wire conversion, and narrow private transformations that do not need request-scoped dependencies
- Keep Pages app `services/` modules focused on injectable keys, provider functions, and service structs/functions; put prompt builders, provider adapters, parsers, converters, repository/database internals, and narrow private helpers under app-local `server/` modules
- Since 0.2.x, reactive expressions in `page!` are auto-wrapped — explicit `Page::reactive(...)` is no longer needed
- Since 0.2.x, `use_effect`/`use_memo`/`use_callback` take explicit dependency arrays
- Use `use_action` for async mutations, `use_resource` for async reads or derived text, and `use_callback` / `use_callback_with` for event handlers; keep `spawn_local` as an escape hatch for low-level browser integration only
- In 0.3.x, use `use_resource(fetcher, deps)` for both mount-only and dependency-driven resources; replace `create_resource*`
- In 0.3.x, replace `use_effect_event*` with `use_callback*` or `.get_untracked()` inside the effect
- Route internal button-triggered redirects through `reinhardt::pages::navigate(..., NavigationType::Push)` or the current router handle API; use `window.location.set_href` only for external URLs or hard-navigation fallbacks
- In 0.4.x, use a small `#[server_fn]` plus `use_resource` only for translation-dependent copy that is truly server-only or depends on server-side policy/data; do not add that round trip for normal catalog-backed Pages labels that `t!` can render synchronously
- In 0.1.x through 0.3.x, expose app-local server-side translations through a small registered `#[server_fn]` and load them with `use_resource` plus a stable fallback instead of duplicating gettext logic behind client/server cfg gates
- Put route-backed `#[component]` wrappers under `src/apps/<app>/client/components/`, not in app-local `pages.rs` or `client/pages`
- For `#[server_fn]`, keep endpoint-specific request flows visible; do not move the same logic into `server/`, `service/`, or `services/` unless the extraction creates a narrower contract, shared dependency, or independently testable invariant
- Keep simple `Model::objects()` CRUD visible inside the `#[server_fn]` or nearby endpoint helper; avoid semantic wrappers such as `get_project_model`, `list_document_chunks`, or `document_path` when they only hide a direct ORM call
- Inline and delete single-use helpers that only delegate one `#[server_fn]` section's request, dependencies, and persistence/provider sequence
- Test service-boundary domain rules directly when a service owns lifecycle, validation, state-transition, or orchestration policy
- Use 0.3 Pages primitives directly where relevant: `#[wasm_server_api]`, `Portal` / `mount_portal`, `ActivityBoundary`, `ViewTransitionBoundary`, and `FieldArray`
- Keep shared app code cfg-clean across native and `wasm32-unknown-unknown`; rely on documented inert stubs instead of broad call-site `#[cfg]` workarounds
<<<<<<< HEAD
- In 0.4.x, group existing server functions with `#[server_fnset]` and register the set explicitly. For model-backed sets, require wire DTO mappings, a typed unique lookup, and an explicit policy; do not treat them as REST ViewSets
=======
- In 0.4.x, use `bind:` for signal-owned text, checkbox, radio, number, textarea, and select controls; keep uncontrolled controls event-owned, and use `number(value, error)` only when rejected numeric text must be surfaced
>>>>>>> origin/main

## Cross-Domain References

- Model definitions: `../modeling/references/model-patterns.md`
- DI patterns: `../dependency-injection/references/di-patterns.md`
- Auth backends: `../authentication/references/auth-backends.md`
- Macro overview: `../macros/references/attribute-macros.md`
- View patterns: `../api-development/references/view-patterns.md`

## Dynamic References

For the latest API definitions:

1. Read `reinhardt/crates/reinhardt-pages/macros/src/lib.rs` for macro definitions (page!, head!, form!, #[component], #[layout], #[server_fn])
2. Read `reinhardt/crates/reinhardt-pages/src/prelude.rs` for exported types
3. Read `reinhardt/crates/reinhardt-pages/src/reactive.rs` for reactive system
<<<<<<< HEAD
4. Read `reinhardt/crates/reinhardt-pages/src/router.rs` for routing
5. Read `reinhardt/crates/reinhardt-pages/src/api.rs` for API client
6. Read `reinhardt/crates/reinhardt-pages/src/tables.rs` for table component
7. Read `reinhardt/crates/reinhardt-pages/src/testing.rs` for test utilities
8. Read `reinhardt/crates/reinhardt-pages/src/i18n.rs` for reactive Pages i18n and SSR/hydration contracts
9. Read `reinhardt/crates/reinhardt-pages/docs/server_fn_macro.md` for typed server function sets
=======
4. Read `reinhardt/crates/reinhardt-pages/src/router.rs` for routing, nested layout trees, and `Outlet`
5. Read `reinhardt/crates/reinhardt-pages/src/ssr/renderer.rs` for async SSR, `SsrStream`, resource resolution, and hydration state
6. Read `reinhardt/crates/reinhardt-pages/src/api.rs` for API client
7. Read `reinhardt/crates/reinhardt-pages/src/tables.rs` for table component
8. Read `reinhardt/crates/reinhardt-pages/src/testing.rs` for test utilities
9. Read `reinhardt/crates/reinhardt-pages/src/i18n.rs` for reactive Pages i18n and SSR/hydration contracts
>>>>>>> origin/main
