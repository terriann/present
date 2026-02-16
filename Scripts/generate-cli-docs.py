#!/usr/bin/env python3
"""Generate CLI reference markdown from `present-cli --experimental-dump-help` JSON.

Reads JSON from stdin, writes markdown to stdout.
No dependencies beyond the Python 3 standard library.
"""

import json
import sys
from datetime import datetime, timezone


def format_name(name_obj):
    """Format a name object into its CLI representation."""
    kind = name_obj["kind"]
    name = name_obj["name"]
    if kind == "long":
        return f"--{name}"
    elif kind == "short":
        return f"-{name}"
    return name


def format_names(arg):
    """Format all names for an argument into a combined string."""
    names = arg.get("names", [])
    return ", ".join(format_name(n) for n in names)


def is_help_arg(arg):
    """Check if an argument is the auto-generated --help flag."""
    preferred = arg.get("preferredName", {})
    return preferred.get("name") == "help"


def is_help_command(sub):
    """Check if a subcommand is the auto-generated help command."""
    return sub.get("commandName") == "help"


def sort_commands(subcommands):
    """Sort subcommands alphabetically by commandName."""
    return sorted(subcommands, key=lambda s: s["commandName"])


def make_anchor(signature):
    """Convert a command signature to a GitHub-compatible markdown anchor."""
    anchor = signature.lower()
    anchor = anchor.replace(" ", "-")
    # Remove characters that GitHub strips from anchors
    anchor = "".join(c for c in anchor if c.isalnum() or c == "-")
    return anchor


def build_command_path(command, parent_path=""):
    """Build the full command path string."""
    name = command["commandName"]
    if parent_path:
        return f"{parent_path} {name}"
    return name


def build_signature(command, parent_path=""):
    """Build a command signature with positional args."""
    path = build_command_path(command, parent_path)
    args = command.get("arguments", [])
    positionals = [a for a in args if a.get("kind") == "positional" and not is_help_arg(a)]

    parts = [path]
    for arg in positionals:
        value_name = arg.get("valueName", "value")
        if arg.get("isOptional"):
            parts.append(f"[<{value_name}>]")
        else:
            parts.append(f"<{value_name}>")

    return " ".join(parts)


def render_command(command, parent_path="", default_subcommand=None, depth=3):
    """Render a single command as markdown."""
    lines = []
    cmd_name = command["commandName"]
    signature = build_signature(command, parent_path)
    heading = "#" * depth

    lines.append(f"{heading} `{signature}`")
    lines.append("")

    abstract = command.get("abstract", "")
    if abstract:
        default_marker = ""
        if default_subcommand and cmd_name == default_subcommand:
            default_marker = " *(default)*"
        lines.append(f"{abstract}{default_marker}")
        lines.append("")

    # Separate arguments by kind (filtering out --help)
    args = [a for a in command.get("arguments", []) if not is_help_arg(a)]
    positionals = [a for a in args if a.get("kind") == "positional"]
    options = [a for a in args if a.get("kind") == "option"]
    flags = [a for a in args if a.get("kind") == "flag"]

    # Positional arguments table
    if positionals:
        lines.append("**Arguments:**")
        lines.append("")
        lines.append("| Argument | Required | Description |")
        lines.append("|---|---|---|")
        for arg in positionals:
            value_name = arg.get("valueName", "value")
            required = "No" if arg.get("isOptional") else "Yes"
            desc = arg.get("abstract", "")
            lines.append(f"| `<{value_name}>` | {required} | {desc} |")
        lines.append("")

    # Options table
    if options:
        lines.append("**Options:**")
        lines.append("")
        lines.append("| Option | Default | Description |")
        lines.append("|---|---|---|")
        for arg in options:
            name_str = format_names(arg)
            default = arg.get("defaultValue", "\u2014")
            if default == "":
                default = "\u2014"
            desc = arg.get("abstract", "")
            lines.append(f"| `{name_str}` | `{default}` | {desc} |" if default != "\u2014" else f"| `{name_str}` | {default} | {desc} |")
        lines.append("")

    # Flags table (non-help)
    if flags:
        lines.append("**Flags:**")
        lines.append("")
        lines.append("| Flag | Description |")
        lines.append("|---|---|")
        for arg in flags:
            name_str = format_names(arg)
            desc = arg.get("abstract", "")
            lines.append(f"| `{name_str}` | {desc} |")
        lines.append("")

    # Subcommands (alphabetical)
    subcommands = sort_commands(
        [s for s in command.get("subcommands", []) if not is_help_command(s)]
    )
    sub_default = command.get("defaultSubcommand")

    if subcommands:
        cmd_path = build_command_path(command, parent_path)

        lines.append("**Subcommands:**")
        lines.append("")
        lines.append("| Command | Description |")
        lines.append("|---|---|")
        for sub in subcommands:
            sub_sig = build_signature(sub, cmd_path)
            sub_anchor = make_anchor(sub_sig)
            sub_abstract = sub.get("abstract", "")
            marker = " *(default)*" if sub_default and sub["commandName"] == sub_default else ""
            lines.append(f"| [`{sub['commandName']}`](#{sub_anchor}) | {sub_abstract}{marker} |")
        lines.append("")

        # Render each subcommand with details
        for sub in subcommands:
            sub_lines = render_command(sub, cmd_path, default_subcommand=sub_default, depth=depth + 1)
            lines.extend(sub_lines)

    return lines


def build_toc(subcommands, parent_path, default_sub=None, indent=0):
    """Build a nested table of contents list recursively."""
    lines = []
    prefix = "  " * indent
    for sub in subcommands:
        sig = build_signature(sub, parent_path)
        anchor = make_anchor(sig)
        cmd_path = build_command_path(sub, parent_path)
        # Strip the root CLI name for cleaner display (e.g., "activity add" not "present-cli activity add")
        display = cmd_path.split(" ", 1)[1] if " " in cmd_path else cmd_path
        marker = " *(default)*" if default_sub and sub["commandName"] == default_sub else ""
        lines.append(f"{prefix}- [`{display}`](#{anchor}){marker}")

        # Recurse into child subcommands
        children = sort_commands(
            [s for s in sub.get("subcommands", []) if not is_help_command(s)]
        )
        if children:
            child_path = build_command_path(sub, parent_path)
            child_default = sub.get("defaultSubcommand")
            lines.extend(build_toc(children, child_path, child_default, indent + 1))
    return lines


def generate_markdown(data):
    """Generate the full markdown document."""
    command = data["command"]
    root_name = command["commandName"]
    abstract = command.get("abstract", "")
    default_sub = command.get("defaultSubcommand")
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    lines = []

    # Header
    lines.append("<!-- DO NOT EDIT — auto-generated by Scripts/generate-cli-docs.sh -->")
    lines.append("")
    lines.append("# CLI Reference")
    lines.append("")
    if abstract:
        lines.append(f"> {abstract}")
        lines.append("")
    lines.append(f"*Auto-generated on {timestamp} from `{root_name} --experimental-dump-help`.*")
    lines.append("")

    # Top-level commands (alphabetical)
    subcommands = sort_commands(
        [s for s in command.get("subcommands", []) if not is_help_command(s)]
    )

    if subcommands:
        # Nested table of contents
        lines.append("## Commands")
        lines.append("")
        lines.extend(build_toc(subcommands, root_name, default_sub))
        lines.append("")

        # Detailed command sections
        for sub in subcommands:
            sub_lines = render_command(sub, root_name, default_subcommand=default_sub)
            lines.extend(sub_lines)

    # Ensure trailing newline
    return "\n".join(lines).rstrip() + "\n"


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    if "command" not in data:
        print("Error: JSON missing 'command' key", file=sys.stderr)
        sys.exit(1)

    markdown = generate_markdown(data)
    sys.stdout.write(markdown)


if __name__ == "__main__":
    main()
