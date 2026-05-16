# Upgrade Workflow Reference

Comprehensive guide for the 3-phase reinhardt-web version upgrade procedure.

---

## Pre-Flight Checklist

Before starting any upgrade, verify all prerequisites are met:

1. **Clean git working tree** — run `git status --porcelain` and confirm empty output.
   If not clean, instruct the user to commit or stash changes first. A clean tree
   ensures safe rollback if the upgrade encounters issues.

2. **All tests passing** — run `cargo nextest run --workspace --all-features` (or
   `cargo test --workspace --all-features` if nextest is unavailable). Do not begin
   an upgrade on a failing test suite; pre-existing failures make it impossible to
   distinguish upgrade regressions from prior issues.

3. **Docker running** — verify with `docker info`. Required for TestContainers-based
   database tests. If Docker is not running, warn the user that integration tests
   will be skipped during verification.

4. **reinhardt source available** — confirm the `reinhardt/` directory exists locally
   (for CHANGELOG reading and deprecated API scanning). If unavailable, the analysis
   phase will rely on GitHub API only, which may be incomplete.

5. **GitHub CLI authenticated** — run `gh auth status`. Required for fetching PR/Issue
   details that provide migration context beyond CHANGELOG entries.

---

## Phase 1: Analyze

Goal: Build a complete picture of what changed between the current and target versions.

### Step 1.1 — Detect current version

Read the project's `Cargo.toml` and extract the reinhardt dependency version:
```
reinhardt = { version = "0.1.0-rc.19", features = [...] }
```

### Step 1.2 — Resolve target version

- If the user specifies an exact version (e.g., `0.1.0-rc.22`), use it directly.
- If the user says `latest`, resolve via:
  ```bash
  gh release list -R kent8192/reinhardt-web --limit 1
  ```
  Or read `reinhardt/Cargo.toml` if the repo is available locally.

### Step 1.3 — Dispatch migration-analyzer agent

The agent performs:
- CHANGELOG extraction between current and target versions
- GitHub PR/Issue context enrichment
- Deprecated API detection in reinhardt source
- Application code scanning for affected usage

The agent returns a structured migration report.

---

## Phase 2: Plan

Goal: Present findings and get user approval before making changes.

### Step 2.1 — Present migration report

Display the full report from the migration-analyzer agent, organized by priority:

1. **Breaking Changes** (action required for compilation)
   - Changed APIs, removed types, signature modifications
   - Each with affected file locations in the user's code

2. **Deprecated APIs** (should migrate to avoid future breakage)
   - APIs marked with `#[deprecated]` in the upgrade range
   - Replacement guidance from the `note` attribute

3. **New Features** (informational, optional adoption)
   - Newly added APIs and capabilities
   - No action required, but user may want to adopt

### Step 2.2 — Propose migration task list

Order tasks by dependency:
1. `Cargo.toml` version update
2. Breaking changes (compilation blockers first)
3. Deprecated API replacements
4. Optional new feature adoption

### Step 2.3 — Get confirmation

Wait for explicit user approval before proceeding to execution.

---

## Phase 3: Execute

Goal: Apply changes incrementally with verification at each step.

### Step 3.1 — Update Cargo.toml

Change the reinhardt version to the target:
```toml
reinhardt = { version = "0.1.0-rc.22", features = [...] }
```

Run `cargo check` immediately after to identify compilation errors. This surfaces
all breaking changes that need resolution.

### Step 3.2 — Fix breaking changes

For each breaking change identified by `cargo check`:
1. Show the error context and the relevant CHANGELOG/PR information
2. Show the before/after code transformation
3. Apply the fix
4. Run `cargo check` after each batch of fixes (group related fixes)

Continue until `cargo check` passes cleanly.

### Step 3.3 — Replace deprecated APIs

For each deprecated API usage:
1. Show the deprecation warning and replacement guidance
2. Show the before/after transformation
3. Apply the replacement

Run `cargo check` after all replacements to confirm no regressions.

### Step 3.4 — Final verification

1. Run `cargo check --workspace --all-features` — must pass
2. Run `cargo nextest run --workspace --all-features` — must pass
3. Run `cargo test --doc` — must pass (doc examples may reference changed APIs)
4. Run `cargo clippy --workspace --all-features -- -D warnings` — should pass

### Step 3.5 — Summary

Report to the user:
- Version upgraded: `X.Y.Z-rc.N` to `X.Y.Z-rc.M`
- Breaking changes resolved: count
- Deprecated APIs replaced: count
- All checks passing: yes/no

---

## Rollback Procedure

If the upgrade fails or the user wants to revert at any point:

### Full rollback (before any commits)

```bash
git checkout Cargo.toml Cargo.lock
git checkout -- src/
cargo check
```

This reverts all changes and returns to the pre-upgrade state.

### Partial rollback (after some commits)

If migration was committed incrementally:
```bash
git log --oneline  # find the commit before migration started
git reset --soft <pre-migration-commit>
git checkout -- .
cargo check
```

### Verification after rollback

Always run `cargo check` after rollback to confirm the project compiles at the
original version. If it does not, the rollback was incomplete — check for
uncommitted files or partial changes.

---

## Multi-Version Hop Guidance

When upgrading across multiple RC versions (e.g., `rc.18` to `rc.22`), special
care is needed because intermediate versions may have introduced breaking
scaffolding/path changes whose migration recipe lives in the version that
introduced the change, not the version you are jumping to.

### Why intermediate versions matter

Consider this scenario:
- `rc.18` introduces `ClientLauncher` and removes `--template-type` CLI flag
- `rc.19` moves `ws_url_resolvers` from `<app>/ws_urls.rs` to `<app>/urls/ws_urls.rs` (breaking)
- `rc.21` removes a stray `pub mod ws_urls` line from the app-root template
- `rc.22` generalizes implicit CSRF auto-injection into `form!` `strip_arguments`

If you jump directly from `rc.18` to `rc.22`, you see a module-not-found
compilation error for `apps::<name>::ws_urls` but miss the rc.19 release
note that explained the new layout. The CHANGELOG entry that contains the
migration recipe is in `rc.19`, not `rc.22`.

### Procedure for multi-version hops

1. **Read ALL intermediate announcements** — extract entries for every
   version between current and target, not just the target version. The
   announcement files live under `reinhardt/announcements/v0.1.0-rc.N.md`.

2. **Track each breaking change's recipe** — for every breaking change:
   - When was it introduced? (which version's CHANGELOG)
   - What is the migration step? (from that version's release notes / linked discussion)
   - Did a later version add or remove follow-up steps?

3. **Apply migrations in logical order** — fix scaffolding/path changes
   from earlier versions first, as later changes may depend on earlier
   migrations being complete.

4. **Update Cargo.toml once** — despite reviewing intermediate versions, only
   update `Cargo.toml` to the final target version. The intermediate review
   is for understanding migration paths, not for stepping through each version.

### Example: rc.18 to rc.22

```
rc.19 announcement:
  - Breaking: ws_url_resolvers path moved
    - Old: src/apps/<app>/ws_urls.rs
    - New: src/apps/<app>/urls/ws_urls.rs
    - Per-app migration:
        mkdir -p src/apps/<app>/urls
        git mv src/apps/<app>/ws_urls.rs src/apps/<app>/urls/ws_urls.rs
      Then declare in src/apps/<app>/urls.rs:
        #[cfg(server)] pub mod ws_urls;
  - Fixed: ws_urls scaffold template now returns WebSocketRouter (was ())

rc.21 announcement:
  - Fixed: stray `pub mod ws_urls` removed from app-root template
    (existing apps must remove that line manually if present)

rc.22 announcement:
  - Added: form! strip_arguments DSL — explicit CSRF / auxiliary arg routing
  - Backward-compatible: existing form! blocks still compile via the legacy
    auto-injection path; explicit migration is recommended
```

Migration order:
1. Move every `<app>/ws_urls.rs` to `<app>/urls/ws_urls.rs` (rc.19)
2. Add `#[cfg(server)] pub mod ws_urls;` inside each `<app>/urls.rs`
3. Remove the stray top-level `pub mod ws_urls;` from each app's `lib.rs`
   if your scaffold predates rc.21
4. (Optional) Migrate each `form!` block to use explicit `strip_arguments`
   for CSRF (rc.22) — see
   `${CLAUDE_PLUGIN_ROOT}/skills/macros/references/proc-macros.md`
5. Update `Cargo.toml` to `0.1.0-rc.22`
6. If any `cargo install reinhardt-admin-cli` invocation appears in
   project scripts/docs, pin it: `--version "0.1.0-rc.22"` (rc.22 quick-start fix)
7. Run `cargo check` and `cargo test`
