# Claude Code Skills

Skills are custom slash commands for Claude Code. They live in
`.claude/skills/` and provide reusable, project-specific workflows
that any contributor can invoke from the CLI.

## Available Skills

### `/issue` — Create a GitHub Issue

Takes a rough bug report or feature request and turns it into a
well-structured GitHub issue with codebase references, architectural
context, and a suggested approach.

**What it does:**

1. Asks clarifying questions to fill in missing details
2. Researches the codebase for relevant files, patterns, and context
3. Drafts the issue and presents it for approval
4. Creates the issue via `gh issue create`

**Usage:**

```text
/issue the timer flickers when resuming a paused session
/issue add CSV export to the reports tab
```

The argument is a free-form description of the bug or feature. The
skill determines whether to file a bug report or feature request based
on the description.

> [!NOTE]
> The skill will not write or modify any source code. It only creates
> GitHub issues.

### `/fix` — Resolve a GitHub Issue

Takes a GitHub issue link or number and drives it to resolution:
evaluate approaches, plan in phases, implement with tests, and validate
acceptance criteria.

**What it does:**

1. Fetches and parses the issue (problem, suggested approach, acceptance criteria)
2. Evaluates 2-3 implementation approaches with pros/cons
3. Plans phased implementation and enters plan mode for approval
4. Executes each phase with tests, pausing for review and commit
5. Validates all acceptance criteria before the final commit

**Usage:**

```text
/fix https://github.com/terriann/present/issues/42
/fix #42
/fix #42 check docs/architecture.md — break into small phases
```

The argument is a GitHub issue URL or `#number`, optionally followed by
file references and supplementary instructions. File references are
reviewed during relevant phases; instructions shape execution throughout.

> [!NOTE]
> Every phase pauses for review before committing. The final commit
> uses a GitHub closing keyword so the issue auto-closes on merge.

### `/sprint` — Batch Issue Workflow

Works through a filtered set of GitHub issues from a milestone, one at
a time. Pre-researches upcoming issues with background subagents so
work is queued up. Each issue follows a plan/review/implement/test/commit
cycle, pausing for user review after every issue.

**What it does:**

1. Detects the current milestone from the branch name (or asks)
2. Fetches qualifying issues based on filters (priority, labels, count, type)
3. Delegates to the project-manager agent to order by priority and dependency
4. Presents the ordered queue for user approval
5. Pre-researches the next issue in the background while
   working on the current one
6. For each issue: plans, implements, tests, pauses for
   review, commits (delegates to commit-pr-writer)
7. Tracks progress with a running checklist at every transition

**Usage:**

```text
/sprint
/sprint P2
/sprint v0.2.0 bugs
/sprint P1 up to 5
/sprint small tasks
```

The argument is optional. Filters can include priority level (P0-P3,
or `P1+` for "P1 and above"), milestone, labels, type shorthands
(`bugs`, `features`, `small tasks`), and count limits. Defaults to all
open issues in the current milestone.

> [!NOTE]
> Each issue is resolved via the `/fix` skill, so every issue gets
> approach evaluation, issue comments, and acceptance criteria
> validation. Maximum 8 issues per sprint. Context is compacted
> every 2 issues to stay sharp. The sprint ends with a summary and
> a nudge toward `/ship`.

### `/ship` — Push, PR, and Benchmark

Pushes the current feature branch, creates a pull request that
enumerates all addressed issues, runs performance benchmarks against
the PR's base branch, and posts the results as a PR comment.

**What it does:**

1. Pushes the current branch to origin
2. Gathers commit history, diff, and referenced issues
3. Delegates PR description to the commit-pr-writer agent with project context
4. Creates the PR via `gh pr create`
5. Runs `Scripts/benchmark.sh --baseline <base-branch>` and
   posts results as a PR comment
6. Flags regressions via the code-reviewer agent for
   assessment

**Usage:**

```text
/ship
/ship --base develop
/ship mention the breaking change in session output
```

The argument is optional. Use it to override the base branch or
provide extra context for the PR description. Defaults to
`main`.

> [!NOTE]
> Benchmarks always compare against the PR's base branch.
> Regression detection delegates to the code-reviewer agent for
> assessment before flagging to the user.

---

## Adding a New Skill

Each skill is a directory under `.claude/skills/` containing a
`SKILL.md` file.

```text
.claude/skills/
  fix/
    SKILL.md
  issue/
    SKILL.md
  ship/
    SKILL.md
  sprint/
    SKILL.md
  your-skill/
    SKILL.md
```

### SKILL.md Format

The file uses YAML frontmatter followed by markdown instructions.

```markdown
---
name: your-skill
description: Short description shown in skill listings.
argument-hint: "[what the user provides]"
---

# Skill Title

Instructions for Claude Code when this skill is invoked.

The user's input is available as $ARGUMENTS.
```

**Frontmatter fields:**

| Field | Required | Description |
| --- | --- | --- |
| `name` | Yes | Slash command name (e.g., `issue`) |
| `description` | Yes | One-line summary of what the skill does |
| `argument-hint` | No | Placeholder shown after the command |

The markdown body is the prompt Claude Code receives when the skill
runs. Write it as direct instructions, not documentation. Use
`$ARGUMENTS` to reference the user's input.
