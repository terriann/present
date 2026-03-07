---
name: ship
description: Push the current branch, create a PR with issue references, and run benchmarks against the PR base branch.
argument-hint: "[optional: base branch, extra context]"
---

# Ship — Push, PR, and Benchmark

Push the current feature branch, create a pull request that enumerates all addressed issues, and run performance benchmarks comparing against the PR's base branch.

## Input

The user's input: $ARGUMENTS

Parse for optional overrides:
- **Base branch** — If the user specifies a base branch (e.g., `--base develop`), use it. Otherwise default to `main`.
- **Extra context** — Any additional instructions for the PR description (e.g., "mention the breaking change in session output").

## Phase 1: Push

1. Run `git status` to confirm the working tree is clean. If there are uncommitted changes, stop and ask the user whether to commit first or proceed with only committed changes.
2. Check if the current branch tracks a remote and whether it's up to date.
3. Push the current branch to origin with `-u` to set upstream tracking:
   ```bash
   git push -u origin HEAD
   ```
4. Note the branch name and remote URL for later use.

## Phase 2: Create the Pull Request

### 2a. Gather Context

Collect everything the commit-pr-writer agent needs — do this research yourself, then pass the results as context.

1. **Determine the base branch.** Use the user-specified base, or default to `main`.
2. **Fetch the latest base branch from origin** so comparisons reflect the remote state (local `main` may be stale):
   ```bash
   git fetch origin <base>
   ```
3. **Get the full diff and commit history** against the remote base branch:
   ```bash
   git log --oneline origin/<base>..HEAD
   git diff origin/<base>...HEAD --stat
   ```
3. **Find addressed issues.** Search the commit messages and diff for GitHub issue references (`#123`, `Closes #123`, `Fixes #123`, `Resolves #123`, `Addressing #123`, `Related to #123`, `Part of #123`). For each referenced issue, fetch its title:
   ```bash
   gh issue view <number> --json title,state,url,milestone --jq '"\(.title) (\(.state)) \(.url) milestone:\(.milestone.title // "none")"'
   ```
4. **Determine milestone.** Pick the milestone that appears most frequently across the referenced issues. If no issues have a milestone, fall back to checking the branch name for a version (e.g., `feat/0.2.0`) and look for a matching milestone. If neither produces a result, skip milestone assignment.

### 2b. Delegate to commit-pr-writer

Delegate the PR description to the commit-pr-writer agent with the following project-specific context:

> **Project context for PR description:**
>
> - This is a macOS time tracking app (SwiftUI + CLI) called Present.
> - Use conventional commit format for the PR title: `type(scope): description` (see CLAUDE.md for types and scopes).
> - The PR description must include a **Referenced Issues** section that lists every GitHub issue addressed by commits in this branch. For each issue, use the full issue URL (e.g., `https://github.com/owner/repo/issues/N`) — do not wrap it in markdown link syntax. GitHub auto-links plain URLs. Prefix with closing keywords (`Closes`) for issues fully resolved by this PR, or `Related to` for partial progress.
> - If the user provided extra context in $ARGUMENTS, incorporate it into the description.
> - Keep the PR title under 70 characters.
> - Structure: Summary (2-3 bullets), Referenced Issues, Test Plan.
> - Default base branch: `main` unless overridden.

Pass the commit history, diff stat, and issue list you gathered in 2a to the agent.

### 2c. Create the PR

After the commit-pr-writer drafts the PR description:

1. Show the draft title and body to the user for approval.
2. Create the PR:
   ```bash
   gh pr create --base <base-branch> --title "<title>" --body "<body>"
   ```
3. If a milestone was determined (from issues or branch name), assign it:
   ```bash
   gh pr edit <number> --milestone "<milestone>"
   ```
4. Output the PR URL.

## Phase 3: Run Benchmarks

After the PR is created:

1. Run the benchmark script comparing against the PR's base branch:
   ```bash
   bash Scripts/benchmark.sh --baseline <base-branch>
   ```
2. **Post the benchmark results as a PR comment** automatically:
   ```bash
   gh pr comment <pr-number> --body "<benchmark markdown output>"
   ```
3. **Add the `has:benchmark` label** to the PR:
   ```bash
   gh pr edit <pr-number> --add-label "has benchmark"
   ```
4. When benchmarks complete, display the results summary.
5. If any regressions are detected (warning or rotating_light indicators in the output), delegate to the code-reviewer to assess if it's a real concern with this changeset, then flag it to the user for assessment.

## Rules

- **Always push before creating the PR.** The remote branch must exist.
- **Always delegate PR description writing** to the commit-pr-writer agent with the project context above. Never write the PR description directly.
- **Always enumerate issues.** The Referenced Issues section is mandatory. If no issues are referenced in commits, ask the user if there are related issues to include.
- **Always run benchmarks.** Do not skip Phase 3 unless the user explicitly says to.
- **Never force push.** Use regular `git push`. If the push is rejected, ask the user how to proceed.
- **Show the PR draft** before creating it. Let the user adjust title, body, or base branch.
- **Benchmark failures are not blockers** unless the user says so. Flag regressions but don't refuse to ship.
