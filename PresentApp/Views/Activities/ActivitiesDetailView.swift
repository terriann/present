import SwiftUI
import PresentCore

struct ActivitiesDetailView: View {
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
        _editExternalId = State(initialValue: activity.externalId ?? "")
        _editLink = State(initialValue: activity.link ?? "")
    }

    @State private var editExternalId: String = ""
    @State private var editLink: String = ""

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    if activity.isSystem {
                        systemActivityInfo
                        Spacer(minLength: 0)
                    } else {
                        linksSection
                        notesSection
                        tagsSection
                    }
                    activityFooter
                }
                .padding(Constants.spacingPage)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .alert("Archive Activity?", isPresented: $showingArchiveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Archive") {
                Task {
                    guard let activityId = activity.id else { return }
                    do {
                        _ = try await appState.service.archiveActivity(id: activityId)
                        await reload()
                    } catch {
                        appState.showError(error, context: "Could not archive activity")
                    }
                }
            }
            Button("Delete Instead", role: .destructive) {
                Task {
                    guard let activityId = activity.id else { return }
                    do {
                        try await appState.service.deleteActivity(id: activityId)
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
                    guard let activityId = activity.id else { return }
                    do {
                        try await appState.service.deleteActivity(id: activityId)
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
            if activity.isSystem && selectedSessionType == .rhythm {
                selectedSessionType = .work
            }
        }
        .syncRhythmSelection($selectedRhythmOption)
    }

    private var isEditable: Bool { !activity.isArchived && !activity.isSystem }
    private var allowedSessionTypes: [SessionType] {
        activity.isSystem ? [.work, .timebound] : SessionType.allCases
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
                        font: .statValue,
                        isEditable: isEditable,
                        onSave: { newTitle in
                            Task { await updateTitle(newTitle) }
                        }
                    )

                    if activity.isSystem {
                        Text("System")
                            .font(.caption)
                            .padding(.horizontal, Constants.spacingCompact)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.2), in: Capsule())
                    }

                    if activity.isArchived {
                        Text("Archived")
                            .font(.caption)
                            .padding(.horizontal, Constants.spacingCompact)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }
            }

            Spacer()

            // Right: session controls (fixed position, not affected by title editing)
            if !activity.isArchived || activity.isSystem {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(allowedSessionTypes, id: \.self) { type in
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
                                    Text(option.displayLabel)
                                        .font(.caption.weight(isSelected ? .semibold : .regular))
                                        .padding(.horizontal, Constants.spacingCompact)
                                        .padding(.vertical, 3)
                                        .background(isSelected ? theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                        .foregroundStyle(isSelected ? theme.accent : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if selectedSessionType == .timebound {
                        TimeboundDurationField(minutes: $timeboundMinutes, size: .regular)
                    }

                    Button("Start Session") {
                        Task {
                            guard let activityId = activity.id else { return }
                            switch selectedSessionType {
                            case .rhythm:
                                let option = selectedRhythmOption ?? appState.rhythmDurationOptions.first
                                await appState.startSession(
                                    activityId: activityId,
                                    type: .rhythm,
                                    timerMinutes: option?.focusMinutes,
                                    breakMinutes: option?.breakMinutes
                                )
                            case .timebound:
                                await appState.startSession(
                                    activityId: activityId,
                                    type: .timebound,
                                    timerMinutes: timeboundMinutes
                                )
                            default:
                                await appState.startSession(
                                    activityId: activityId,
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

    // MARK: - System Activity Info

    private var systemActivityInfo: some View {
        VStack(spacing: Constants.spacingPage) {
            SteamingCupIcon()
                .environment(theme)

            VStack(spacing: Constants.spacingCard) {
                Text("This is a system activity")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Break is a built-in part of how Rhythm Sessions work. After each focus period, Present uses this activity to track your rest time, keeping the natural flow of focused work followed by recovery.\n\nBecause it's tied to the cycle of a Rhythm Session, it can't be renamed, archived, or deleted.\n\nYou're welcome to use Break on its own with a work session to track open-ended downtime, or with a timebound session if you'd like a countdown for a specific break length.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 480)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.spacingPage)
    }

    // MARK: - Links

    private var hasLinkChanges: Bool {
        editExternalId != (activity.externalId ?? "") || editLink != (activity.link ?? "")
    }

    private var linksSection: some View {
        Group {
            if !activity.isArchived || activity.externalId != nil || activity.link != nil {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // External ID
                        if !activity.isArchived || activity.externalId != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("External ID")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if activity.isArchived {
                                    Text(activity.externalId ?? "")
                                        .font(.body)
                                } else {
                                    HStack(spacing: 6) {
                                        TextField("Add external ID", text: $editExternalId)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body)

                                        if let url = resolvedExternalURL(for: editExternalId), !editExternalId.isEmpty {
                                            Link(destination: url) {
                                                Image(systemName: "arrow.up.right")
                                                    .font(.body)
                                                    .foregroundStyle(theme.accent)
                                            }
                                            .accessibilityLabel("Open external ID link")
                                        }
                                    }
                                }
                            }
                        }

                        // Link
                        if !activity.isArchived || activity.link != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Link")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if activity.isArchived {
                                    if let link = activity.link, !link.isEmpty,
                                       let url = URL(string: link) {
                                        Link(destination: url) {
                                            Text(link)
                                                .underline()
                                                .font(.body)
                                                .foregroundStyle(theme.accent)
                                                .lineLimit(1)
                                        }
                                    } else {
                                        Text(activity.link ?? "")
                                            .font(.body)
                                    }
                                } else {
                                    HStack(spacing: 6) {
                                        TextField("Add link URL", text: $editLink)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body)

                                        if let url = URL(string: editLink), url.scheme != nil, url.host != nil, !editLink.isEmpty {
                                            Link(destination: url) {
                                                Image(systemName: "arrow.up.right")
                                                    .font(.body)
                                                    .foregroundStyle(theme.accent)
                                            }
                                            .accessibilityLabel("Open link")
                                        }
                                    }
                                }
                            }
                        }

                        // Save/Cancel when changes exist
                        if !activity.isArchived && hasLinkChanges {
                            HStack {
                                Spacer()

                                Button {
                                    editExternalId = activity.externalId ?? ""
                                    editLink = activity.link ?? ""
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(theme.alert)
                                .accessibilityLabel("Cancel link changes")

                                Button {
                                    Task { await saveLinks() }
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(theme.success)
                                .accessibilityLabel("Save links")
                            }
                        }
                    }
                    .padding(Constants.spacingTight)
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
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(minHeight: 200)

                if !activity.isArchived && notes != (activity.notes ?? "") {
                    HStack {
                        Spacer()

                        Button {
                            notes = activity.notes ?? ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.alert)
                        .accessibilityLabel("Cancel note changes")

                        Button {
                            Task { await saveNotes() }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.success)
                        .accessibilityLabel("Save notes")
                    }
                }
            }
            .padding(Constants.spacingTight)
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
                            .padding(.horizontal, Constants.spacingCompact)
                            .padding(.vertical, Constants.spacingTight)
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
            .padding(Constants.spacingTight)
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

            if !activity.isSystem {
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
        }
        .padding(.top, Constants.spacingCard)
    }

    // MARK: - Actions

    private func loadDetails() async {
        baseUrl = (try? await appState.service.getPreference(key: PreferenceKey.externalIdBaseUrl)) ?? ""
        await loadTags()
    }

    private func reload() async {
        guard let activityId = activity.id else { return }
        do {
            activity = try await appState.service.getActivity(id: activityId)
            notes = activity.notes ?? ""
            editExternalId = activity.externalId ?? ""
            editLink = activity.link ?? ""
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
        guard let activityId = activity.id else { return [] }
        // Use GRDB association to fetch tags for this activity
        return try await appState.service.tagsForActivity(activityId: activityId)
    }

    private func updateTitle(_ newTitle: String) async {
        guard !newTitle.isEmpty, let activityId = activity.id else { return }
        do {
            activity = try await appState.service.updateActivity(
                id: activityId,
                UpdateActivityInput(title: newTitle)
            )
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not update title")
        }
    }

    private func saveLinks() async {
        guard let activityId = activity.id else { return }
        do {
            activity = try await appState.service.updateActivity(
                id: activityId,
                UpdateActivityInput(externalId: editExternalId, link: editLink)
            )
            editExternalId = activity.externalId ?? ""
            editLink = activity.link ?? ""
        } catch {
            appState.showError(error, context: "Could not update links")
        }
    }

    private func saveNotes() async {
        guard let activityId = activity.id else { return }
        do {
            _ = try await appState.service.updateActivity(
                id: activityId,
                UpdateActivityInput(notes: notes)
            )
            activity.notes = notes.isEmpty ? nil : notes
        } catch {
            appState.showError(error, context: "Could not save notes")
        }
    }

    private func addTag(_ tag: Tag) async {
        guard let activityId = activity.id, let tagId = tag.id else { return }
        do {
            try await appState.service.tagActivity(activityId: activityId, tagId: tagId)
            await loadTags()
        } catch {
            appState.showError(error, context: "Could not add tag")
        }
    }

    private func removeTag(_ tag: Tag) async {
        guard let activityId = activity.id, let tagId = tag.id else { return }
        do {
            try await appState.service.untagActivity(activityId: activityId, tagId: tagId)
            await loadTags()
        } catch {
            appState.showError(error, context: "Could not remove tag")
        }
    }

    private func handleArchive() async {
        guard let activityId = activity.id else { return }
        do {
            let result = try await appState.service.archiveActivity(id: activityId)
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
        guard let activityId = activity.id else { return }
        do {
            _ = try await appState.service.unarchiveActivity(id: activityId)
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
                            let tag = try await appState.service.findOrCreateTag(name: newTagName)
                            newTagName = ""
                            onAdd(tag)
                            await appState.refreshAll()
                        } catch {
                            appState.showError(error, context: "Could not add tag")
                        }
                    }
                }
        }
    }
}

