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

## Phase 2: Local CI Checks

With GitHub Actions disabled, run CI checks locally before creating the PR. Both checks must pass before proceeding.

### 2a. Build the app

```bash
xcodegen generate && xcodebuild build -project Present.xcodeproj -scheme Present -destination 'platform=macOS'
```

If the build fails, stop and show the error output. Ask the user to fix the build before continuing.

### 2b. Regenerate CLI docs

```bash
bash Scripts/generate-cli-docs.sh
```

After running, check if `docs/cli-reference.md` has changed:

```bash
git diff --quiet docs/cli-reference.md
```

- If the file **changed**, stop and tell the user:
  > CLI reference docs are out of date. The regenerated `docs/cli-reference.md` needs to be committed before the PR can be created. Please review the diff, commit the update, and re-run `/ship`.
  Show the diff summary (`git diff --stat docs/cli-reference.md`) so the user can see what changed. Do not proceed to Phase 3.
- If the file **did not change**, continue to Phase 3.

### 2c. Run unit tests

```bash
swift test --skip PresentBenchmarks
```

If tests fail, stop and show the failures. Ask the user to fix them before continuing.

## Phase 3: Create the Pull Request

### 3a. Gather Context

Collect everything the commit-pr-writer agent needs — do this research yourself, then pass the results as context.

1. **Determine the base branch.** Use the user-specified base, or default to `main`.
2. **Fetch the latest base branch from origin** so comparisons reflect the remote state (local `main` may be stale):
   ```bash
   git fetch origin <base>
   ```
3. **Get the full diff and commit history** against the remote base branch:
   ```bash
   git log origin/<base>..HEAD
   git diff origin/<base>...HEAD --stat
   ```
   **Important:** Use `git log` (not `--oneline`) so the full commit body is visible. Issue references often appear in the body, not the subject line.
3. **Find addressed issues.** Extract all GitHub issue numbers from the full commit log programmatically — do not scan by eye:
   ```bash
   git log origin/<base>..HEAD | grep -oE '#[0-9]+' | sort -t'#' -k2 -n -u
   ```
   This catches every reference regardless of keyword (`Closes`, `Fixes`, `Resolves`, `Addressing`, `Related to`, `Part of`, or bare `#N`). For each unique issue number, fetch its details:
   ```bash
   gh issue view <number> --json title,state,url,milestone --jq '"\(.title) (\(.state)) \(.url) milestone:\(.milestone.title // "none")"'
   ```
4. **Determine milestone.** Pick the milestone that appears most frequently across the referenced issues. If no issues have a milestone, fall back to checking the branch name for a version (e.g., `feat/0.2.0`) and look for a matching milestone. If neither produces a result, skip milestone assignment.

### 3b. Delegate to commit-pr-writer

Delegate the PR description to the commit-pr-writer agent with the following project-specific context:

> **Project context for PR description:**
>
> - This is a macOS time tracking app (SwiftUI + CLI) called Present.
> - Use conventional commit format for the PR title: `type(scope): description` (see CLAUDE.md for types and scopes).
> - The PR description must include a **Referenced Issues** section. List each issue on its own line using `#N` shorthand (renders as a rich card with title, state, and labels on GitHub). Group issues under subheadings by relationship:
>   ```
>   ## Referenced Issues
>
>   ### Closes
>   - Closes #1
>   - Closes #2
>
>   ### Related
>   - #3
>   ```
>   Omit any subheading that has no issues (e.g., skip "Related" if all issues are closed by this PR).
> - If the user provided extra context in $ARGUMENTS, incorporate it into the description.
> - Keep the PR title under 70 characters.
> - Structure: Summary (2-3 bullets), Referenced Issues, Test Plan.
> - Default base branch: `main` unless overridden.

Pass the commit history, diff stat, and issue list you gathered in 3a to the agent.

### 3c. Create the PR

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

## Phase 3.5: Code Review

After the PR is created, run an automated code review of the changes.

1. **Delegate to the code-reviewer agent** in **diff review mode**. Pass it:
   - The PR number and base branch
   - Instruction to run `git diff origin/<base>...HEAD` and review only the changed code
   - The full review checklist from the code-reviewer agent applies (SOLID, safety, accessibility, database scalability, etc.)

2. **If findings exist**, post them as a PR comment and add a label:
   ```bash
   gh pr comment <pr-number> --body "<review findings>"
   gh pr edit <pr-number> --add-label "has feedback"
   ```
   The comment should:
   - Open with: "**Code Review Agent** reviewed this PR and has some feedback to consider."
   - Group findings by severity (Critical, High, Medium, Low) with counts
   - Include file paths and line numbers for each finding
   - Keep the tone advisory — these are suggestions, not blockers

3. **If no findings**, skip the comment and label. Mention to the user that the review passed clean.

4. **This phase is non-blocking.** Always proceed to Phase 4 regardless of findings.

## Phase 4: Run Benchmarks

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
- **Always run local CI checks.** Do not skip Phase 2. If the build, tests, or CLI docs check fails, stop and let the user fix it.
- **Always run benchmarks.** Do not skip Phase 4 unless the user explicitly says to.
- **Never force push.** Use regular `git push`. If the push is rejected, ask the user how to proceed.
- **Show the PR draft** before creating it. Let the user adjust title, body, or base branch.
- **Benchmark failures are not blockers** unless the user says so. Flag regressions but don't refuse to ship.
