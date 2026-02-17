import SwiftUI

struct InlineEditableField: View {
    let value: String
    var placeholder: String = ""
    var font: Font = .body
    var isEditable: Bool = true
    var onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            editView
        } else {
            displayView
        }
    }

    // MARK: - Display State

    private var displayView: some View {
        HStack(spacing: 4) {
            if value.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .font(font)
            } else {
                Text(value)
                    .font(font)
            }

            if isEditable && isHovering {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onHover { hovering in
            guard isEditable else { return }
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture(count: 2) {
            guard isEditable else { return }
            beginEditing()
        }
        .accessibilityHint(isEditable ? "Double-click to edit" : "")
    }

    // MARK: - Edit State

    private var editView: some View {
        TextField(placeholder, text: $editText)
            .font(font)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit {
                commitEdit()
            }
            .onKeyPress(.escape) {
                cancelEdit()
                return .handled
            }
            .onChange(of: isFocused) {
                if !isFocused {
                    commitEdit()
                }
            }
    }

    // MARK: - Helpers

    private func beginEditing() {
        editText = value
        withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
            isEditing = true
        }
        // Focus after a brief delay so the TextField is in the hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
        if trimmed != value {
            onSave(trimmed)
        }
    }

    private func cancelEdit() {
        withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
    }
}
