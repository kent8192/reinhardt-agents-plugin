---
name: api-development
description: Use when building REST API endpoints with reinhardt-web - covers serializers, views, URL routing, authentication, and pagination
versions: ["0.1.x", "0.2.x", "0.3.x", "0.4.0"]
---

# Reinhardt REST API Development

Guide developers through building REST API endpoints using reinhardt-rest, reinhardt-views, and reinhardt-auth.

## When to Use

- User creates or modifies API endpoints
- User works with serializers, views, or URL routing
- User configures authentication or authorization
- User mentions: "API", "endpoint", "serializer", "view", "ViewSet", "routing", "authentication", "REST", "pagination"

## Workflow

### Creating a New API Endpoint

1. **Define Serializer** — read `references/serializer-patterns.md`
2. **Implement View** — read `references/view-patterns.md`
3. **Configure Routing** — read `references/routing-guide.md`
4. **Set Up Auth** — read `references/auth-config.md` (if needed)
5. **Test** — use the testing skill for API testing guidance

## Important Rules

- Every endpoint MUST have appropriate authentication/authorization
- Use `ModelSerializer` for standard CRUD operations
- Keep simple `Model::objects()` CRUD in the handler/server_fn; do not introduce semantic wrappers such as `get_project_model`, `list_document_chunks`, or `document_path` when they only hide a direct ORM call
- For model-backed DTOs in 0.2.x, prefer the generated `{Model}Info` type plus `Validate`/`#[validate(...)]` over hand-maintained duplicate field shapes
- **(0.4.0; #5543)** For a named write DTO shared by REST, `#[server_fn]`, or WebSocket client/server code, use `#[dto]` with unconditional `#[validate(...)]` rules; keep serde and optional OpenAPI `Schema` derives explicit, and revalidate after the payload reaches the server
- For user-facing writes that reference related models, accept representative values such as `title`, `name`, or `slug` and resolve them server-side; raw FK primary-key input is reserved for internal/admin-only or machine APIs
- Use `reinhardt-query` for custom queries, NEVER raw SQL
- Scoped endpoints must apply the same target scope to every backend path, including fallback filename, filesystem, and hybrid-search branches
- `#[server_fn]` is for Pages client RPC; external workers and agent services should use explicit HTTP or gRPC endpoints with configured domains
- Server-side prompt endpoints and generated text APIs must use `reinhardt-i18n` / locale-aware settings for language-specific output
- For Pages `#[server_fn]` business logic, inject shared keyed services with `Depends<K, T>` rather than constructing settings directly in the request boundary
- In Pages component files, import DTOs, route helpers, serializers, server functions, and shared components at module scope; avoid repeated full `crate::...` paths inside `page!`, event handlers, and small helpers
- Prefer DI services over utility-function clusters when endpoint or server-function behavior needs settings, providers, repositories, external I/O, lifecycle scoping, or test overrides
- Keep app `services/` modules limited to DI keys, providers, and service structs/functions; put provider adapters, prompt builders, parsers, converters, repository/database helpers, and pure helpers under app-local `server/` modules
- Do not move the same endpoint control flow into `server/`, `service/`, or `services/` only to shorten a handler; extract only for a narrower contract, shared dependency, or independently testable invariant
- Inline and delete single-use delegated helpers when they only pass through one endpoint's request, dependencies, and persistence/provider sequence
- Do not add top-level free helpers under app `server/` modules for exactly one production call site; inline the logic unless the helper has a reusable domain contract, isolates genuinely complex behavior with a clear operational name, or is expected to gain more call sites
- Follow the Django-parity app boundary: every user-facing endpoint belongs to an app, including endpoints in minimal services and benchmarks with only one or two handlers
- Define HTTP endpoint handlers in `src/apps/<app>/views.rs` and Pages `#[server_fn]` functions in `src/apps/<app>/server_fn.rs` (or app-local equivalents), then register them in an app-local router; `src/config/urls.rs` only composes app routers and framework-level routes, and MUST NOT define application endpoint handlers directly
- Keep endpoint decorator paths app-local; compose app/API prefixes in route modules or `*_urls.rs`, not inside handler paths or function bodies
- Import request, DTO, and framework types at module scope instead of using long fully qualified paths inside handler or server function signatures/bodies
- Preserve streamed text exactly unless normalization is part of the product requirement; do not collapse prose with `split_whitespace()`
- Implement `From` for custom response DTOs and call `.into()` at mapping sites instead of repeating manual field-by-field conversions
- Do not serialize absent typed identifiers as empty strings; drop the item or return an explicit optional/error shape
- ALL code comments must be in English
- `#[url_patterns]` is removed in 0.2.x -- use `#[routes]` for all URL registration
- In 0.3.x, raw server-route registration (`ServerRouter::function`, `.route`, `.handler_with_method`, and named variants) is removed from the public migration surface — use `#[get]` / `#[post]` / endpoint macros plus `.endpoint(factory)`
- `FunctionHandler` is not a public app-facing registration type in 0.3.x; keep `.view(...)` / `.view_named(...)` only for intentional class-style `Handler` implementations
- Use `CurrentUser<T>` for full authenticated-user extraction; migrate legacy `AuthUser<T>` before upgrading to 0.3.x

## Cross-Domain References

- Model definitions: `../modeling/references/model-patterns.md`
- DI for services: `../dependency-injection/references/di-patterns.md`

## Dynamic References

For the latest API:

1. Read `reinhardt/crates/reinhardt-rest/src/lib.rs` for serializer and REST types
2. Read `reinhardt/crates/reinhardt-views/src/lib.rs` for view patterns
3. Read `reinhardt/crates/reinhardt-urls/src/lib.rs` for URL routing
4. Read `reinhardt/crates/reinhardt-auth/src/lib.rs` for auth backends
