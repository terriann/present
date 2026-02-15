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

## Adding a New Skill

Each skill is a directory under `.claude/skills/` containing a
`SKILL.md` file.

```text
.claude/skills/
  issue/
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
|---|---|---|
| `name` | Yes | Slash command name (e.g., `issue`) |
| `description` | Yes | One-line summary of what the skill does |
| `argument-hint` | No | Placeholder shown after the command |

The markdown body is the prompt Claude Code receives when the skill
runs. Write it as direct instructions, not documentation. Use
`$ARGUMENTS` to reference the user's input.
