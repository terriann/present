---
name: fix
description: Resolve a GitHub issue by link. Use when the user says "/fix <github-issue-url>" or "fix issue #123". Accepts additional context (file references, workflow preferences) alongside the issue. Fetches the issue, evaluates approaches, plans in phases, writes tests, commits per phase, and validates acceptance criteria before final commit.
version: 1.0.0
---

# Fix — GitHub Issue Resolver

Resolve a GitHub issue end-to-end: fetch context, evaluate approaches, plan in phases, implement with tests, and validate acceptance criteria.

> **CRITICAL — Phase Gate Rule**
>
> You MUST stop and wait for explicit user confirmation after completing each implementation phase. DO NOT proceed to the next phase, start new code changes, or continue implementation until the user tells you to. This applies even if the next phase seems trivial.
>
> After each phase, output the **Phase Completion Template** (see Phase 4e) and then STOP. Do not write any more code or make any more tool calls until the user responds.

## Input

The user invokes `/fix` with a GitHub issue reference **and optional additional context**. Parse the full input for three components:

1. **Issue reference** — A GitHub issue URL or `owner/repo#number`. Extract issue details using `gh`.
2. **File references** — Any files or docs the user mentions (e.g., `@docs/architecture.md`, explicit paths). These should be reviewed and updated as needed during relevant phases.
3. **Supplementary instructions** — Workflow preferences, constraints, or scope notes (e.g., "break into phases," "update docs as needed"). Honor these throughout all phases.

Carry all three components forward. File references inform the plan; supplementary instructions shape execution. If no extra context is provided, proceed with defaults.

---

## Phase 1: Understand the Issue

1. **Fetch the issue** using GitHub CLI:
   ```bash
   gh issue view <number> --repo <owner/repo> --json title,body,labels,assignees,state,comments
   ```

2. **Parse the issue body** for:
   - **Problem statement**: What's broken or missing?
   - **Suggested approach**: Does the issue propose a solution?
   - **Acceptance criteria**: Explicit criteria, checkboxes, or "done when" statements.
   - **Checkboxes**: Note any `- [ ]` items — these may map to phases or validation steps.

3. **If acceptance criteria are unclear**, ask the user to clarify before proceeding. You cannot validate resolution without clear criteria.

4. **Summarize** the issue back to the user in 2-3 sentences, confirming your understanding.

---

## Phase 2: Evaluate Approaches

Even if the issue suggests an approach, do not blindly follow it. Evaluate alternatives.

1. **Read relevant code** — use Glob/Grep/Read to understand the affected area.
2. **List 2-3 approaches** (minimum 2, even if one is clearly better). For each:
   - Brief description (1-2 sentences)
   - Pros
   - Cons
   - Estimated complexity (small / medium / large)
3. **If the issue's suggested approach is sound**, include it as option 1 and note that it aligns with the issue author's recommendation.
4. **Present options to the user** using `AskUserQuestion` and wait for approval before proceeding.
5. **After the user selects an approach**, post a comment on the GitHub issue summarizing the decision:
   ```bash
   gh issue comment <number> --repo <owner/repo> --body "$(cat <<'EOF'
   ## Approach Evaluation

   **Options considered:**

   1. **<Option 1>** — <brief description>
      - Pros: ...
      - Cons: ...

   2. **<Option 2>** — <brief description>
      - Pros: ...
      - Cons: ...

   **Direction chosen:** Option N — <rationale for selection>
   EOF
   )"
   ```
   Keep the comment concise. This creates a public record of the decision on the issue itself.

---

## Phase 3: Plan the Implementation

After the user selects an approach:

1. **Resolve open questions first.** Before writing any plan, identify ambiguities, unknowns, or decisions that could change the shape of the implementation (e.g., scope boundaries, edge case behavior, naming choices, migration strategy). If any exist, use `AskUserQuestion` to resolve them now. DO NOT enter plan mode with unresolved questions — they lead to rework or wrong assumptions baked into phases.
2. **Break the work into phases.** Each phase should be a logical, committable unit.
3. **Write the plan** to a temporary plan file and enter plan mode (`EnterPlanMode`) for user approval.
4. **Every phase gets a commit.** Pause after each phase for testing, review, and commit. This is the default workflow, not just for large plans.
5. **Map issue checkboxes to phases** where applicable — note which checkbox(es) each phase addresses.
6. **Incorporate file references** from the user's input. If the user mentioned specific files (docs, configs, etc.), assign their review/update to the appropriate phase(s). Documentation updates typically belong in the phase whose changes they describe.

---

## Phase 4: Execute — Per-Phase Loop

For each phase:

### 4a. Test-First (Bug Fixes)

If the issue is a **bug**:
1. **Write a failing test first** that reproduces the bug (when feasible).
2. Run the test to confirm it fails.
3. Implement the fix.
4. Run the test again to confirm it passes.

If a test-first approach is not feasible (e.g., UI-only bug, environment-specific), note why and skip to implementation.

### 4b. Implement

- Follow all project conventions from CLAUDE.md (patterns, naming, architecture).
- Keep changes minimal and focused on the current phase.
- If user-specified files (docs, configs) are scoped to this phase, include those updates alongside the code changes so they ship in the same commit.

### 4c. Tests (Non-Bug or Post-Fix)

After implementation:
- **Bug fixes**: Confirm the pre-written test passes. Add edge-case tests if warranted.
- **Features**: Write tests covering the new behavior. Delegate to the appropriate test generator agent.
- **Refactors**: Ensure existing tests still pass. Add tests if coverage gaps are found.
- If no tests are appropriate, explicitly state why.

### 4d. Validate Phase

- Run the test suite to confirm nothing is broken.
- If the issue has checkboxes that map to this phase, note which ones are now addressed.

### 4e. STOP — Phase Complete

**After completing each phase you MUST stop.** Output the Phase Completion Template below, then make no further tool calls until the user responds.

#### Phase Completion Template

Use this exact structure in your output:

```
## Phase N Complete

**What changed:** <1-3 bullet summary of this phase's changes>

**Checkboxes addressed:** <list, or "None this phase">

**Test results:** <pass/fail summary, or "No tests applicable — <reason>">

---

Ready for you to test. When you're happy, I'll commit and move to Phase N+1.
```

#### Rules

- DO NOT skip this template. DO NOT abbreviate it.
- DO NOT start Phase N+1 code, research, or tool calls until the user replies.
- **Delegate the commit to the commit-pr-writer agent** when the user approves.
- If the user asks for changes, make them within the current phase before committing.

---

## Phase 5: Final Validation

Before the **last commit** (or before opening a PR):

1. **Restate the acceptance criteria** from the issue.
2. **Walk through each criterion** and confirm it's met, with evidence (test results, behavior description).
3. **List any issue checkboxes** and their status.
4. **Ask the user to validate** that acceptance criteria are met before proceeding.
5. Only after user confirmation: commit (via commit-pr-writer) and optionally open a PR.

---

## Checkbox Management

If the GitHub issue contains checkboxes (`- [ ]` / `- [x]`):
- Track which checkboxes correspond to which phases.
- After completing each relevant phase, note the checkbox status in your summary.
- Do **not** update the GitHub issue checkboxes automatically — note completed items and let the user decide whether to update the issue.

---

## Summary of Workflow

```
/fix <issue-url> [file refs] [instructions]
  |
  v
Parse input (issue ref + file refs + supplementary instructions)
  |
  v
Fetch & parse issue
  |
  v
Clarify acceptance criteria (if needed)
  |
  v
Evaluate approaches (2-3 options with pros/cons)
  |
  v
User selects approach -> comment on issue
  |
  v
Plan phases (enter plan mode, assign file refs to phases)
  |
  v
User approves plan
  |
  v
For each phase:
  |- Write failing test (bugs)
  |- Implement (incl. user-specified file updates)
  |- Write/update tests
  |- Run test suite
  |- Output Phase Completion Template
  |- *** STOP — wait for user ***
  |- User reviews -> commit (always)
  |
  v
Final validation:
  |- Restate acceptance criteria
  |- Confirm each criterion met
  |- User validates
  |- Final commit / PR
```

---

## Issue Linking in Commits

Every commit must reference the GitHub issue. The phrasing depends on whether the commit **resolves** the issue or is **progress toward** it.

### In-progress commits (does not close the issue)

Use one of these phrases in the commit body (not the subject line):

- `Addressing #123`
- `Related to #123`
- `For #123`
- `See #123`
- `Working toward #123`
- `Progress on #123`
- `Part of #123`

### Final commit (resolves the issue)

Use a GitHub closing keyword so the issue auto-closes when merged:

- `Closes #123`
- `Closed #123`
- `Resolves #123`
- `Resolved #123`

### Rules

- **Always include an issue reference** — no commit in this workflow should lack one.
- The reference goes in the **commit body**, not the subject line.
- Only the **final commit** (after acceptance criteria validation) should use a closing keyword.
- When delegating to the commit-pr-writer agent, pass the issue number and whether the commit is in-progress or final so it uses the correct phrasing.

---

## Important Rules

- **Never skip approach evaluation.** Even obvious fixes deserve a second option considered.
- **STOP after every phase.** Output the Phase Completion Template (4e), then make zero tool calls until the user responds. This is the most important rule in this skill.
- **Never auto-commit.** Always pause for user review.
- **Always delegate commits** to the commit-pr-writer agent. Include the issue number and whether it's an in-progress or closing commit.
- **Always delegate tests** to the appropriate test generator agent (wordpress-test-generator or nodejs-test-generator).
- **Acceptance criteria must be validated** before the final commit. This is non-negotiable.
- **Respect phase boundaries.** Do not bleed work across phases. One phase, one commit.
- **If the issue is on a different branch than current**, note this and ask the user about branching strategy before starting work.
- **Never close the issue via `gh issue close`**. Issues should close automatically when the closing keyword commit is pushed/merged. Let GitHub handle it.
