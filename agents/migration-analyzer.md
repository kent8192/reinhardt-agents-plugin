---
description: Analyzes reinhardt version upgrade impact by cross-referencing CHANGELOG entries, GitHub PR/Issue descriptions, deprecated API annotations, and application code usage. Returns structured migration report.
capabilities: ["changelog-analysis", "deprecated-api-detection", "github-context-enrichment", "app-code-scanning"]
---

# Migration Analyzer Agent

Specialized agent for analyzing the impact of reinhardt-web version upgrades.

## Invocation

Called by the migration skill with:

- `current_version`: Current reinhardt version from Cargo.toml
- `target_version`: Target version specified by user
- `app_code_path`: Path to user's application source code

## Version Family Detection

Before analysis, determine the version families involved:

- **0.1.x family**: `0.1.0-rc.*`, `0.1.0`, `0.1.1`, `0.1.2`, `0.1.3` — legacy stable series
- **0.2.x family**: `0.2.0-rc.*`, `0.2.0`, `0.2.1`, `0.2.2` — stable 0.2 line with breaking changes from 0.1.x
- **0.3.0 family**: `0.3.0-alpha.*`, `0.3.0-rc.*`, `0.3.0` — next major stable line
- **Cross-family upgrade** (0.1.x → 0.2.0): Flag as a **major version migration** with extensive breaking changes. Use the migration skill's "Major Version Upgrade: 0.1.x → 0.2.0" section and milestone #1 for the comprehensive migration path.
- **Cross-family upgrade** (0.2.x → 0.3.0): Flag as a **major version migration**. Use `../skills/migration/references/0.3-upgrade.md` and prefer `reinhardt/instructions/MIGRATION_0.3.md` when the local source checkout is available.

## Analysis Steps

Execute these steps in order:

### Step 1: CHANGELOG Extraction

1. Read `reinhardt/CHANGELOG.md` (main changelog)
2. Read per-crate changelogs at `reinhardt/crates/*/CHANGELOG.md` for crates used by the app
3. Extract entries between `current_version` and `target_version`
4. Focus on: **Changed**, **Deprecated**, **Removed** sections (these require action)
5. Also note **Added** (informational)

Reference: `../skills/migration/references/changelog-format.md`

For 0.2.x → 0.3.0 upgrades, read `reinhardt/instructions/MIGRATION_0.3.md`
before CHANGELOG extraction when it exists. If it is unavailable, read
`../skills/migration/references/0.3-upgrade.md` and treat it as the fallback
source map for removed APIs, Pages layout changes, DI identity changes, routing
changes, model-info relation shape changes, and migration verification.

### Step 2: GitHub Context Enrichment

For each CHANGELOG entry referencing a PR number `(#NNN)`:

1. Run `gh pr view NNN -R kent8192/reinhardt-web --json body,title`
2. Extract migration-relevant information from the PR body
3. If the PR references issues, run `gh issue view NNN -R kent8192/reinhardt-web --json body,title`
4. Look for migration guides, before/after examples, or breaking change descriptions

### Step 3: Deprecated API Detection

1. Grep reinhardt source for `#[deprecated(since = "...")]`

   ```bash
   grep -rn '#\[deprecated' reinhardt/crates/ --include='*.rs'
   ```

2. Filter: only include entries where `since` version is between `current_version` and `target_version`
3. Extract the `note` field for each deprecated item (contains replacement guidance)
4. Identify the deprecated symbol name (type, function, method, trait)

### Step 4: Application Code Scan

For each deprecated or removed API identified in Steps 1-3:

1. Grep the user's application code for usage:

   ```bash
   grep -rn 'DeprecatedSymbolName' <app_code_path>/src/ --include='*.rs'
   ```

2. Record file paths and line numbers
3. Cross-reference with the replacement guidance from `#[deprecated(note)]`

### Output Format

Return a structured report in this format:

```markdown
## Migration Report: {current_version} → {target_version}

### Summary
- Breaking changes: N
- Deprecated APIs: N
- New features: N
- Files affected in your application: N

### Breaking Changes (action required)

#### 1. [crate-name] Description
- **Source**: CHANGELOG entry + PR #N
- **Context**: (from PR/Issue description — migration details)
- **Impact**: Affected files in your application
  - `src/path/file.rs:LINE` — usage description
- **Migration**:
  ```rust
  // Before
  old_code();
  // After
  new_code();
  ```

### Deprecated APIs (should migrate)

#### 1. `OldType` → `NewType`

- **Since**: version
- **Note**: (from #[deprecated] note attribute)
- **Used in**:
  - `src/path/file.rs:LINE`
- **Migration**:

  ```rust
  // Before
  use reinhardt::OldType;
  // After
  use reinhardt::NewType;
  ```

### New Features (informational)

- [crate-name] Description — available for adoption

```markdown

## Important Rules

- ALWAYS read actual CHANGELOG content — do not guess or assume changes
- ALWAYS verify PR/Issue details via `gh` CLI — do not fabricate context
- ONLY report deprecated APIs whose `since` version falls in the upgrade range
- ONLY report application code usage that actually exists (verified by grep)
- If reinhardt source is not available locally, note it, skip only the source-only deprecated annotation scan in Step 3, and still run Step 4 application scans using bundled fallback symbols when available
- If `gh` CLI fails, note the error and continue with CHANGELOG-only analysis
- For 0.1.x → 0.2.x upgrades, include ALL breaking changes from the "Major Version Upgrade" reference in the report, even if the user's code doesn't directly use the affected APIs (they may use them transitively)
- For 0.1.x → 0.2.x upgrades, also check `reinhardt/announcements/v0.2.0-rc.N.md` for 0.2.x-series release notes
- For 0.2.x → 0.3.0 upgrades, include ALL removed APIs and layout migrations from `MIGRATION_0.3.md` or `0.3-upgrade.md`, even when the app scan only finds a subset
- For 0.2.x → 0.3.0 upgrades, explicitly scan for `AuthUser`, `create_resource*`, `use_effect_event*`, raw `ServerRouter` function/route registration, `FunctionHandler`, `DependsResult`, `DependsOption`, `pages.rs`, `server_urls`, `client/pages`, and broad `src/shared/forms.rs` / `src/shared/types.rs` usage
