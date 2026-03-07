import SwiftUI
import PresentCore

struct ActivitiesDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var activity: Activity
    @State private var notes: String
    @State private var tags: [Tag] = []
    @State private var showingArchiveConfirm = false
    @State private var archiveResult: ArchiveResult?
    @State private var showingDeleteConfirm = false
    @State private var selectedSessionType: SessionType = .work
    @State private var selectedRhythmOption: RhythmOption?
    @State private var timeboundMinutes: Int = 25
    @State private var titleText: String
    @State private var isMetadataExpanded = false
    @FocusState private var isTitleFocused: Bool
    var tagColorMap: [String: Color] = [:]
    var startInEditMode: Bool = false
    var onDelete: (() -> Void)?

    init(activity: Activity, tagColorMap: [String: Color] = [:], startInEditMode: Bool = false, onDelete: (() -> Void)? = nil) {
        _activity = State(initialValue: activity)
        _notes = State(initialValue: activity.notes ?? "")
        _titleText = State(initialValue: activity.title)
        self.tagColorMap = tagColorMap
        self.startInEditMode = startInEditMode
        self.onDelete = onDelete
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    if activity.isSystem {
                        systemActivityInfo
                        Spacer(minLength: 0)
                    } else {
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
            Button("Delete Instead", role: .destructive) {
                Task {
                    guard let activityId = activity.id else { return }
                    do {
                        try await appState.deleteActivity(id: activityId)
                        onDelete?()
                        await appState.refreshAll()
                    } catch {
                        appState.showError(error, context: "Could not delete activity")
                    }
                }
            }
            Button("Archive") {
                Task {
                    guard let activityId = activity.id else { return }
                    do {
                        _ = try await appState.archiveActivity(id: activityId, force: true)
                        await reload()
                    } catch {
                        appState.showError(error, context: "Could not archive activity")
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
                        try await appState.deleteActivity(id: activityId)
                        onDelete?()
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
            timeboundMinutes = (try? await appState.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
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
                    if isEditable {
                        TextField("Activity title", text: $titleText)
                            .font(.statValue)
                            .textFieldStyle(.plain)
                            .focused($isTitleFocused)
                            .onSubmit { Task { await saveTitle() } }
                            .onChange(of: isTitleFocused) {
                                if !isTitleFocused {
                                    Task { await saveTitle() }
                                }
                            }
                            .onAppear {
                                if startInEditMode {
                                    isTitleFocused = true
                                }
                            }
                    } else {
                        Text(activity.title)
                            .font(.statValue)
                    }

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
        .padding(.bottom, Constants.spacingCompact)
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

    // MARK: - Notes

    private var notesSection: some View {
        GroupBox {
            MarkdownEditor(
                text: $notes,
                isEditable: !activity.isArchived,
                onCommit: { Task { await saveNotes() } }
            )
            .frame(maxWidth: 700, alignment: .leading)
            .frame(minHeight: 200)
            .onKeyPress(.escape) {
                notes = activity.notes ?? ""
                return .handled
            }
            .padding(Constants.spacingTight)
        } label: {
            HStack {
                Label("Notes", systemImage: "doc.text")
                if activity.link != nil {
                    TicketBadge(
                        ticketId: activity.externalId,
                        link: activity.link
                    )
                }
                Spacer()
                MarkdownHelpButton()
            }
        }
    }

    // MARK: - Tags

    private var availableTags: [Tag] {
        let assignedIds = Set(tags.map(\.id))
        return appState.allTags.filter { !assignedIds.contains($0.id) }
    }

    private var tagsSection: some View {
        GroupBox {
            FlowLayout(spacing: 6) {
                if !activity.isArchived {
                    // Browse all available tags
                    Menu {
                        if availableTags.isEmpty {
                            Text("No more tags available")
                        } else {
                            ForEach(availableTags) { tag in
                                Button(tag.name) {
                                    Task { await addTag(tag) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "tag.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.vertical, Constants.spacingTight)
                    .accessibilityLabel("Browse tags")
                    .help("Browse all tags")
                }

                // Assigned tag pills
                ForEach(tags) { tag in
                    let color = tagColorMap[tag.name] ?? .secondary
                    HStack(spacing: 4) {
                        Text(tag.name)
                            .font(.callout)
                            .foregroundStyle(color)

                        if !activity.isArchived {
                            Button {
                                Task { await removeTag(tag) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Constants.spacingCompact)
                    .padding(.vertical, Constants.spacingTight)
                    .background(color.opacity(0.15), in: Capsule())
                }

                // Free-type autocomplete input
                if !activity.isArchived {
                    InlineTagInput(
                        allTags: appState.allTags,
                        assignedTags: tags,
                        onAdd: { tag in Task { await addTag(tag) } },
                        onCreate: { name in Task { await createAndAddTag(name) } }
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
                if isMetadataExpanded {
                    Text("Created \(TimeFormatting.formatRelativeWithTimestamp(activity.createdAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Updated \(TimeFormatting.formatRelativeWithTimestamp(activity.updatedAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Updated \(TimeFormatting.formatShortRelative(activity.updatedAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onTapGesture {
                withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                    isMetadataExpanded.toggle()
                }
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
                        .tint(.secondary)
                        .accessibilityLabel("Unarchive activity")

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.alert)
                        .accessibilityLabel("Delete activity")
                    }
                }
            }
        }
        .padding(.top, Constants.spacingCard)
    }

    // MARK: - Actions

    private func loadDetails() async {
        await loadTags()
    }

    private func reload() async {
        guard let activityId = activity.id else { return }
        do {
            activity = try await appState.getActivity(id: activityId)
            titleText = activity.title
            notes = activity.notes ?? ""
            await loadTags()
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not reload activity")
        }
    }

    private func loadTags() async {
        do {
            tags = try await loadAssignedTags()
        } catch {
            appState.showError(error, context: "Could not load tags")
        }
    }

    private func loadAssignedTags() async throws -> [Tag] {
        guard let activityId = activity.id else { return [] }
        // Use GRDB association to fetch tags for this activity
        return try await appState.tagsForActivity(activityId: activityId)
    }

    private func saveTitle() async {
        let trimmed = titleText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != activity.title, let activityId = activity.id else {
            // Revert to current title if empty or unchanged
            titleText = activity.title
            return
        }
        do {
            activity = try await appState.updateActivity(
                id: activityId,
                UpdateActivityInput(title: trimmed)
            )
            titleText = activity.title
            await appState.refreshAll()
        } catch {
            titleText = activity.title
            appState.showError(error, context: "Could not update title")
        }
    }

    private func saveNotes() async {
        guard let activityId = activity.id else { return }
        guard notes != (activity.notes ?? "") else { return }
        do {
            activity = try await appState.updateActivity(
                id: activityId,
                UpdateActivityInput(notes: notes)
            )
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not save notes")
        }
    }

    private func createAndAddTag(_ name: String) async {
        do {
            let tag = try await appState.findOrCreateTag(name: name)
            await addTag(tag)
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not create tag")
        }
    }

    private func addTag(_ tag: Tag) async {
        guard let activityId = activity.id, let tagId = tag.id else { return }
        do {
            try await appState.tagActivity(activityId: activityId, tagId: tagId)
            await loadTags()
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not add tag")
        }
    }

    private func removeTag(_ tag: Tag) async {
        guard let activityId = activity.id, let tagId = tag.id else { return }
        do {
            try await appState.untagActivity(activityId: activityId, tagId: tagId)
            await loadTags()
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not remove tag")
        }
    }

    private func handleArchive() async {
        guard let activityId = activity.id else { return }
        do {
            let result = try await appState.archiveActivity(id: activityId)
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
            _ = try await appState.unarchiveActivity(id: activityId)
            await reload()
        } catch {
            appState.showError(error, context: "Could not unarchive activity")
        }
    }

}

// MARK: - Inline Tag Input

struct InlineTagInput: View {
    let allTags: [Tag]
    let assignedTags: [Tag]
    var onAdd: (Tag) -> Void
    var onCreate: (String) -> Void

    @State private var searchText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Add tag\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 100)
                .focused($isInputFocused)
                .onKeyPress(.escape) {
                    searchText = ""
                    return .handled
                }
                .onSubmit {
                    let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }

                    // Match an existing unassigned tag (case-insensitive)
                    let assignedIds = Set(assignedTags.map(\.id))
                    if let match = allTags.first(where: {
                        !assignedIds.contains($0.id)
                            && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                    }) {
                        onAdd(match)
                    } else {
                        onCreate(trimmed)
                    }

                    searchText = ""
                    isInputFocused = true
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isInputFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear tag input")
            }
        }
        .padding(.vertical, Constants.spacingTight)
    }
}

