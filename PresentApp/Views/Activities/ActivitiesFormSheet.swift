import SwiftUI
import PresentCore

enum ActivitiesFormMode {
    case create
    case edit(Activity)
}

struct ActivitiesFormSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let mode: ActivitiesFormMode

    @State private var title = ""
    @State private var externalId = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Activity" : "New Activity")
                .font(.headline)

            Form {
                TextField("Title", text: $title)

                TextField("External ID", text: $externalId)

                TextField("Link (URL)", text: $link)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.alert)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Create") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Constants.spacingPage)
        .frame(width: 400)
        .onAppear {
            if case .edit(let activity) = mode {
                title = activity.title
                externalId = activity.externalId ?? ""
                link = activity.link ?? ""
                notes = activity.notes ?? ""
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func save() async {
        do {
            if case .edit(let activity) = mode {
                _ = try await appState.service.updateActivity(
                    id: activity.id!,
                    UpdateActivityInput(
                        title: title,
                        externalId: externalId,
                        link: link,
                        notes: notes
                    )
                )
            } else {
                _ = try await appState.service.createActivity(
                    CreateActivityInput(
                        title: title,
                        externalId: externalId.isEmpty ? nil : externalId,
                        link: link.isEmpty ? nil : link,
                        notes: notes.isEmpty ? nil : notes
                    )
                )
            }
            await appState.refreshAll()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
