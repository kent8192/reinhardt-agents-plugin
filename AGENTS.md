# AGENTS.md

## Purpose

This file contains project-specific instructions for the reinhardt-agent-plugin repository.
reinhardt-agent-plugin is the official Claude Code and Codex plugin for the Reinhardt family of repositories
(reinhardt-web, reinhardt-cloud, awesome-delions, reinhardt-agent-plugin). It provides skills,
agents, hooks, and commands used by Claude Code and Codex when working in those repositories.

For the Claude Code plugin structure, see `.claude-plugin/`. For the Codex plugin
structure, see `.codex-plugin/`.

---

## Project Overview

**Repository URL**: https://github.com/kent8192/reinhardt-agent-plugin

reinhardt-agent-plugin is a plugin workspace — it does not contain Rust code or tests. The
"code" in this repo is skill definitions (`.md` files), agent manifests, hooks
(`.sh`/TypeScript), and commands. The primary Reinhardt coding standards live in the
`reinhardt-web` and `reinhardt-cloud` repositories; this file covers contributor
guidelines specific to this plugin repo.

---

## Critical Rules

### Documentation

**AGENTS.md ↔ CLAUDE.md Sync Policy:**
- `AGENTS.md` (Codex) and `CLAUDE.md` (Claude Code) are deliberate mirror copies kept in sync
- The two files MUST differ only on a small set of mechanical substitutions:
  - `AGENTS.md` ↔ `CLAUDE.md` (title, references)
  - `AGENTS.local.md` ↔ `CLAUDE.local.md`
  - `Codex attribution` ↔ `Claude Code attribution`
- **MUST**: Any edit to one file MUST be mirrored into the other in the same commit
- **MUST**: After editing, run `diff CLAUDE.md AGENTS.md` and confirm only the documented substitutions remain
- **NEVER**: Commit a change that touches only one of the two files

### Git Workflow

**Commit Policy:**
- **NEVER** commit without explicit user instruction
- **NEVER** push without explicit user instruction
- **EXCEPTION**: Plan Mode approval is considered explicit commit authorization
  - When user approves a plan via Exit Plan Mode, implementation and commits are both authorized
  - Upon successful implementation, all planned commits are created automatically without additional confirmation
  - If implementation fails or tests fail, NO commits are created (report to user instead)
- **EXCEPTION (Reinhardt family)**: When operating inside `reinhardt-web` / `reinhardt-cloud` / `awesome-delions` / `reinhardt-agent-plugin`, the **Autonomous Operation Policy** below authorizes commit and push on any non-protected branch (plus Draft PR / Issue creation) without further confirmation — see the next subsection
- Split commits by specific intent (NOT feature-level goals)
- Each commit MUST be small enough to explain in one line

**Autonomous Operation Policy (Reinhardt Family):**

This is an explicit, named exception to "NEVER commit/push without explicit user instruction" (Commit Policy above) and to the "Authorization = explicit user instruction OR Plan Mode approval" requirement in the GitHub Comments policy.

Scope (applies only when the working directory is inside one of these four repositories):

- `kent8192/reinhardt-web`
- `kent8192/reinhardt-cloud`
- `kent8192/awesome-delions`
- `kent8192/reinhardt-agent-plugin`

Autonomously Allowed (no per-action confirmation required):

| Operation | Constraint |
|-----------|------------|
| `git commit` | On any non-protected branch |
| `git push` | On any non-protected branch (`feature/...`, `fix/...`, `refactor/...`, `docs/...`, `chore/...`, `test/...`, `perf/...`, `debug/...`, etc.); **never** on `main`, `master`, `develop/*`, or `release/*` |
| Create a **Draft** Pull Request | `gh pr create --draft` / MCP `create_pull_request` with `draft=true`; body MUST follow `.github/PULL_REQUEST_TEMPLATE.md` |
| Convert Draft PR to **Ready for Review** | **Implementation-complete is the only readiness criterion** — CI completion is **not** required (overrides any "CI green" criterion elsewhere in this document or in `instructions/`) |
| Create an Issue | `gh issue create` / MCP `issue_write`; MUST follow the appropriate issue template and apply at least one type label |

**Protected Branches** (commit/push always require explicit user authorization):
- `main`, `master`
- `develop/*` (any branch starting with `develop/`)
- `release/*` (any branch starting with `release/`)

Still Requires Explicit User Authorization (no autonomy):

- Direct push to any protected branch listed above
- `git push --force`, `--force-with-lease`, or any other history-rewriting push
- `git rebase`, `git reset --hard`, `git branch -D`, deleting tags, or any other history-destructive operation
- Closing, merging, or deleting PRs
- Closing or deleting Issues, comments, or review threads
- Creating release tags or any PR carrying the `release` label
- Posting comments / replies / reviews on PRs/Issues — the comment-posting authorization model in `instructions/GITHUB_INTERACTION.md` PP-1 is unchanged; the autonomous policy covers only the **creation** of commits, pushes, Draft PRs, and Issues, not commenting

Unchanged Quality Guardrails (apply equally to autonomous operations):

- PR title and body MUST follow Conventional Commits and `.github/PULL_REQUEST_TEMPLATE.md`
- Issue body MUST follow `.github/ISSUE_TEMPLATE/*.yml`
- Branch naming, commit message format, Codex attribution footer, English-only policy, and all other rules in this document remain in force

**Branch Operations:**
- When merging branches and resolving conflicts, execute immediately without entering Plan Mode
- Before creating branches, verify names don't conflict with existing ones using `git worktree list` and `git branch -a`

**GitHub Integration:**
- **MUST** use GitHub CLI (`gh`) for all GitHub operations
- For usage questions, prefer GitHub Discussions over Issues
- When GitHub MCP tools return errors (e.g., 404), immediately fall back to `gh` CLI instead of retrying

**GitHub Comments & Interactions:**
- **NEVER** post comments on PRs or Issues without authorization
- Authorization = explicit user instruction OR Plan Mode approval
- Self-initiated comments MUST be previewed and approved by user before posting
- ALL comments MUST be in English and include Codex attribution footer
- **Reinhardt family scope note**: The Autonomous Operation Policy authorizes *creation* of Draft PRs and Issues without further confirmation in the four Reinhardt-family repos, but *commenting* on PRs/Issues remains fully subject to the rules above

### File Management

- **NEVER** save temp files to project directory (use `/tmp`)
- **IMMEDIATELY** delete `/tmp` files when no longer needed

---

## Common Commands

**GitHub Operations:**
```bash
gh pr create --draft --title "feat(skill): ..." --label enhancement
gh issue create --title "Bug: ..." --body "..."
gh pr list --state open
```

---

## Quick Reference

### ✅ MUST DO
- Write ALL commit messages, PR descriptions, and documentation in English
- Wait for explicit user instruction before commits (except where the Autonomous Operation Policy applies)
- Treat the Autonomous Operation Policy (Reinhardt family) as a standing exception that allows commit and push on any non-protected branch (anything other than `main`/`master`/`develop/*`/`release/*`), Draft PR creation, Draft→Ready conversion (implementation-complete only — no CI requirement), and Issue creation without further confirmation
- When editing `AGENTS.md` or `CLAUDE.md`, mirror the change into the other file in the same commit (AGENTS.md ↔ CLAUDE.md sync policy)
- Follow Conventional Commits v1.0.0 format: `<type>[scope]: <description>`
- Start commit description with lowercase letter
- Use `!` notation for breaking changes
- Apply at least one type label to every Issue and PR

### ❌ NEVER DO
- Commit without user instruction (except Plan Mode approval or the Autonomous Operation Policy for Reinhardt-family repos)
- Push directly to any protected branch (`main`, `master`, `develop/*`, `release/*`) — even under the Autonomous Operation Policy these require explicit user authorization
- Force-push, rebase-and-push, or otherwise rewrite history without explicit user authorization
- Close, merge, or delete PRs / Issues / comments without explicit user authorization (autonomy covers creation only, not destruction)
- Create release tags or any PR with the `release` label without explicit user authorization
- Commit a change that touches only `AGENTS.md` without mirroring it into `CLAUDE.md` (and vice versa)
- Post GitHub comments without authorization
- Skip Codex attribution footer on GitHub comments

---

**Note**: This AGENTS.md covers contributor guidelines specific to the reinhardt-agent-plugin plugin repository. For Reinhardt coding standards (Rust, testing, architecture), see the `reinhardt-web` or `reinhardt-cloud` AGENTS.md.
