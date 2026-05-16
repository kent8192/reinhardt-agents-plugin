---
name: pages
description: Use when building WASM frontend pages with reinhardt-pages - covers page!/head!/form! macros, reactive hooks (Signal/Effect/useState), routing, SSR/hydration, server functions, and API client
---

# Reinhardt Pages (WASM Frontend)

Guide developers through building WASM frontend applications using reinhardt-pages.

## When to Use

- User creates or modifies WASM frontend components
- User works with `page!`, `head!`, `form!` macros or `#[server_fn]`
- User sets up reactive state with Signal, Effect, Memo, or hooks
- User configures client-side routing, SSR, or hydration
- User mentions: "page", "head", "form", "server_fn", "Signal", "useState", "useEffect", "watch", "SSR", "hydration", "WASM", "frontend", "router", "ApiQuerySet", "Table", "prelude", "component"

## Workflow

### Creating a New Page

1. **Define Page Component** — read `references/page-macro.md`
2. **Add Head Section** — read `references/head-form-macros.md` (if SSR)
3. **Set Up Reactivity** — read `references/reactive-hooks.md`
4. **Configure Routing** — read `references/routing-ssr.md` (if SPA)
5. **Add Server Functions** — read `references/head-form-macros.md` (`#[server_fn]` section)
6. **Connect API** — read `references/api-tables.md` (if data fetching)
7. **Test** — read `references/testing-guide.md`

### Creating a Form

1. **Define Form** — read `references/head-form-macros.md` (form! section)
2. **Add Server Function** — read `references/head-form-macros.md` (`#[server_fn]` section)
3. **Embed in Page** — read `references/page-macro.md`
4. **Test** — read `references/testing-guide.md`

## Important Rules

- Prefer explicit imports over prelude (e.g., `use reinhardt::pages::component::Page;`) — see reinhardt-cloud dashboard for the canonical import style
- Configure `cfg_aliases` in `build.rs` for `wasm`/`native` aliases
- Event handlers in `page!` are auto-handled across platforms (no manual `#[cfg(wasm)]` needed)
- Use `watch {}` for reactive conditionals (not static `if` with extracted Signal values)
- Boolean attributes require expressions, not literals (`disabled: is_disabled`, NOT `disabled: true`)
- `img` elements require both `src` and `alt` (compile-time enforcement)
- `button` elements require text content or `aria-label`/`aria-labelledby`
- URL attributes (`href`, `src`, `action`, `formaction`) block dangerous schemes (`javascript:`, `data:`, `vbscript:`)
- ALL code comments must be in English
- Use `reinhardt-query` for any SQL construction, NEVER raw SQL

## Cross-Domain References

- Model definitions: `${CLAUDE_PLUGIN_ROOT}/skills/modeling/references/model-patterns.md`
- DI patterns: `${CLAUDE_PLUGIN_ROOT}/skills/dependency-injection/references/di-patterns.md`
- Auth backends: `${CLAUDE_PLUGIN_ROOT}/skills/authentication/references/auth-backends.md`
- Macro overview: `${CLAUDE_PLUGIN_ROOT}/skills/macros/references/attribute-macros.md`
- View patterns: `${CLAUDE_PLUGIN_ROOT}/skills/api-development/references/view-patterns.md`

## Dynamic References

For the latest API definitions:
1. Read `reinhardt/crates/reinhardt-pages/macros/src/lib.rs` for macro definitions (page!, head!, form!, #[server_fn])
2. Read `reinhardt/crates/reinhardt-pages/src/prelude.rs` for exported types
3. Read `reinhardt/crates/reinhardt-pages/src/reactive.rs` for reactive system
4. Read `reinhardt/crates/reinhardt-pages/src/router.rs` for routing
5. Read `reinhardt/crates/reinhardt-pages/src/api.rs` for API client
6. Read `reinhardt/crates/reinhardt-pages/src/tables.rs` for table component
7. Read `reinhardt/crates/reinhardt-pages/src/testing.rs` for test utilities
