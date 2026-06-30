---
name: lint
description: Use when running static analysis, fixing lint errors, or preparing code for commit - covers the full cargo/clippy/rustdoc/semgrep suite with fix-iterate workflow
versions: ["0.1.x", "0.2.x", "0.3.x"]
---

# Reinhardt Static Analysis & Linting

Run the full static analysis suite and iteratively fix issues. Covers formatting, linting, documentation, security scanning, and dependency auditing.

## When to Use

- User asks to lint, format, or check code quality
- Before creating a commit or pull request
- After making code changes that may introduce warnings
- User mentions: "lint", "clippy", "fmt", "format", "static analysis", "code quality", "semgrep", "audit", "rustdoc warnings", "check before commit"

## Workflow

### Full Analysis Suite

Run all checks in order. Read `references/suite-commands.md` for exact commands and flags.

1. **Format check** — `cargo make fmt-check`
2. **Clippy lint** — `cargo make clippy-check`
3. **TODO check** — `cargo make clippy-todo-check`
4. **Rustdoc validation** — `cargo doc --no-deps`
5. **Semgrep scan** — `semgrep scan --config .semgrep/`
6. **Dependency audit** — `cargo make audit`

### Fix-Iterate Pattern

When issues are found:

1. Run the failing check
2. Fix the reported issues
3. Re-run the same check to verify the fix
4. Move to the next check in the suite
5. After all checks pass, do a final full run to catch cross-tool issues

### Quick Fix Commands

- Format: `cargo make fmt-fix`
- Clippy auto-fix: `cargo make clippy-fix`
- Manual fixes: required for rustdoc, semgrep, and audit issues

### Diff-Aware Scanning (for PRs)

For checking only changes relative to main:

```bash
semgrep scan --config .semgrep/ --baseline-commit origin/main --error --metrics off
```

### 0.3 Migration Scans

When checking 0.3.x readiness, run the migration-guide scans before the normal
suite:

```bash
SCAN_DIRS=()
for dir in src crates examples; do
  [ -d "$dir" ] && SCAN_DIRS+=("$dir")
done

if [ "${#SCAN_DIRS[@]}" -eq 0 ]; then
  echo "No src/, crates/, or examples/ directories found to scan."
else
  rg -n "AuthUser|create_resource|create_resource_with_deps|use_effect_event|use_effect_event_with" "${SCAN_DIRS[@]}"
  rg -n "\\.(function|route|handler_with_method)(_named)?\\(|FunctionHandler|Depends(Result|Option)" "${SCAN_DIRS[@]}"
  rg -n "FactoryOutput<|Depends<[^,>]+>|injectable_factory|InjectableKey" "${SCAN_DIRS[@]}"
  rg --files "${SCAN_DIRS[@]}" | rg '(^|/)(pages\.rs|server_urls\.rs|client/pages(/|\.rs$)|src/shared/(forms|types)\.rs$)'
fi
```

## Important Rules

- Fix formatting FIRST — clippy may report different issues on unformatted code
- ALL `#[allow(...)]` attributes MUST have an explanatory comment
- NEVER silence semgrep findings without understanding the security implication
- Rustdoc warnings with `-D warnings` will fail CI — fix locally before pushing
- Prefer named functions for exported service handlers/fakes over exported lambda expressions when interop or test discovery relies on stable names
- Remove redundant raw identifiers (`r#name`) when the identifier is not a Rust keyword in that position
- Run `cargo doc --no-deps` locally before pushing doc-related changes
- For 0.3.x upgrades, treat matches from the 0.3 migration scans as migration work, not ordinary lint noise
- Known gotchas: read `references/known-gotchas.md` before investigating unfamiliar warnings

## Cross-Domain References

- Code style rules: see project CLAUDE.md § Rustdoc Formatting Rules
- CI commands: see project CLAUDE.md § CI Commands
- Testing after fixes: `../testing/references/rstest-patterns.md`

## Dynamic References

For the latest lint configuration:

1. Read `reinhardt/Makefile.toml` for cargo-make task definitions
2. Read `reinhardt/.semgrep/` for custom semgrep rules
3. Read `reinhardt/clippy.toml` or `reinhardt/.clippy.toml` for clippy configuration (if exists)
4. Read `reinhardt/instructions/MIGRATION_0.3.md` before adding or changing 0.3.x migration checks
