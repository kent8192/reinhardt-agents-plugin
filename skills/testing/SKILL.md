---
name: testing
description: Use when writing tests for reinhardt-web applications - provides rstest/AAA patterns, TestContainers setup, and API testing utilities
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Testing

Guide developers through writing high-quality tests using rstest, AAA pattern, reinhardt-test fixtures, and TestContainers.

## When to Use

- User wants to write tests for reinhardt code
- User asks about testing strategies or patterns
- User mentions: "test", "fixture", "TestContainers", "assert", "rstest", "integration test", "unit test"

## Workflow

### Writing a Single Test

1. Determine test type (unit / integration / E2E)
2. Read `references/rstest-patterns.md` for correct structure
3. Write test using rstest + AAA pattern
4. Use reinhardt-test fixtures for setup/teardown
5. Run with `cargo nextest run`

### Writing Multiple Tests

1. Follow the single test workflow for the first test
2. For bulk generation, delegate to the **test-generator agent**:
   - Agent has full knowledge of rstest, AAA, and reinhardt-test patterns
   - Returns test code + fixture definitions
   - Review generated tests before accepting

### Database Tests

1. Read `references/testcontainers.md` for container setup
2. Use rstest fixtures for PostgreSQL/MySQL/Redis containers
3. Ensure Docker Desktop is running
4. Use `#[serial(db)]` if tests share global database state

### 0.3 Migration Regression Tests

1. Run the migration skill's 0.3 scan commands before writing tests
2. Add focused regression tests for replaced APIs (`CurrentUser<T>`, keyed DI providers, endpoint registration, `use_resource`)
3. For Pages apps, verify both native and `wasm32-unknown-unknown` surfaces when shared modules rely on 0.3 inert stubs
4. For generated projects, scaffold a fresh 0.3 Pages app and compare app-local layout expectations before changing fixtures

## Important Rules

- **NEVER** use `#[test]` — always use `#[rstest]`
- **ONLY** use AAA labels: `// Arrange`, `// Act`, `// Assert`
- **NEVER** use `// Setup`, `// Execute`, `// Verify` or BDD-style labels
- AAA comments MAY be omitted when test body is 5 lines or fewer
- **PREFER** `assert_eq!` over `assert!(x.is_ok())` — check the actual value
- **ALWAYS** clean up test artifacts
- Use `#[serial(group_name)]` for tests with global state
- Every test MUST use at least one reinhardt component
- Add focused regression tests for review-found bugs before broad happy-path expansion
- In 0.3.x migrations, update stale fixtures that use `AuthUser`, `create_resource*`, `use_effect_event*`, raw `ServerRouter` registration, `DependsResult`, `DependsOption`, `pages.rs`, or `server_urls`
- When generated `{Model}Info` relation fields change shape, update serializer/browser-test expectations intentionally rather than broadening assertions

## Cross-Domain References

- Model patterns: `../modeling/references/model-patterns.md`
- API patterns: `../api-development/references/view-patterns.md`
- 0.3 migration checklist: `../migration/references/0.3-upgrade.md`

## Dynamic References

For the latest test utilities:

1. Read `reinhardt/crates/reinhardt-test/src/lib.rs` for re-exports and public API
2. Read `reinhardt/crates/reinhardt-test/src/fixtures/` for auth, admin, and E2E fixtures
3. Read `reinhardt/crates/reinhardt-testkit/src/` for APIClient, APIRequestFactory, TestContainers, and migration fixtures
4. Grep for `#[rstest]` in `reinhardt/tests/integration/` for real integration test examples
