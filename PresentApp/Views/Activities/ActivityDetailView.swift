import SwiftUI
import PresentCore

struct ActivityDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var activity: Activity
    @State private var notes: String
    @State private var tags: [Tag] = []
    @State private var baseUrl = ""
    @State private var showingEditSheet = false
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                linksSection
                notesSection
                tagsSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(activity.title)
        .toolbar {
            ToolbarItemGroup {
                if !activity.isArchived {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        Task { await handleArchive() }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } else {
                    Button {
                        Task { await handleUnarchive() }
                    } label: {
                        Label("Unarchive", systemImage: "arrow.uturn.backward")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ActivityFormSheet(mode: .edit(activity))
        }
        .alert("Archive Activity?", isPresented: $showingArchiveConfirm) {
            Button("Archive") {
                Task {
                    do {
                        _ = try await appState.service.archiveActivity(id: activity.id!)
                        await reload()
                    } catch {
                        print("Error archiving: \(error)")
                    }
                }
            }
            Button("Delete Instead", role: .destructive) {
                Task {
                    do {
                        try await appState.service.deleteActivity(id: activity.id!)
                        await appState.refreshAll()
                    } catch {
                        print("Error deleting: \(error)")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
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
                        print("Error deleting: \(error)")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the activity and all its sessions. This cannot be undone.")
        }
        .task {
            await loadDetails()
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
        }
        .onChange(of: appState.rhythmDurationOptions) {
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
        }
        .onChange(of: showingEditSheet) {
            if !showingEditSheet {
                Task { await reload() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.title)
                        .font(.title.bold())

                    if activity.isArchived {
                        Text("Archived")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }

                Text("Created \(TimeFormatting.formatDate(activity.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !activity.isArchived {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(SessionType.allCases, id: \.self) { type in
                            let isSelected = selectedSessionType == type
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedSessionType = type
                                }
                            } label: {
                                Text(SessionTypeConfig.config(for: type).displayName)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
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
                                        .font(.caption2.weight(isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if selectedSessionType == .timebound {
                        HStack(spacing: 4) {
                            Text("Duration:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("", value: $timeboundMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 48)
                                .font(.caption)
                            Text("min")
                                .font(.caption)
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
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Group {
            if activity.externalId != nil || activity.link != nil {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        ExternalIDLink(activity: activity, baseUrl: baseUrl)
                    }
                    .padding(4)
                } label: {
                    Label("Links", systemImage: "link")
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

                if !activity.isArchived {
                    HStack {
                        Spacer()
                        Button("Save Notes") {
                            Task { await saveNotes() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(notes == (activity.notes ?? ""))
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Notes", systemImage: "doc.text")
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if tags.isEmpty {
                    Text("No tags assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            HStack(spacing: 4) {
                                Text(tag.name)
                                    .font(.caption)

                                if !activity.isArchived {
                                    Button {
                                        Task { await removeTag(tag) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
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
            print("Error reloading activity: \(error)")
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
            print("Error loading tags: \(error)")
        }
    }

    private func loadAssignedTags() async throws -> [Tag] {
        // Use GRDB association to fetch tags for this activity
        try await appState.service.tagsForActivity(activityId: activity.id!)
    }

    private func saveNotes() async {
        do {
            _ = try await appState.service.updateActivity(
                id: activity.id!,
                UpdateActivityInput(notes: notes)
            )
            activity.notes = notes.isEmpty ? nil : notes
        } catch {
            print("Error saving notes: \(error)")
        }
    }

    private func addTag(_ tag: Tag) async {
        do {
            try await appState.service.tagActivity(activityId: activity.id!, tagId: tag.id!)
            await loadTags()
        } catch {
            print("Error adding tag: \(error)")
        }
    }

    private func removeTag(_ tag: Tag) async {
        do {
            try await appState.service.untagActivity(activityId: activity.id!, tagId: tag.id!)
            await loadTags()
        } catch {
            print("Error removing tag: \(error)")
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
            print("Error archiving: \(error)")
        }
    }

    private func handleUnarchive() async {
        do {
            _ = try await appState.service.unarchiveActivity(id: activity.id!)
            await reload()
        } catch {
            print("Error unarchiving: \(error)")
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
                            print("Error creating tag: \(error)")
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
