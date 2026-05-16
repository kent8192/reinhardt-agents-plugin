---
description: Upgrade reinhardt-web version with guided migration analysis, breaking change detection, and code modification assistance
---

# Reinhardt Version Upgrade

You are guiding the user through upgrading their reinhardt-web dependency. Follow this workflow:

## Step 1: Detect Current Version

Read the project's `Cargo.toml` and extract the current reinhardt version:
- Look for `reinhardt = { version = "..." }` in `[dependencies]`
- Report the detected version to the user

If no reinhardt dependency is found, inform the user this command is for reinhardt-web projects only.

## Step 2: Ask Target Version

Ask the user which version they want to upgrade to:
- Accept specific versions (e.g., `0.1.0-rc.22`)
- Accept `latest` — resolve via `gh release list -R kent8192/reinhardt-web --limit 1` or by reading `reinhardt/Cargo.toml` if the repo is available locally
- If the target is the same as current, inform the user and exit

## Step 3: Confirm

Present the upgrade plan:
> Upgrading reinhardt: **{current}** → **{target}**
>
> This will:
> 1. Analyze CHANGELOG and GitHub PRs for breaking changes
> 2. Scan your code for deprecated API usage
> 3. Guide you through necessary code modifications
> 4. Update Cargo.toml and verify with cargo check
>
> Proceed?

## Step 4: Invoke Migration Skill

After confirmation, invoke the migration skill which handles:
- Dispatching the migration-analyzer agent for impact analysis
- Presenting the migration report
- Guiding code modifications
- Verification with cargo check/test

## Pre-Flight Checks

Before starting, verify:
- Git working tree is clean (`git status --porcelain` returns empty)
- If not clean, warn the user and recommend committing or stashing first
- This ensures safe rollback if needed
