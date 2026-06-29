---
name: architecture
description: Use when implementing a complete feature across all reinhardt layers - guides the full workflow from model to API to tests with completion checklist
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Feature Development Architecture

Guide developers through implementing a complete feature across all reinhardt layers, from model definition to API endpoints to tests. This is the "glue" skill that ties individual skills together into a coherent workflow.

## When to Use

- User adds a new entity, resource, or feature end-to-end
- User asks about the recommended order of implementation
- User wants a checklist for feature completeness
- User mentions: "new feature", "implement entity", "full-stack", "architecture", "feature workflow", "add model with API", "implementation guide"

## Workflow

### Implementing a New Feature

Follow the 7-layer sequence. Each step references the appropriate skill for detailed guidance.

1. **Define Model** — read `references/layer-sequence.md` § Model Layer
   - Use the modeling skill: `../modeling/references/model-patterns.md`
2. **Define Serializer** — read `references/layer-sequence.md` § Serializer Layer
   - Use the API skill: `../api-development/references/serializer-patterns.md`
3. **Implement Service** — read `references/layer-sequence.md` § Service Layer
   - Use the DI skill: `../dependency-injection/references/di-patterns.md`
4. **Create API Routes** — read `references/layer-sequence.md` § API Layer
   - Use the API skill: `../api-development/references/view-patterns.md`
5. **Register Admin** — read `references/layer-sequence.md` § Admin Layer
   - Use the admin skill: `../admin/references/model-admin.md`
6. **Write Tests** — read `references/layer-sequence.md` § Test Layer
   - Use the testing skill: `../testing/references/rstest-patterns.md`
7. **Add Signals** (optional) — read `references/layer-sequence.md` § Signal Layer
   - Use the signals skill: `../signals/references/reliable-pattern.md`

### Verifying Completeness

After implementation, run through `references/completion-checklist.md` to verify all layers are properly implemented.

### Error Mapping Convention

Read `references/error-mapping.md` for the standard mapping from service-layer errors to HTTP responses.

## Important Rules

- Follow the layer sequence — earlier layers are dependencies for later ones
- Every feature MUST have tests at minimum two layers: unit (service) and integration (API)
- Services MUST return domain types, not ORM models directly
- Error types from services are mapped centrally — do not handle HTTP concerns in services
- Cross-layer operations must preserve their domain invariants: scope filters, idempotency, accepted/current version uniqueness, and ordered sibling integrity
- Research/agent services should return evidence and diagnostics only unless the feature explicitly assigns them authoring or mutation ownership
- ALL code comments must be in English
- Use `reinhardt-query` for custom queries, NEVER raw SQL
- For 0.3.x features, use endpoint macros plus `.endpoint(...)` for server routes instead of raw `ServerRouter::function` / `.route` registration
- For 0.3.x DI providers, use `#[injectable]`, `#[injectable_key]`, `FactoryOutput<K, T>`, and `Depends<K, T>` when provider output type is not a unique identity
- For 0.3.x auth, use `CurrentUser<T>` for full user extraction and remove legacy `AuthUser<T>`
- For 0.3.x model-facing APIs, review generated `{Model}Info` relation fields and avoid assuming flattened `*_id` payloads
- For Pages features, place route-backed `#[component]` wrappers under `src/apps/<app>/client/components/` and keep client/server modules split

## Cross-Domain References

- Model definitions: `../modeling/references/model-patterns.md`
- Serializer patterns: `../api-development/references/serializer-patterns.md`
- DI registration: `../dependency-injection/references/di-patterns.md`
- View patterns: `../api-development/references/view-patterns.md`
- Admin setup: `../admin/references/model-admin.md`
- Test patterns: `../testing/references/rstest-patterns.md`
- Signal patterns: `../signals/references/reliable-pattern.md`
- Auth config: `../authentication/references/auth-backends.md`
- Permissions: `../authorization/references/permissions.md`

## Dynamic References

For the latest API:

1. Read `reinhardt/src/lib.rs` for all facade re-exports
2. Read `reinhardt/crates/reinhardt-rest/src/lib.rs` for serializer types
3. Read `reinhardt/crates/reinhardt-views/src/lib.rs` for view types
4. Read `reinhardt/crates/reinhardt-core/src/signals.rs` for signal types
5. Read `reinhardt/instructions/MIGRATION_0.3.md` when designing or updating a 0.3.x feature surface
