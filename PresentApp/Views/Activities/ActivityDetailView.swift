import SwiftUI
import PresentCore

struct ActivityDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var activity: Activity
    @State private var notes: String
    @State private var tags: [Tag] = []
    @State private var baseUrl = ""
    @State private var showingArchiveConfirm = false
    @State private var archiveResult: ArchiveResult?
    @State private var showingDeleteConfirm = false
    @State private var selectedSessionType: SessionType = .work
    @State private var selectedRhythmOption: RhythmOption?
    @State private var timeboundMinutes: Int = 25

    init(activity: Activity) {
        _activity = State(initialValue: activity)
        _notes = State(initialValue: activity.notes ?? "")
    }

    @State private var editingExternalId = false
    @State private var editingLink = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerRow
                linksSection
                notesSection
                tagsSection
                activityFooter
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .alert("Archive Activity?", isPresented: $showingArchiveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Archive") {
                Task {
                    do {
                        _ = try await appState.service.archiveActivity(id: activity.id!)
                        await reload()
                    } catch {
                        appState.showError(error, context: "Could not archive activity")
                    }
                }
            }
            Button("Delete Instead", role: .destructive) {
                Task {
                    do {
                        try await appState.service.deleteActivity(id: activity.id!)
                        await appState.refreshAll()
                    } catch {
                        appState.showError(error, context: "Could not delete activity")
                    }
                }
            }
        } message: {
            if case .promptDelete(let totalSeconds) = archiveResult {
                Text("This activity has less than 10 minutes of tracked time (\(TimeFormatting.formatDuration(seconds: totalSeconds))). Would you like to delete it instead?")
            }
        }
        .alert("Delete Activity?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await appState.service.deleteActivity(id: activity.id!)
                        await appState.refreshAll()
                    } catch {
                        appState.showError(error, context: "Could not delete activity")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the activity and all its sessions. This cannot be undone.")
        }
        .task {
            await loadDetails()
            timeboundMinutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
        }
        .onChange(of: appState.rhythmDurationOptions) {
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .top) {
            // Left: title + badge
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    InlineEditableField(
                        value: activity.title,
                        placeholder: "Activity title",
                        font: .title.bold(),
                        isEditable: !activity.isArchived,
                        onSave: { newTitle in
                            Task { await updateTitle(newTitle) }
                        }
                    )

                    if activity.isArchived {
                        Text("Archived")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }
            }

            Spacer()

            // Right: session controls (fixed position, not affected by title editing)
            if !activity.isArchived {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(SessionType.allCases, id: \.self) { type in
                            let isSelected = selectedSessionType == type
                            Button {
                                withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
                                    selectedSessionType = type
                                }
                            } label: {
                                Text(SessionTypeConfig.config(for: type).displayName)
                                    .font(.callout.weight(isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? theme.accent.opacity(0.15) : Color.clear, in: Capsule())
                                    .foregroundStyle(isSelected ? theme.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedSessionType == .rhythm {
                        HStack(spacing: 4) {
                            ForEach(appState.rhythmDurationOptions, id: \.self) { option in
                                let isSelected = selectedRhythmOption == option
                                Button {
                                    selectedRhythmOption = option
                                } label: {
                                    Text("\(option.focusMinutes) min (\(option.breakMinutes)m)")
                                        .font(.caption.weight(isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(isSelected ? theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                        .foregroundStyle(isSelected ? theme.accent : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if selectedSessionType == .timebound {
                        HStack(spacing: 4) {
                            Text("Duration:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("", value: $timeboundMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 48)
                                .font(.callout)
                            Text("min")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Start Session") {
                        Task {
                            switch selectedSessionType {
                            case .rhythm:
                                let option = selectedRhythmOption ?? appState.rhythmDurationOptions.first
                                await appState.startSession(
                                    activityId: activity.id!,
                                    type: .rhythm,
                                    timerMinutes: option?.focusMinutes,
                                    breakMinutes: option?.breakMinutes
                                )
                            case .timebound:
                                await appState.startSession(
                                    activityId: activity.id!,
                                    type: .timebound,
                                    timerMinutes: timeboundMinutes
                                )
                            default:
                                await appState.startSession(
                                    activityId: activity.id!,
                                    type: selectedSessionType
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isSessionActive)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Group {
            if !activity.isArchived || activity.externalId != nil || activity.link != nil {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // External ID
                        if !activity.isArchived || activity.externalId != nil {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("External ID")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if editingExternalId {
                                    InlineEditableField(
                                        value: activity.externalId ?? "",
                                        placeholder: "Add external ID",
                                        font: .body,
                                        isEditable: true,
                                        startInEditMode: true,
                                        onSave: { newValue in
                                            editingExternalId = false
                                            Task { await updateExternalId(newValue) }
                                        },
                                        onCancel: { editingExternalId = false }
                                    )
                                } else if let externalId = activity.externalId, !externalId.isEmpty,
                                          let url = resolvedExternalURL(for: externalId) {
                                    EditableLinkDisplay(
                                        text: externalId,
                                        url: url,
                                        accentColor: theme.accent,
                                        isEditable: !activity.isArchived,
                                        onEdit: { editingExternalId = true }
                                    )
                                } else if !activity.isArchived {
                                    InlineEditableField(
                                        value: activity.externalId ?? "",
                                        placeholder: "Add external ID",
                                        font: .body,
                                        isEditable: true,
                                        onSave: { newValue in
                                            Task { await updateExternalId(newValue) }
                                        }
                                    )
                                } else if let externalId = activity.externalId, !externalId.isEmpty {
                                    Text(externalId)
                                        .font(.body)
                                }
                            }
                        }

                        // Link
                        if !activity.isArchived || activity.link != nil {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Link")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if editingLink {
                                    InlineEditableField(
                                        value: activity.link ?? "",
                                        placeholder: "Add link URL",
                                        font: .body,
                                        isEditable: true,
                                        startInEditMode: true,
                                        onSave: { newValue in
                                            editingLink = false
                                            Task { await updateLink(newValue) }
                                        },
                                        onCancel: { editingLink = false }
                                    )
                                } else if let link = activity.link, !link.isEmpty,
                                          let url = URL(string: link), url.scheme != nil, url.host != nil {
                                    EditableLinkDisplay(
                                        text: link,
                                        url: url,
                                        accentColor: theme.accent,
                                        isEditable: !activity.isArchived,
                                        onEdit: { editingLink = true }
                                    )
                                } else if !activity.isArchived {
                                    InlineEditableField(
                                        value: activity.link ?? "",
                                        placeholder: "Add link URL",
                                        font: .body,
                                        isEditable: true,
                                        onSave: { newValue in
                                            Task { await updateLink(newValue) }
                                        }
                                    )
                                } else if let link = activity.link, !link.isEmpty {
                                    Text(link)
                                        .font(.body)
                                }
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Links", systemImage: "link")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(.horizontal) { width, _ in
                    width * 0.6
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownEditor(text: $notes, isEditable: !activity.isArchived)
                    .frame(minHeight: 200)

                if !activity.isArchived && notes != (activity.notes ?? "") {
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            notes = activity.notes ?? ""
                        }
                        .buttonStyle(.bordered)

                        Button("Save Notes") {
                            Task { await saveNotes() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(4)
        } label: {
            HStack {
                Label("Notes", systemImage: "doc.text")
                Spacer()
                Text("Markdown")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if tags.isEmpty {
                    Text("No tags assigned")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            HStack(spacing: 4) {
                                Text(tag.name)
                                    .font(.callout)

                                if !activity.isArchived {
                                    Button {
                                        Task { await removeTag(tag) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }

                if !activity.isArchived {
                    TagPicker(
                        allTags: appState.allTags,
                        assignedTags: tags,
                        onAdd: { tag in Task { await addTag(tag) } }
                    )
                }
            }
            .padding(4)
        } label: {
            Label("Tags", systemImage: "tag")
        }
    }

    // MARK: - Footer

    private var activityFooter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Created \(TimeFormatting.formatRelativeWithTimestamp(activity.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Updated \(TimeFormatting.formatRelativeWithTimestamp(activity.updatedAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if !activity.isArchived {
                    Button {
                        Task { await handleArchive() }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.warning)
                    .accessibilityLabel("Archive activity")
                } else {
                    Button {
                        Task { await handleUnarchive() }
                    } label: {
                        Label("Unarchive", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Unarchive activity")

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete activity")
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Actions

    private func loadDetails() async {
        baseUrl = (try? await appState.service.getPreference(key: PreferenceKey.externalIdBaseUrl)) ?? ""
        await loadTags()
    }

    private func reload() async {
        do {
            activity = try await appState.service.getActivity(id: activity.id!)
            notes = activity.notes ?? ""
            await loadTags()
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not reload activity")
        }
    }

    private func loadTags() async {
        do {
            let allActivityTags = try await appState.service.listTags()
            // Filter to only tags assigned to this activity
            // We need to check the activity_tag table
            tags = allActivityTags.filter { tag in
                // For now, load via a service call — we'll refine this
                true
            }
            // Actually fetch assigned tags properly
            tags = try await loadAssignedTags()
        } catch {
            appState.showError(error, context: "Could not load tags")
        }
    }

    private func loadAssignedTags() async throws -> [Tag] {
        // Use GRDB association to fetch tags for this activity
        try await appState.service.tagsForActivity(activityId: activity.id!)
    }

    private func updateTitle(_ newTitle: String) async {
        guard !newTitle.isEmpty else { return }
        do {
            activity = try await appState.service.updateActivity(
                id: activity.id!,
                UpdateActivityInput(title: newTitle)
            )
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not update title")
        }
    }

    private func updateExternalId(_ newValue: String) async {
        do {
            activity = try await appState.service.updateActivity(
                id: activity.id!,
                UpdateActivityInput(externalId: newValue)
            )
        } catch {
            appState.showError(error, context: "Could not update external ID")
        }
    }

    private func updateLink(_ newValue: String) async {
        do {
            activity = try await appState.service.updateActivity(
                id: activity.id!,
                UpdateActivityInput(link: newValue)
            )
        } catch {
            appState.showError(error, context: "Could not update link")
        }
    }

    private func saveNotes() async {
        do {
            _ = try await appState.service.updateActivity(
                id: activity.id!,
                UpdateActivityInput(notes: notes)
            )
            activity.notes = notes.isEmpty ? nil : notes
        } catch {
            appState.showError(error, context: "Could not save notes")
        }
    }

    private func addTag(_ tag: Tag) async {
        do {
            try await appState.service.tagActivity(activityId: activity.id!, tagId: tag.id!)
            await loadTags()
        } catch {
            appState.showError(error, context: "Could not add tag")
        }
    }

    private func removeTag(_ tag: Tag) async {
        do {
            try await appState.service.untagActivity(activityId: activity.id!, tagId: tag.id!)
            await loadTags()
        } catch {
            appState.showError(error, context: "Could not remove tag")
        }
    }

    private func handleArchive() async {
        do {
            let result = try await appState.service.archiveActivity(id: activity.id!)
            archiveResult = result
            if case .promptDelete = result {
                showingArchiveConfirm = true
            } else {
                await reload()
            }
        } catch {
            appState.showError(error, context: "Could not archive activity")
        }
    }

    private func handleUnarchive() async {
        do {
            _ = try await appState.service.unarchiveActivity(id: activity.id!)
            await reload()
        } catch {
            appState.showError(error, context: "Could not unarchive activity")
        }
    }

    // MARK: - Helpers

    private func resolvedExternalURL(for externalId: String) -> URL? {
        guard !baseUrl.isEmpty else { return nil }
        return URL(string: baseUrl + externalId)
    }
}

// MARK: - Editable Link Display

private struct EditableLinkDisplay: View {
    let text: String
    let url: URL
    let accentColor: Color
    var isEditable: Bool = true
    var onEdit: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Link(destination: url) {
                Text(text)
                    .underline()
                    .font(.body)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
            }

            Link(destination: url) {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(accentColor)
            }

            if isEditable && isHovering {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit")
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Tag Picker

struct TagPicker: View {
    let allTags: [Tag]
    let assignedTags: [Tag]
    var onAdd: (Tag) -> Void

    @State private var newTagName = ""
    @Environment(AppState.self) private var appState

    private var availableTags: [Tag] {
        let assignedIds = Set(assignedTags.map(\.id))
        return allTags.filter { !assignedIds.contains($0.id) }
    }

    var body: some View {
        HStack {
            if !availableTags.isEmpty {
                Menu("Add Tag") {
                    ForEach(availableTags) { tag in
                        Button(tag.name) { onAdd(tag) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            TextField("New tag...", text: $newTagName)
                .textFieldStyle(.plain)
                .frame(width: 120)
                .onSubmit {
                    guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        do {
                            let tag = try await appState.service.createTag(name: newTagName)
                            newTagName = ""
                            onAdd(tag)
                            await appState.refreshAll()
                        } catch {
                            appState.showError(error, context: "Could not create tag")
                        }
                    }
                }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                   proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
