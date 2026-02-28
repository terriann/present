import SwiftUI
import PresentCore

// MARK: - View Modifier

/// Keeps a rhythm option selection in sync with the available options from AppState.
///
/// On appear and whenever `appState.rhythmDurationOptions` changes, validates that the
/// current selection still exists in the available options. Falls back to the first
/// option if the selection is nil or no longer valid.
///
/// Use this on any view that lets the user pick a rhythm option but doesn't own the
/// options list (i.e. consumers, not the settings editor).
struct RhythmSelectionSyncModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    @Binding var selection: RhythmOption?

    func body(content: Content) -> some View {
        content
            .onAppear { validate() }
            .onChange(of: appState.rhythmDurationOptions) { validate() }
    }

    private func validate() {
        guard let current = selection,
              appState.rhythmDurationOptions.contains(current) else {
            selection = appState.rhythmDurationOptions.first
            return
        }
    }
}

// MARK: - View Extension

extension View {
    /// Keeps a rhythm option binding in sync with the available options from AppState.
    ///
    /// Validates the selection on appear and whenever options change, falling back
    /// to the first available option if the current selection is invalid.
    func syncRhythmSelection(_ selection: Binding<RhythmOption?>) -> some View {
        modifier(RhythmSelectionSyncModifier(selection: selection))
    }
}
