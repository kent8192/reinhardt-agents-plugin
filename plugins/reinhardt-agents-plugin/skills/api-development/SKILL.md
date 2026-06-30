---
name: api-development
description: Use when building REST API endpoints with reinhardt-web - covers serializers, views, URL routing, authentication, and pagination
versions: ["0.1.x", "0.2.x", "0.3.x"]
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
- For model-backed DTOs in 0.2.x, prefer the generated `{Model}Info` type plus `Validate`/`#[validate(...)]` over hand-maintained duplicate field shapes
- Use `reinhardt-query` for custom queries, NEVER raw SQL
- Scoped endpoints must apply the same target scope to every backend path, including fallback filename, filesystem, and hybrid-search branches
- `#[server_fn]` is for Pages client RPC; external workers and agent services should use explicit HTTP or gRPC endpoints with configured domains
- For Pages `#[server_fn]` business logic, inject shared keyed services with `Depends<K, T>` rather than constructing settings directly in the request boundary
- Prefer DI services over utility-function clusters when endpoint or server-function behavior needs settings, providers, repositories, external I/O, lifecycle scoping, or test overrides
- Keep app `services/` modules limited to DI keys, providers, and service structs/functions; put provider adapters, prompt builders, parsers, converters, repository/database helpers, and pure helpers under app-local `server/` modules
- Do not move the same endpoint control flow into `server/`, `service/`, or `services/` only to shorten a handler; extract only for a narrower contract, shared dependency, or independently testable invariant
- Inline and delete single-use delegated helpers when they only pass through one endpoint's request, dependencies, and persistence/provider sequence
- Keep endpoint decorator paths app-local; compose app/API prefixes in route modules or `*_urls.rs`, not inside handler paths or function bodies
- Import request, DTO, and framework types at module scope instead of using long fully qualified paths inside handler or server function signatures/bodies
- Preserve streamed text exactly unless normalization is part of the product requirement; do not collapse prose with `split_whitespace()`
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
