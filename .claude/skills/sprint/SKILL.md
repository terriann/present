---
name: sprint
description: Work through a batch of GitHub issues from a milestone. Fetches qualifying issues, pre-researches upcoming work with subagents, and drives each issue through plan/review/implement/test/commit one at a time.
argument-hint: "[filter: priority, label, count, or milestone]"
---

# Sprint — Batch Issue Workflow

Work through a filtered set of GitHub issues from a milestone, one at a time, with subagents pre-researching ahead.

> **CRITICAL — Phase Gate Rule**
>
> You MUST stop and wait for explicit user confirmation after completing each issue. DO NOT proceed to the next issue until the user tells you to. This applies even if the next issue seems trivial.

## Input

The user's input: $ARGUMENTS

Parse for optional filters (all are combinable):
- **Milestone** — e.g., `v0.2`, `0.2.0`, `v0.2.0`. If not specified, detect the current milestone (see Milestone Detection below).
- **Priority** — e.g., `P1`, `P2`, `P1+` (P1 and above). Maps to GitHub labels `priority/P0`, `priority/P1`, etc.
- **Labels** — e.g., `bug`, `type/enhancement`. Filter to issues with specific labels.
- **Count** — e.g., `10`, `up to 5`. Limits how many issues to work through.
- **Type shorthand** — e.g., `bugs` (→ label `type/bug`), `features` (→ label `type/enhancement`), `small tasks` (→ label `size/S` or `size/XS`).

If no filters are provided at all, default to: all open issues in the current milestone, sorted by priority.

### Milestone Detection

Reuse the same logic as `/ship`:

1. Check the current branch name for a version pattern (e.g., `feat/0.2.0` → `v0.2.0`).
2. Look for a matching GitHub milestone:
   ```bash
   gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title | test("0\\.2")) | .title'
   ```
3. If no milestone is detected from the branch, ask the user which milestone to use.

### Guard Rails

- **Minimum 1 issue, maximum 12.** If the query returns more than 12 issues, show the count and ask the user to narrow the filter. Working through more than 12 issues in one sprint gets unwieldy — suggest splitting into multiple sprints or adding priority/label filters.
- **Zero results.** If no issues match, show the query you ran and suggest alternative filters.

---

## Phase 1: Fetch, Order, and Present the Queue

1. **Build the `gh issue list` query** from the parsed filters:
   ```bash
   gh issue list --milestone "<milestone>" --label "<label>" --state open --json number,title,labels,assignees,body --limit 50
   ```

2. **Delegate ordering to the project-manager agent.** Pass the fetched issues and ask it to:
   - Order by priority (P0 → P3)
   - Identify dependency chains — if Issue B depends on Issue A (referenced in body, or A is a prerequisite), A should come first
   - Flag any issues that should be skipped (e.g., blocked by external work, assigned to someone else)
   - Return the ordered list with a brief rationale for the ordering

   The project-manager agent has context on triage, sizing, and prioritization conventions. Trust its ordering unless the user overrides.

3. **Apply count limit** if specified. Take the top N issues from the ordered list.

4. **Present the queue** as a numbered list:
   ```
   ## Sprint Queue: v0.2.0 (P2 issues)

   Found N issues (ordered by priority and dependency):

   1. #42 — Add CSV export to reports (P2, size/M)
   2. #47 — Fix timer flicker on pause (P2, size/S) — depends on #42
   3. #51 — Update CLI help text for session add (P2, size/XS)

   I'll work through these one at a time, pausing after each for your review and commit.
   Ready to start with #42?
   ```

5. **Wait for user confirmation** before starting. The user may want to reorder, skip, or adjust the queue.

---

## Phase 2: Pre-Research Pipeline

Once the user confirms the queue:

1. **Start working on Issue 1** immediately (see Phase 3).
2. **Launch a subagent to pre-research Issue 2** in the background using the Explore agent type. The subagent should:
   - Fetch the issue details via `gh issue view`
   - Read relevant code files mentioned in the issue
   - Identify the affected area of the codebase
   - Summarize: problem, likely affected files, complexity estimate, and any open questions
   - **Do NOT write code or make changes** — research only

3. **Rolling pre-research**: When you finish Issue N and move to Issue N+1 (which is already pre-researched), launch a background subagent to pre-research Issue N+2. Always stay 1 issue ahead.

4. **Use the pre-research** when starting each issue to skip redundant exploration and jump straight to approach evaluation.

---

## Phase 3: Per-Issue Loop

For each issue in the queue, follow this workflow. This mirrors `/fix` but is streamlined for batch work.

### 3a. Understand

- If pre-researched, review the subagent's summary. Otherwise, fetch the issue and read relevant code.
- Summarize the issue in 1-2 sentences.
- **Always include the issue URL** (e.g., `https://github.com/terriann/present/issues/42`) so the user can open it in the browser to read full context.

### 3b. Plan

- For **small/XS issues**: Present a brief plan inline (no plan mode needed). 1-3 steps.
- For **medium+ issues**: Break into phases, enter plan mode, and wait for approval.
- If the issue has multiple valid approaches with real tradeoffs, use `AskUserQuestion` to resolve before planning.

### 3c. Implement

- Follow all project conventions from CLAUDE.md.
- For multi-phase issues, follow the `/fix` phase gate pattern: implement one phase, present the Phase Completion Template, STOP, wait for review.
- For single-phase issues, implement and present the completion summary.
- **Delegate tests** to the appropriate test generator agent when tests are needed.

### 3d. Issue Complete — STOP

After implementation (all phases if multi-phase):

```
## Issue #N Complete: <title>

**What changed:** <1-3 bullet summary>

**Test results:** <pass/fail summary, or "No tests applicable — <reason>">

---

Ready for you to test. When you're happy, I'll commit.
```

**STOP and wait for user confirmation.**

### 3e. Commit

When the user approves:
- **Delegate the commit to the commit-pr-writer agent.** Pass the issue number and whether this commit closes the issue or is in-progress.
- The final commit for an issue should use a closing keyword (`Closes #N`) in the body.
- In-progress commits (for multi-phase issues) use `Addressing #N` or `Part of #N`.

### 3f. Transition to Next Issue

After committing:

```
## Sprint Progress: N/Total complete

Completed:
- [x] #42 — Add CSV export to reports
- [x] #47 — Fix timer flicker on pause

Up next:
- [ ] #51 — Update CLI help text for session add

Ready to start #51?
```

**Wait for user confirmation.** The user may want to:
- Take a break
- Skip an issue
- Reorder remaining issues
- Stop the sprint early

---

## Sprint Completion

When all issues are done (or the user stops early):

```
## Sprint Complete

**Milestone:** v0.2.0
**Issues completed:** N/Total

Completed:
- [x] #42 — Add CSV export to reports (abc1234)
- [x] #47 — Fix timer flicker on pause (def5678)

Skipped:
- [ ] #51 — Update CLI help text (user deferred)

All changes are committed on branch `feat/0.2.0`.
Ready to /ship when you are.
```

---

## Important Rules

### One issue, one commit, one link — no exceptions

> **CRITICAL — Commit Discipline**
>
> Every issue MUST result in its own independent commit. Never bundle multiple issues into a single commit. Every commit MUST reference the issue number in the commit body — no commit in this workflow should lack an issue reference. This is non-negotiable.
>
> - **Final commit for an issue** → `Closes #N` (closing keyword)
> - **In-progress commit (multi-phase)** → `Addressing #N` or `Part of #N`
> - **No orphan commits.** If a commit doesn't reference an issue, it's wrong. Fix it before moving on.

When delegating to the commit-pr-writer agent, always pass:
1. The issue number
2. Whether the commit is in-progress or final (closing)

The agent will use the correct phrasing, but **verify the output** — if the issue reference is missing, reject the commit message and ask for a corrected one.

### Other rules

- **STOP after every issue.** Output the completion summary, then make zero tool calls until the user responds.
- **Never auto-commit.** Always pause for user review and testing.
- **Always delegate commits** to the commit-pr-writer agent.
- **Always delegate tests** to the appropriate test generator agent.
- **Pre-research is read-only.** Subagents must not write code or make changes.
- **Respect the 12-issue cap.** Push back on larger batches.
- **Track sprint progress.** Show the checklist at every transition so the user always knows where they are.
- **The user controls the pace.** They can skip, reorder, pause, or stop at any time.
- **Never close issues via `gh issue close`.** Issues close automatically via closing keyword commits on merge.
- **If an issue requires a separate branch** (e.g., it's a large feature unrelated to the current milestone work), flag this to the user and ask how to proceed.
