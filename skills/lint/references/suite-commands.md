# Static Analysis Suite — Command Reference

All commands should be run from the project root directory.

---

## 1. Formatting

**Check (no changes):**

```bash
cargo make fmt-check
```

**Auto-fix:**

```bash
cargo make fmt-fix
```

Underlying command: `cargo fmt --all -- --check`

---

## 2. Clippy Linting

**Check (no changes):**

```bash
cargo make clippy-check
```

**Auto-fix (safe fixes only):**

```bash
cargo make clippy-fix
```

Underlying command: `cargo clippy --workspace --all-features -- -D warnings`

---

## 3. TODO/FIXME Detection

**Check for new TODOs in PR diff:**

```bash
cargo make clippy-todo-check
```

Rules:

- New `todo!()`, `// TODO`, `// FIXME` in PR diff are blocked by CI
- `unimplemented!()` is exempt (for permanently excluded features)
- Existing TODOs are not flagged (diff-aware)

---

## 4. Rustdoc Validation

**Build docs and check for warnings:**

```bash
cargo doc --no-deps
```

For workspace-wide check with all features:

```bash
cargo doc --workspace --no-deps --all-features
```

CI runs with `-D warnings`, so any warning is a build failure.

---

## 5. Semgrep Security Scan

**Full scan:**

```bash
docker run --rm -v "$(pwd):/src" semgrep/semgrep semgrep scan --config .semgrep/ --error --metrics off
```

**Diff-aware scan (for PRs):**

```bash
docker run --rm -v "$(pwd):/src" semgrep/semgrep semgrep scan --config .semgrep/ --baseline-commit origin/main --error --metrics off
```

---

## 6. Dependency Audit

**Check for known vulnerabilities:**

```bash
cargo make audit
```

Underlying command: `cargo audit`

---

## Recommended Execution Order

Run checks in this order because earlier checks can affect later results:

| Order | Check | Why first |
|-------|-------|-----------|
| 1 | fmt | Unformatted code can cause false clippy positives |
| 2 | clippy | Must pass before doc/semgrep checks |
| 3 | todo-check | Quick scan, independent |
| 4 | rustdoc | Requires code to compile cleanly |
| 5 | semgrep | Independent security scan |
| 6 | audit | Independent dependency check |

## Full Suite One-Liner

```bash
cargo make fmt-check && cargo make clippy-check && cargo make clippy-todo-check && cargo doc --no-deps && cargo make audit
```

Note: semgrep requires Docker and is typically run separately.
