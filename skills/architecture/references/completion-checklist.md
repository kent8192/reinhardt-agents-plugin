# Feature Completion Checklist

Run through this checklist after implementing a feature to verify all layers are complete.

---

## Model Layer

- [ ] Model defined with `#[model]` macro
- [ ] Primary key field defined
- [ ] `Option<T>` used for all nullable fields
- [ ] Timestamp fields use `auto_now_add` / `auto_now`
- [ ] Model re-exported from parent module via `pub use`
- [ ] Migration generated (`makemigrations`)
- [ ] Migration applied (`migrate`)
- [ ] Migration reviewed for correctness

## Serializer Layer

- [ ] Read serializer defined (API response)
- [ ] Write serializer / input type defined (API request)
- [ ] Field validation applied where needed
- [ ] Nested serializers for related models (if applicable)

## Service Layer

- [ ] Service struct defined with dependency fields
- [ ] `#[injectable_factory]` macro applied
- [ ] Constructor receives all dependencies via injection
- [ ] Methods return domain types, not ORM models
- [ ] Error handling uses domain error types (not HTTP status codes)
- [ ] No direct HTTP concerns in service code

## API Layer

- [ ] View functions defined with HTTP method decorators
- [ ] URL routes configured and mounted in app config
- [ ] Authentication configured (if required)
- [ ] Permission guards applied (if required)
- [ ] Error mapping verified (service errors → HTTP responses)
- [ ] Request validation via serializer/input types

## Admin Layer

- [ ] Model registered with `#[admin]` macro
- [ ] `list_display` configured (id first, max 6 fields)
- [ ] `search_fields` includes id
- [ ] `readonly_fields` includes id and auto-generated fields
- [ ] `ordering` specified
- [ ] `list_per_page` set

## Test Layer

- [ ] Unit tests for service business logic (mocked deps)
- [ ] Integration tests with TestContainers (real DB)
- [ ] API tests for HTTP endpoints
- [ ] All tests use `#[rstest]`
- [ ] AAA pattern with standard labels
- [ ] Strict assertions (`assert_eq!`, not `assert!(x.contains(...))`)
- [ ] Edge cases covered (not found, validation failure, duplicate)

## Signal Layer (if applicable)

- [ ] Signal receivers connected with `connect_receiver!`
- [ ] `dispatch_uid` set for each receiver
- [ ] Receivers are idempotent
- [ ] No cascading signal triggers
- [ ] Signal tests verify behavior in isolation

## Documentation

- [ ] Rustdoc comments on public types and methods
- [ ] All comments in English
- [ ] No `todo!()` left unresolved (or tracked in issue)

## Code Quality

- [ ] `cargo make fmt-check` passes
- [ ] `cargo make clippy-check` passes
- [ ] `cargo doc --no-deps` passes (no warnings)
- [ ] All tests pass (`cargo nextest run`)
