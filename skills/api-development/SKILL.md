---
name: api-development
description: Use when building REST API endpoints with reinhardt-web - covers serializers, views, URL routing, authentication, and pagination
versions: ["0.1.2", "0.2.x"]
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
- Use `reinhardt-query` for custom queries, NEVER raw SQL
- ALL code comments must be in English
- `#[url_patterns]` is removed in 0.2.x -- use `#[routes]` for all URL registration

## Cross-Domain References

- Model definitions: `${CLAUDE_PLUGIN_ROOT}/skills/modeling/references/model-patterns.md`
- DI for services: `${CLAUDE_PLUGIN_ROOT}/skills/dependency-injection/references/di-patterns.md`

## Dynamic References

For the latest API:
1. Read `reinhardt/crates/reinhardt-rest/src/lib.rs` for serializer and REST types
2. Read `reinhardt/crates/reinhardt-views/src/lib.rs` for view patterns
3. Read `reinhardt/crates/reinhardt-urls/src/lib.rs` for URL routing
4. Read `reinhardt/crates/reinhardt-auth/src/lib.rs` for auth backends
