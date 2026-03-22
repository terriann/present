import SwiftUI
import PresentCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedSessionType: SessionType = .work
    @State private var selectedRhythmOption: RhythmOption?
    @State private var timeboundMinutes: Int = 25
    @State private var activitySort: String = "recent"
    @State private var selectedIndex: Int?
    @State private var isSortRecentHovered = false
    @State private var isSortAlphaHovered = false
    @State private var isLaunchHovered = false
    @State private var isSettingsHovered = false
    @State private var showSessionEditForm = false
    @State private var isExpanded = false
    @State private var switchActivityTarget: Activity?
    @State private var switchFromActivityTitle: String?
    @State private var isEditHovered = false
    @State private var isChevronHovered = false
    @State private var hoveredSessionType: SessionType?
    @State private var hoveredRhythmOption: RhythmOption?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isPanelFocused: Bool

    private var zoomScale: CGFloat { appState.zoomScale }

    var body: some View {
        VStack(spacing: 0) {
            if switchActivityTarget != nil {
                switchConfirmationBar
            } else if appState.isSessionRunning {
                currentSessionSection
                chevronToggle

                if isExpanded {
                    Divider()
                    quickStartSection
                    Divider()
                    bottomBar
                }
            } else {
                if appState.isSessionActive {
                    currentSessionSection
                } else {
                    idleSection
                }

                Divider()

                quickStartSection

                Divider()

                bottomBar
            }
        }
        .frame(width: (switchActivityTarget != nil ? 400 : 320) * zoomScale)
        .adaptiveAnimation(.easeInOut(duration: 0.2), value: switchActivityTarget != nil)
        .focusable()
        .focused($isPanelFocused)
        .focusEffectDisabled()
        .onAppear {
            isPanelFocused = true
            isExpanded = false
        }
        .onDisappear {
            // Force any active text editor to resign first responder before removing the form.
            // This triggers save-on-blur callbacks (e.g., saveNote) synchronously, ensuring
            // buffered changes are flushed before the form disappears.
            if showSessionEditForm {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            searchText = ""
            selectedIndex = nil
            switchActivityTarget = nil
            switchFromActivityTitle = nil
            showSessionEditForm = false
        }
        .onKeyPress(.escape) {
            if switchActivityTarget != nil {
                switchActivityTarget = nil
                switchFromActivityTitle = nil
                return .handled
            }
            dismiss()
            return .handled
        }
    }

    // MARK: - Switch Confirmation

    /// The effective session type for the switch target, accounting for system activity restrictions.
    private var switchTargetSessionType: SessionType {
        guard let target = switchActivityTarget else { return selectedSessionType }
        return (target.isSystem && selectedSessionType == .rhythm) ? .work : selectedSessionType
    }

    private var switchConfirmationBar: some View {
        VStack(spacing: Constants.spacingCard) {
            Text("Time to move on?")
                .font(scaledFont(.headline))

            HStack(alignment: .center, spacing: Constants.spacingCompact) {
                // Current session
                if let currentTitle = switchFromActivityTitle,
                   let session = appState.currentSession {
                    switchSessionColumn(
                        activityTitle: currentTitle,
                        sessionType: session.sessionType,
                        sessionTypeDetail: switchSessionTypeDetail(for: session)
                    )
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "arrow.right")
                    .font(scaledFont(.title2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                // Target session
                if let target = switchActivityTarget {
                    switchSessionColumn(
                        activityTitle: target.title,
                        sessionType: switchTargetSessionType,
                        sessionTypeDetail: switchTargetTypeDetail
                    )
                }
            }

            VStack(spacing: Constants.spacingCompact) {
                Button("Begin \(switchActivityTarget?.title ?? "")") {
                    guard let target = switchActivityTarget else { return }
                    switchActivityTarget = nil
                    switchFromActivityTitle = nil
                    Task {
                        await switchSessionForType(activity: target)
                        withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Cancel") {
                    switchActivityTarget = nil
                    switchFromActivityTitle = nil
                }
                .buttonStyle(.plain)
                .font(scaledFont(.caption))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, Constants.spacingCompact)
        }
        .padding(Constants.spacingPage)
    }

    private func switchSessionColumn(activityTitle: String, sessionType: SessionType, sessionTypeDetail: String) -> some View {
        VStack(spacing: Constants.spacingTight) {
            Image(systemName: sessionTypeIcon(for: sessionType))
                .font(scaledFont(.title3))
                .accessibilityHidden(true)
                .padding(.bottom, Constants.spacingCard)
            Text(activityTitle)
                .font(scaledFont(.body, weight: .medium))
                .lineLimit(1)
            Text(sessionTypeDetail)
                .font(scaledFont(.caption))
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionTypeIcon(for type: SessionType) -> String {
        switch type {
        case .work: "infinity"
        case .timebound: "timer"
        case .rhythm: "arrow.triangle.2.circlepath"
        }
    }


    /// Format session type detail for the current (running) session, matching `ActivitySessionCard.sessionTypeLabel`.
    private func switchSessionTypeDetail(for session: Session) -> String {
        let base = SessionTypeConfig.config(for: session.sessionType).displayName
        switch session.sessionType {
        case .timebound:
            if let minutes = session.timerLengthMinutes {
                return "\(base) \u{00B7} \(minutes)m"
            }
        case .rhythm:
            if let work = session.timerLengthMinutes, let brk = session.breakMinutes {
                return "\(base) \u{00B7} \(RhythmOption(focusMinutes: work, breakMinutes: brk).displayLabel)"
            }
        case .work:
            break
        }
        return base
    }

    /// Format session type detail for the switch target based on the selected session type picker.
    private var switchTargetTypeDetail: String {
        let type = switchTargetSessionType
        let base = SessionTypeConfig.config(for: type).displayName
        switch type {
        case .timebound:
            return "\(base) \u{00B7} \(timeboundMinutes)m"
        case .rhythm:
            let option = selectedRhythmOption ?? appState.rhythmDurationOptions.first
            if let option {
                return "\(base) \u{00B7} \(option.displayLabel)"
            }
            return base
        case .work:
            return base
        }
    }

    // MARK: - Scaled Fonts

    /// Returns a font scaled by the menu bar zoom level.
    ///
    /// At the default zoom (`1.0`), this returns `.system(style, weight:)` which
    /// fully respects the user's Dynamic Type / accessibility text size setting.
    ///
    /// At non-default zoom levels the method uses hard-coded base sizes instead of
    /// querying Dynamic Type. This is intentional: the menu bar popover is
    /// width-constrained (320pt * zoomScale) and the zoom feature serves as the
    /// popover's own accessibility scaling mechanism. Layering Dynamic Type on top
    /// of zoom would risk text clipping and layout overflow at large combined sizes.
    ///
    /// Trade-off documented in GitHub issue #136.
    private func scaledFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard zoomScale != 1.0 else {
            return .system(style, weight: weight)
        }
        let baseSize: CGFloat = switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote: 10
        case .caption, .caption2: 10
        default: 13
        }
        return .system(size: round(baseSize * zoomScale), weight: weight)
    }

    // MARK: - Current Session

    private var currentSessionSection: some View {
        VStack(spacing: 12 * zoomScale) {
            if let activity = appState.currentActivity, let session = appState.currentSession {
                // Clickable region: activity name + session type + timer
                Button {
                    withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                        showSessionEditForm.toggle()
                    }
                } label: {
                    VStack(spacing: 4 * zoomScale) {
                        Text(activity.title)
                            .font(scaledFont(.headline, weight: .semibold))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                                .font(scaledFont(.caption, weight: .regular))
                                .foregroundStyle(.secondary)

                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .opacity(isEditHovered && !showSessionEditForm ? 1 : 0)
                        }

                        Text(appState.formattedTimerValue)
                            .font(scaledFont(.title, weight: .light).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showSessionEditForm ? "Close edit form" : "Edit session")
                .help(showSessionEditForm ? "Close edit form" : "Edit session")
                .onHover { hovering in isEditHovered = hovering }

                TicketBadge(
                    ticketId: session.ticketId,
                    link: session.link,
                    font: scaledFont(.caption),
                    scale: zoomScale
                )

                SessionControls()

                if showSessionEditForm {
                    SessionEditForm(
                        session: session,
                        activity: activity,
                        zoomScale: zoomScale,
                        scaledFont: scaledFont,
                        onSave: dismissEditForm,
                        onCancel: dismissEditForm
                    )
                }
            }
        }
        .padding(Constants.spacingCard * zoomScale)
    }

    // MARK: - Chevron Toggle

    private var chevronToggle: some View {
        Button {
            let wasCollapsed = !isExpanded
            withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
            if wasCollapsed && showSessionEditForm {
                withAdaptiveAnimation(.easeInOut(duration: 0.25)) {
                    showSessionEditForm = false
                }
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(scaledFont(.caption))
                .foregroundStyle(isChevronHovered ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6 * zoomScale)
                .background(isChevronHovered ? Color.primary.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide activities" : "Show activities")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Hide activities" : "Show activities")
        .onHover { hovering in isChevronHovered = hovering }
    }

    // MARK: - Idle

    private var idleSection: some View {
        VStack(spacing: 8 * zoomScale) {
            Image(systemName: "clock")
                .font(scaledFont(.largeTitle))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No active session")
                .font(scaledFont(.headline, weight: .semibold))

            if appState.todaySessionCount > 0 {
                Text("\(appState.todaySessionCount) sessions today \u{2022} \(TimeFormatting.formatDuration(seconds: appState.todayTotalSeconds))")
                    .font(scaledFont(.caption))
                    .foregroundStyle(.secondary)
            }

            if let suggestion = appState.recentSessionSuggestion {
                RecentSuggestionRow(
                    activity: suggestion.activity,
                    session: suggestion.session
                ) {
                    Task {
                        guard let activityId = suggestion.activity.id else { return }
                        await appState.startSession(
                            activityId: activityId,
                            type: suggestion.session.sessionType,
                            timerMinutes: suggestion.session.timerLengthMinutes,
                            breakMinutes: suggestion.session.breakMinutes
                        )
                    }
                }
                .padding(.top, Constants.spacingTight)
            }
        }
        .padding(Constants.spacingCard * zoomScale)
    }

    // MARK: - Quick Start

    private let menuBarSessionTypes: [SessionType] = SessionType.allCases

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: Constants.spacingTight) {
                    ForEach(menuBarSessionTypes, id: \.self) { type in
                        let isSelected = selectedSessionType == type
                        let isHovered = hoveredSessionType == type
                        Button {
                            withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
                                selectedSessionType = type
                            }
                        } label: {
                            Text(SessionTypeConfig.config(for: type).displayName)
                            .font(scaledFont(.caption, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10 * zoomScale)
                            .padding(.vertical, 6 * zoomScale)
                            .background(
                                isSelected ? theme.accent.opacity(0.15) :
                                isHovered ? Color.primary.opacity(0.08) :
                                Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? theme.accent : .secondary)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredSessionType = hovering ? type : nil
                        }
                    }
                }
                .padding(.bottom, Constants.spacingCompact * zoomScale)

                // Duration controls for rhythm/timebound
                if selectedSessionType == .rhythm {
                    HStack(spacing: Constants.spacingTight) {
                        ForEach(Array(appState.rhythmDurationOptions.prefix(4)), id: \.self) { option in
                            let isSelected = selectedRhythmOption == option
                            let isHovered = hoveredRhythmOption == option
                            Button {
                                selectedRhythmOption = option
                            } label: {
                                Text(option.displayLabel)
                                    .font(scaledFont(.caption2, weight: isSelected ? .semibold : .regular))
                                    .padding(.horizontal, Constants.spacingCompact * zoomScale)
                                    .padding(.vertical, 3 * zoomScale)
                                    .background(
                                        isSelected ? theme.accent.opacity(0.12) :
                                        isHovered ? Color.primary.opacity(0.08) :
                                        Color.clear,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(isSelected ? theme.accent : .secondary)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredRhythmOption = hovering ? option : nil
                            }
                        }
                    }
                    .padding(.bottom, 6 * zoomScale)
                } else if selectedSessionType == .timebound {
                    TimeboundDurationField(minutes: $timeboundMinutes, size: .compact, zoomScale: zoomScale)
                        .padding(.bottom, 6 * zoomScale)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Constants.spacingCard * zoomScale)
            .padding(.top, Constants.spacingCompact * zoomScale)

            // Search + sort controls
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(scaledFont(.body))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search or create...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(scaledFont(.body))
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search activities")
                    .onKeyPress(.downArrow) {
                        let maxIndex = selectableItemCount - 1
                        guard maxIndex >= 0 else { return .ignored }
                        if let current = selectedIndex {
                            selectedIndex = min(current + 1, maxIndex)
                        } else {
                            selectedIndex = 0
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard let current = selectedIndex else { return .ignored }
                        if current == 0 {
                            selectedIndex = nil
                        } else {
                            selectedIndex = current - 1
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard let index = selectedIndex else { return .ignored }
                        activateSelectedItem(at: index)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if !searchText.isEmpty || selectedIndex != nil {
                            searchText = ""
                            selectedIndex = nil
                            return .handled
                        }
                        return .ignored
                    }
                    .onChange(of: searchText) {
                        selectedIndex = nil
                    }
                if !searchText.isEmpty {
                    ClearSearchButton {
                        searchText = ""
                    }
                }

                HStack(spacing: 0) {
                    Button {
                        setActivitySort("recent")
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(scaledFont(.caption))
                            .foregroundStyle(activitySort == "recent" ? theme.accent : .secondary)
                            .padding(6 * zoomScale)
                            .background(
                                activitySort == "recent" ? theme.accent.opacity(0.15) :
                                isSortRecentHovered ? Color.primary.opacity(0.08) :
                                Color.clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sort by recent")
                    .help("Sort by recent")
                    .onHover { hovering in isSortRecentHovered = hovering }

                    Button {
                        setActivitySort("alphabetical")
                    } label: {
                        Image(systemName: "textformat.abc")
                            .font(scaledFont(.caption))
                            .foregroundStyle(activitySort == "alphabetical" ? theme.accent : .secondary)
                            .padding(6 * zoomScale)
                            .background(
                                activitySort == "alphabetical" ? theme.accent.opacity(0.15) :
                                isSortAlphaHovered ? Color.primary.opacity(0.08) :
                                Color.clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sort alphabetically")
                    .help("Sort alphabetically")
                    .onHover { hovering in isSortAlphaHovered = hovering }
                }
            }
            .padding(.horizontal, Constants.spacingCard * zoomScale)
            .padding(.vertical, Constants.spacingCompact * zoomScale)

            // Activity list (scrollable)
            let activities = filteredActivities
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
            let showCreateRow = !trimmedSearch.isEmpty && !activities.contains(where: {
                $0.title.caseInsensitiveCompare(trimmedSearch) == .orderedSame
            })

            if activities.isEmpty && trimmedSearch.isEmpty {
                Text("No activities yet")
                    .font(scaledFont(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Constants.spacingCard * zoomScale)
                    .padding(.vertical, Constants.spacingTight * zoomScale)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                                QuickStartRow(
                                    activity: activity,
                                    isSelected: selectedIndex == index,
                                    onTap: {
                                        handleActivityTap(activity: activity)
                                    },
                                    onEdit: {
                                        dismiss()
                                        if let id = activity.id {
                                            appState.navigate(to: .showActivity(id))
                                        }
                                    }
                                )
                                .id(index)
                            }

                            if showCreateRow {
                                createActivityRow(title: trimmedSearch, isSelected: selectedIndex == activities.count)
                                    .id(activities.count)
                            }
                        }
                    }
                    .frame(height: 200 * zoomScale)
                    .onChange(of: selectedIndex) { _, newValue in
                        if let newValue {
                            withAdaptiveAnimation(.easeInOut) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Defer focus to next run loop — NSPopover's window isn't key yet during onAppear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            Task {
                timeboundMinutes = await appState.loadDefaultTimeboundMinutes()
                activitySort = (try? await appState.getPreference(key: PreferenceKey.menuBarActivitySort)) ?? "recent"
            }
        }
        .syncRhythmSelection($selectedRhythmOption)
    }

    private func handleActivityTap(activity: Activity) {
        searchText = ""
        selectedIndex = nil
        if appState.isSessionActive {
            switchFromActivityTitle = appState.currentActivity?.title
            switchActivityTarget = activity
        } else {
            Task {
                await startSessionForType(activity: activity)
            }
        }
    }

    private enum SessionAction { case start, `switch` }

    private func startSessionForType(activity: Activity) async {
        await performSessionAction(.start, activity: activity)
    }

    private func switchSessionForType(activity: Activity) async {
        await performSessionAction(.switch, activity: activity)
    }

    /// Shared session start/switch logic — resolves effective type,
    /// rhythm option, and timebound minutes, then delegates to appState.
    private func performSessionAction(_ action: SessionAction, activity: Activity) async {
        guard let activityId = activity.id else { return }
        // System activities cannot use rhythm sessions — fall back to work
        let effectiveType = (activity.isSystem && selectedSessionType == .rhythm) ? .work : selectedSessionType

        switch effectiveType {
        case .rhythm:
            let option = selectedRhythmOption ?? appState.rhythmDurationOptions.first
            switch action {
            case .start:
                await appState.startSession(
                    activityId: activityId, type: .rhythm,
                    timerMinutes: option?.focusMinutes, breakMinutes: option?.breakMinutes
                )
            case .switch:
                await appState.switchSession(
                    to: activityId, type: .rhythm,
                    timerMinutes: option?.focusMinutes, breakMinutes: option?.breakMinutes
                )
            }
        case .timebound:
            switch action {
            case .start:
                await appState.startSession(
                    activityId: activityId, type: .timebound, timerMinutes: timeboundMinutes
                )
            case .switch:
                await appState.switchSession(
                    to: activityId, type: .timebound, timerMinutes: timeboundMinutes
                )
            }
        default:
            switch action {
            case .start:
                await appState.startSession(activityId: activityId, type: effectiveType)
            case .switch:
                await appState.switchSession(to: activityId, type: effectiveType)
            }
        }
    }

    private var filteredActivities: [Activity] {
        var source = appState.popoverActivities
        if activitySort == "alphabetical" {
            source.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        if searchText.isEmpty {
            return source
        }
        return source.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private func createActivityRow(title: String, isSelected: Bool = false) -> some View {
        CreateActivityButton(title: title, theme: theme, scaledFont: scaledFont, isSelected: isSelected) {
            Task {
                guard let newActivity = try? await appState.createActivity(
                    CreateActivityInput(title: title)
                ) else { return }
                searchText = ""
                handleActivityTap(activity: newActivity)
            }
        }
    }

    private var selectableItemCount: Int {
        let activities = filteredActivities
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        let hasCreateRow = !trimmedSearch.isEmpty && !activities.contains(where: {
            $0.title.caseInsensitiveCompare(trimmedSearch) == .orderedSame
        })
        return activities.count + (hasCreateRow ? 1 : 0)
    }

    private func activateSelectedItem(at index: Int) {
        let activities = filteredActivities
        if index < activities.count {
            let activity = activities[index]
            handleActivityTap(activity: activity)
        } else {
            // Create row
            let title = searchText.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            Task {
                guard let newActivity = try? await appState.createActivity(
                    CreateActivityInput(title: title)
                ) else { return }
                searchText = ""
                selectedIndex = nil
                handleActivityTap(activity: newActivity)
            }
        }
    }

    private func setActivitySort(_ sort: String) {
        activitySort = sort
        Task {
            try? await appState.setPreference(key: PreferenceKey.menuBarActivitySort, value: sort)
        }
    }

    private func dismissEditForm() {
        withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
            showSessionEditForm = false
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                if showSessionEditForm {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    showSessionEditForm = false
                }
                dismiss()
                appState.navigate(to: .showDashboard)
            } label: {
                HStack {
                    Text("Launch Present")
                        .font(scaledFont(.body))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Constants.spacingCard * zoomScale)
                .padding(.vertical, Constants.spacingCard * zoomScale)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Launch Present")
            .onHover { hovering in
                isLaunchHovered = hovering
            }

            Button {
                dismiss()
                appState.navigate(to: .showSettings(nil))
            } label: {
                HStack(spacing: Constants.spacingTight) {
                    if isSettingsHovered {
                        Text("Settings")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    Image(systemName: "gear")
                        .font(scaledFont(.body))
                        .foregroundStyle(isSettingsHovered ? .primary : .secondary)
                }
                .padding(.horizontal, isSettingsHovered ? 8 : 5)
                .padding(.vertical, 4)
                .fixedSize()
                .frame(minHeight: 24)
                .background(
                    isSettingsHovered ? Color.primary.opacity(0.12) : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
            .onHover { hovering in
                if reduceMotion {
                    isSettingsHovered = hovering
                } else {
                    withAdaptiveAnimation(.easeInOut(duration: 0.35)) {
                        isSettingsHovered = hovering
                    }
                }
            }
            .padding(.trailing, Constants.spacingCard * zoomScale)
            .padding(.vertical, Constants.spacingCard * zoomScale)
        }
        .background(isLaunchHovered ? Color.primary.opacity(0.08) : Color.clear)
    }

}

// MARK: - Create Activity Button

private struct CreateActivityButton: View {
    let title: String
    let theme: ThemeManager
    let scaledFont: (Font.TextStyle, Font.Weight) -> Font
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.spacingCompact) {
                Image(systemName: isSelected || isHovered ? "plus.circle.fill" : "plus.circle")
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text("Create \"\(title)\"")
                    .font(scaledFont(.body, .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Constants.spacingCard)
            .padding(.vertical, 6)
            .background(isSelected ? theme.accent.opacity(0.12) : Color.primary.opacity(isHovered ? 0.05 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Clear Search Button

private struct ClearSearchButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(isHovered ? .primary : .secondary)
                .font(.caption)
                .accessibilityLabel("Clear search")
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
