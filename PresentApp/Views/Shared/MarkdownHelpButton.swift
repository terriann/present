import PresentCore
import SwiftUI

/// A "Markdown" label with a help icon that opens a popover showing supported syntax
/// and the external ID auto-detection hint.
struct MarkdownHelpButton: View {
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp.toggle()
        } label: {
            HStack(spacing: 3) {
                Text("Markdown")
                Image(systemName: "questionmark.circle.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.dataLabel)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Markdown formatting help")
        .popover(isPresented: $showHelp) {
            MarkdownHelpContent()
        }
    }
}

// MARK: - Popover Content

private struct MarkdownHelpContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.spacingCard) {
                syntaxSection
                externalIdSection
            }
            .padding()
        }
        .frame(width: 340, height: 380)
    }

    // MARK: - Syntax Reference

    private var syntaxSection: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            Text("Supported Syntax")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 6) {
                syntaxRow("# Heading", "Header (levels 1-3)")
                syntaxRow("**bold**", "Bold text")
                syntaxRow("*italic*", "Italic text")
                syntaxRow("[text](url)", "Link")
                syntaxRow("- item", "Unordered list")
                syntaxRow("1. item", "Ordered list")
                syntaxRow("- [ ] task", "Task list")
                syntaxRow("`code`", "Inline code")
                syntaxRow("```code```", "Code block")
                syntaxRow("> quote", "Blockquote")
                syntaxRow("---", "Horizontal rule")
            }
        }
    }

    @ViewBuilder
    private func syntaxRow(_ syntax: String, _ description: String) -> some View {
        GridRow {
            Text(syntax)
                .font(.codeCaption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - External ID Hint

    private var externalIdSection: some View {
        VStack(alignment: .leading, spacing: Constants.spacingTight) {
            Text("External ID")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("The first issue tracker URL found in notes (Linear, Jira, or GitHub Issues) will automatically set the activity's external ID.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Constants.spacingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
