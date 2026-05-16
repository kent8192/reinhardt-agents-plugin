---
name: migration
description: Use when upgrading reinhardt-web versions or replacing deprecated APIs - analyzes CHANGELOG, detects deprecated API usage, and guides code migration
---

# Reinhardt Migration

Guide developers through reinhardt-web version upgrades and deprecated API replacement.

## When to Use

- User wants to upgrade reinhardt version
- User needs to fix deprecated API warnings
- User mentions: "upgrade", "update reinhardt", "migrate", "deprecated", "version up", "CHANGELOG", "breaking change", "rc.XX"

## Workflow

### Phase 1: Analysis (delegated to migration-analyzer agent)

Dispatch the **migration-analyzer agent** with:
- Current reinhardt version (from Cargo.toml)
- Target version (from user)
- Path to user's application code

The agent returns a structured migration report covering breaking changes, deprecated APIs, and new features.

### Phase 2: Planning

Based on the agent's report:
1. Present the migration report to the user
2. Categorize by priority:
   - **Breaking Changes** — must fix for compilation
   - **Deprecated APIs** — should fix to avoid future breakage
   - **New Features** — informational, optional adoption
3. Propose a migration task list with ordering
4. Get user confirmation before proceeding

### Phase 3: Execution

For each migration task:
1. Update `Cargo.toml` reinhardt version to target
2. For each breaking change:
   - Show change context (from CHANGELOG + PR/Issue)
   - Show affected locations in application code
   - Guide the code modification with before/after examples
3. For each deprecated API:
   - Show `#[deprecated(note)]` replacement guidance
   - Show affected locations in application code
   - Guide the replacement
4. Run `cargo check` after each batch of changes
5. Run `cargo test` (if tests exist) for regression verification
6. Summarize completed migrations

## Important Rules

- ALWAYS present the migration report to the user before making changes
- NEVER modify code without user confirmation
- For multi-version hops (e.g., rc.18 → rc.22), review each intermediate version's changes — see `references/upgrade-workflow.md` for the worked rc.18 → rc.22 example covering the rc.19 `urls/` directory move and the rc.22 `form!` `strip_arguments` migration
- After all migrations, run `cargo check` and `cargo test` to verify
- If `cargo check` fails after migration, diagnose and fix before proceeding

## Rollback

If migration fails or user wants to revert:
1. Revert `Cargo.toml` to original version: `git checkout Cargo.toml Cargo.lock`
2. Revert code changes: `git checkout -- src/`
3. Verify rollback: `cargo check`

## Cross-Domain References

- Model changes: `${CLAUDE_PLUGIN_ROOT}/skills/modeling/references/model-patterns.md`
- API changes: `${CLAUDE_PLUGIN_ROOT}/skills/api-development/references/view-patterns.md`
- DI changes: `${CLAUDE_PLUGIN_ROOT}/skills/dependency-injection/references/di-patterns.md`

## Dynamic References

On each invocation, read from source:
1. `reinhardt/CHANGELOG.md` and `reinhardt/crates/*/CHANGELOG.md`
2. `reinhardt/announcements/v0.1.0-rc.N.md` — per-release Highlights, Breaking
   Changes, and Related PRs (the announcement file is the canonical source for
   migration recipes that go beyond a single CHANGELOG line)
3. `#[deprecated]` annotations in reinhardt source via Grep
4. GitHub PR/Issue descriptions via `gh pr view` / `gh issue view`
5. GitHub discussions linked from announcement Breaking Changes via
   `gh api repos/kent8192/reinhardt-web/discussions/<N>` (the `gh discussion`
   subcommand is unavailable; use the REST API directly)
6. User's application code via Grep
