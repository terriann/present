#!/usr/bin/env python3
"""Generate CLI reference markdown from `present-cli --experimental-dump-help` JSON.

Reads JSON from stdin, writes markdown to stdout.
No dependencies beyond the Python 3 standard library.

Output follows WP-CLI documentation style with definition lists,
extended descriptions, and example blocks.
"""

import json
import re
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


# Global options that appear on most commands (collected and shown once)
GLOBAL_OPTION_NAMES = {"format", "field"}


def is_global_option(arg):
    """Check if an argument is a global/shared option."""
    preferred = arg.get("preferredName", {})
    return preferred.get("name") in GLOBAL_OPTION_NAMES


def parse_discussion(discussion):
    """Split a discussion string into description and examples.

    Returns (description, examples) where examples is the raw text
    after the '## Examples' marker, or None if no marker found.
    """
    if not discussion:
        return None, None

    marker = "## Examples"
    idx = discussion.find(marker)
    if idx == -1:
        return discussion.strip(), None

    desc = discussion[:idx].strip()
    examples = discussion[idx + len(marker):].strip()
    return desc or None, examples or None


def render_examples(examples_text):
    """Render examples text as a fenced code block.

    Expects lines like:
        # Comment describing the example
        $ present-cli command args
    """
    if not examples_text:
        return []
    lines = []
    lines.append("**Examples**")
    lines.append("")
    lines.append("```bash")
    for line in examples_text.splitlines():
        lines.append(line)
    lines.append("```")
    lines.append("")
    return lines


def render_definition_item(label, description, default=None):
    """Render a single WP-CLI style definition list item.

    Format:
        `[--name=<value>]`
        : Description. Default: `value`.
    """
    lines = []
    desc = description or ""
    if default and default != "\u2014":
        desc = f"{desc} Default: `{default}`." if desc else f"Default: `{default}`."
    lines.append(f"`{label}`")
    lines.append(f": {desc}")
    lines.append("")
    return lines


def render_command(command, parent_path="", default_subcommand=None, depth=3):
    """Render a single command as markdown in WP-CLI style."""
    lines = []
    cmd_name = command["commandName"]
    signature = build_signature(command, parent_path)
    heading = "#" * depth

    lines.append(f"{heading} `{signature}`")
    lines.append("")

    # Abstract (short description)
    abstract = command.get("abstract", "")
    if abstract:
        default_marker = ""
        if default_subcommand and cmd_name == default_subcommand:
            default_marker = " *(default)*"
        lines.append(f"{abstract}{default_marker}")
        lines.append("")

    # Discussion (extended description + examples)
    discussion = command.get("discussion", "")
    description, examples = parse_discussion(discussion)

    if description:
        lines.append(description)
        lines.append("")

    # Separate arguments by kind (filtering out --help and global options)
    args = [a for a in command.get("arguments", []) if not is_help_arg(a)]
    positionals = [a for a in args if a.get("kind") == "positional"]
    options = [a for a in args if a.get("kind") == "option" and not is_global_option(a)]
    flags = [a for a in args if a.get("kind") == "flag"]
    global_options = [a for a in args if a.get("kind") == "option" and is_global_option(a)]

    # Positional arguments in definition list style
    if positionals:
        lines.append("**Arguments**")
        lines.append("")
        for arg in positionals:
            value_name = arg.get("valueName", "value")
            required = "" if arg.get("isOptional") else " *(required)*"
            desc = arg.get("abstract", "")
            label = f"<{value_name}>"
            lines.append(f"`{label}`")
            lines.append(f": {desc}{required}")
            lines.append("")

    # Options in definition list style
    if options:
        lines.append("**Options**")
        lines.append("")
        for arg in options:
            preferred = arg.get("preferredName", {})
            pref_name = preferred.get("name", "")
            value_name = arg.get("valueName", "value")
            default = arg.get("defaultValue")
            desc = arg.get("abstract", "")

            # Build the WP-CLI style label: [--name=<value>]
            if preferred.get("kind") == "long":
                label = f"[--{pref_name}=<{value_name}>]"
            else:
                # Fallback to all names
                label = f"[{format_names(arg)}]"

            lines.extend(render_definition_item(label, desc, default))

    # Flags in definition list style
    if flags:
        lines.append("**Flags**")
        lines.append("")
        for arg in flags:
            name_str = format_names(arg)
            desc = arg.get("abstract", "")
            lines.append(f"`[{name_str}]`")
            lines.append(f": {desc}")
            lines.append("")

    # Examples
    if examples:
        lines.extend(render_examples(examples))

    # Global options (format, field) — shown per-command
    if global_options:
        lines.append("**Global Options**")
        lines.append("")
        for arg in global_options:
            preferred = arg.get("preferredName", {})
            pref_name = preferred.get("name", "")
            value_name = arg.get("valueName", "value")
            default = arg.get("defaultValue")
            desc = arg.get("abstract", "")

            all_names = format_names(arg)
            if preferred.get("kind") == "long":
                label = f"[--{pref_name}=<{value_name}>]"
                # Include short alias if present
                names = arg.get("names", [])
                short_names = [format_name(n) for n in names if n["kind"] == "short"]
                if short_names:
                    label = f"[{', '.join(short_names)}, --{pref_name}=<{value_name}>]"
            else:
                label = f"[{all_names}]"

            lines.extend(render_definition_item(label, desc, default))

    # Subcommands
    subcommands = sort_commands(
        [s for s in command.get("subcommands", []) if not is_help_command(s)]
    )
    sub_default = command.get("defaultSubcommand")

    if subcommands:
        cmd_path = build_command_path(command, parent_path)

        lines.append("**Subcommands**")
        lines.append("")
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
        # Strip the root CLI name for cleaner display
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
