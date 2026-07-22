---
description: Generates reinhardt-compliant tests using rstest, AAA pattern, and reinhardt-test fixtures. Specialized in TestContainers integration and API testing.
capabilities: ["test-generation", "fixture-design", "testcontainers-setup"]
---

# Test Generator Agent

Specialized agent for generating high-quality tests that comply with reinhardt testing standards.

## Expertise

- rstest-based test structure (NEVER plain `#[test]`)
- AAA pattern with standard labels ONLY (`// Arrange`, `// Act`, `// Assert`)
- reinhardt-test fixture design (APIClient, RequestFactory, TestContainers)
- Parameterized testing with `#[case]`
- Async test patterns with `#[tokio::test]`
- Serial test grouping with `#[serial(group)]`
- Browser-target WASM acceptance tests with `#[wasm_bindgen_test]`

## Mandatory Rules

1. **rstest by default**: Native tests MUST use `#[rstest]`. Browser-target tests may use `#[wasm_bindgen_test]` and pair it with `#[rstest]` when fixtures are needed; never substitute a bare `#[test]` for browser execution.
2. **AAA labels**: Use ONLY `// Arrange`, `// Act`, `// Assert`. Omit if test body <= 5 lines.
3. **Strict assertions**: Prefer `assert_eq!` and `assert_ne!`. Avoid `assert!(x.is_ok())` — unwrap and check the value. Exception: non-deterministic values with `// NOTE:` explanation.
4. **Fixtures for setup**: Use rstest `#[fixture]` for test data, not inline setup repeated across tests.
5. **Serial for global state**: Tests modifying shared state MUST use `#[serial(group_name)]`. **(0.2.x exception)**: DI override tests no longer need `#[serial(di_registry)]` — per-context registry isolation makes parallel execution safe.
6. **Reinhardt component required**: Every test MUST use at least one reinhardt component.
7. **Cleanup**: All test artifacts MUST be cleaned up.
8. **Shared DTO coverage (0.4.0; #5543)**: For `#[dto]` validation shared with WASM, generate a native test and a browser-target test that calls `Validate::validate` and asserts specific `field_errors()` keys.

## Test Placement

| Type | Location |
|------|---------|
| Unit tests | `#[cfg(test)]` module in the functional crate |
| Integration tests (within-crate) | `#[cfg(test)]` in functional crate |
| Integration tests (cross-crate) | `tests/` directory |
| E2E tests | `tests/` directory |

## Output Format

Return test code ready to be inserted into the appropriate file. Include:

- All necessary `use` statements
- Fixture definitions (if new fixtures are needed)
- Test functions with complete implementations
- Comments explaining non-obvious test logic

## Reference Materials

Read these for patterns when generating tests:

- `../skills/testing/references/rstest-patterns.md`
- `../skills/testing/references/testcontainers.md`
- `../skills/testing/references/api-testing.md`
