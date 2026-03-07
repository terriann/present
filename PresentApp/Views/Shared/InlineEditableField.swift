import SwiftUI
import PresentCore

struct InlineEditableField: View {
    let value: String
    var placeholder: String = ""
    var font: Font = .body
    var isEditable: Bool = true
    var startInEditMode: Bool = false
    var onSave: (String) -> Void
    var onCancel: (() -> Void)?

    @Environment(ThemeManager.self) private var theme
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
        HStack(spacing: Constants.spacingTight) {
            if value.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .font(font)
            } else {
                Text(value)
                    .font(font)
            }

            if isEditable && isHovering {
                EditPillButton(action: beginEditing)
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
        .onTapGesture {
            guard isEditable else { return }
            beginEditing()
        }
        .accessibilityHint(isEditable ? "Click to edit" : "")
        .onAppear {
            if startInEditMode && isEditable {
                beginEditing()
            }
        }
    }

    // MARK: - Edit State

    private var editView: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $editText)
                .font(font)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    commitEdit()
                }
                .onKeyPress(.escape) {
                    cancelEdit()
                    return .handled
                }

            Button {
                cancelEdit()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(theme.alert)
            .accessibilityLabel("Cancel")

            Button {
                commitEdit()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(theme.success)
            .accessibilityLabel("Save")
        }
        .onChange(of: isFocused) {
            if !isFocused {
                // Delay slightly to allow button clicks to register before committing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !isFocused && isEditing {
                        commitEdit()
                    }
                }
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
        } else {
            onCancel?()
        }
    }

    private func cancelEdit() {
        withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
        onCancel?()
    }
}
