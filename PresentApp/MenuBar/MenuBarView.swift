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
    @State private var newActivityTitle = ""
    @State private var activitySort: String = "recent"
    @State private var isSortRecentHovered = false
    @State private var isSortAlphaHovered = false
    @State private var isLaunchHovered = false
    @State private var isSettingsHovered = false

    private var zoomScale: CGFloat { appState.zoomScale }

    var body: some View {
        VStack(spacing: 0) {
            if appState.isSessionRunning {
                // Focused: timer + controls only
                currentSessionSection
            } else {
                if appState.isSessionActive {
                    currentSessionSection
                } else {
                    idleSection
                }

                Divider()

                quickStartSection
            }

            Divider()

            bottomBar
        }
        .frame(width: 320 * zoomScale)
    }

    // MARK: - Scaled Fonts

    /// Base macOS system font sizes for each text style.
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
                VStack(spacing: 4 * zoomScale) {
                    Text(activity.title)
                        .font(scaledFont(.headline, weight: .semibold))
                        .lineLimit(1)

                    Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                        .font(scaledFont(.caption))
                        .foregroundStyle(.secondary)
                }

                Text(appState.formattedTimerValue)
                    .font(scaledFont(.title, weight: .light).monospacedDigit())
                    .contentTransition(.numericText())

                SessionControls()
            }
        }
        .padding(Constants.spacingCard * zoomScale)
    }

    // MARK: - Idle

    private var idleSection: some View {
        VStack(spacing: 8 * zoomScale) {
            Image(systemName: "clock")
                .font(scaledFont(.largeTitle))
                .foregroundStyle(.secondary)

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
                        await appState.startSession(
                            activityId: suggestion.activity.id!,
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
                HStack(spacing: 4) {
                    ForEach(menuBarSessionTypes, id: \.self) { type in
                        let isSelected = selectedSessionType == type
                        Button {
                            withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
                                selectedSessionType = type
                            }
                        } label: {
                            Text(SessionTypeConfig.config(for: type).displayName)
                                .font(scaledFont(.caption, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 10 * zoomScale)
                                .padding(.vertical, 5 * zoomScale)
                                .background(isSelected ? theme.accent.opacity(0.15) : Color.clear, in: Capsule())
                                .foregroundStyle(isSelected ? theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, Constants.spacingCompact * zoomScale)

                // Duration controls for rhythm/timebound
                if selectedSessionType == .rhythm {
                    HStack(spacing: 4) {
                        ForEach(Array(appState.rhythmDurationOptions.prefix(4)), id: \.self) { option in
                            let isSelected = selectedRhythmOption == option
                            Button {
                                selectedRhythmOption = option
                            } label: {
                                Text(option.displayLabel)
                                    .font(scaledFont(.caption2, weight: isSelected ? .semibold : .regular))
                                    .padding(.horizontal, Constants.spacingCompact * zoomScale)
                                    .padding(.vertical, 3 * zoomScale)
                                    .background(isSelected ? theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                    .foregroundStyle(isSelected ? theme.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 6 * zoomScale)
                } else if selectedSessionType == .timebound {
                    HStack(spacing: 4) {
                        Text("Duration:")
                            .font(scaledFont(.caption))
                            .foregroundStyle(.secondary)
                        TextField("", value: $timeboundMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 48 * zoomScale)
                            .font(scaledFont(.caption))
                        Text("min")
                            .font(scaledFont(.caption))
                            .foregroundStyle(.secondary)
                    }
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
                TextField("Search activities...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(scaledFont(.body))
                if !searchText.isEmpty {
                    ClearSearchButton {
                        searchText = ""
                    }
                }

                Button {
                    setActivitySort("recent")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(scaledFont(.caption))
                        .foregroundStyle(activitySort == "recent" ? theme.accent : .secondary)
                        .padding(6 * zoomScale)
                        .background(isSortRecentHovered ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sort by recent")
                .onHover { hovering in isSortRecentHovered = hovering }

                Button {
                    setActivitySort("alphabetical")
                } label: {
                    Image(systemName: "textformat.abc")
                        .font(scaledFont(.caption))
                        .foregroundStyle(activitySort == "alphabetical" ? theme.accent : .secondary)
                        .padding(6 * zoomScale)
                        .background(isSortAlphaHovered ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sort alphabetically")
                .onHover { hovering in isSortAlphaHovered = hovering }
            }
            .padding(.horizontal, Constants.spacingCard * zoomScale)
            .padding(.vertical, Constants.spacingCompact * zoomScale)

            // Activity list (scrollable)
            let activities = filteredActivities
            if activities.isEmpty {
                Text(searchText.isEmpty ? "No activities" : "No matching activities")
                    .font(scaledFont(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Constants.spacingCard * zoomScale)
                    .padding(.vertical, Constants.spacingTight * zoomScale)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activities) { activity in
                            QuickStartRow(activity: activity, onTap: {
                                Task {
                                    await startSessionForType(activity: activity)
                                }
                            }, onEdit: {
                                dismiss()
                                if let id = activity.id {
                                    appState.navigate(to: .showActivity(id))
                                }
                            })
                        }
                    }
                }
                .frame(height: 200 * zoomScale)
            }

            // Quick-create activity (pinned below scroll area)
            HStack(spacing: 8 * zoomScale) {
                Image(systemName: "plus")
                    .font(scaledFont(.caption))
                    .foregroundStyle(.secondary)
                TextField("New activity...", text: $newActivityTitle)
                    .textFieldStyle(.plain)
                    .font(scaledFont(.body))
                    .onSubmit {
                        guard !newActivityTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task {
                            guard let newActivity = try? await appState.service.createActivity(
                                CreateActivityInput(title: newActivityTitle.trimmingCharacters(in: .whitespaces))
                            ) else { return }
                            newActivityTitle = ""
                            await startSessionForType(activity: newActivity)
                        }
                    }
            }
            .padding(.horizontal, Constants.spacingCard * zoomScale)
            .padding(.vertical, Constants.spacingCompact * zoomScale)
        }
        .onAppear {
            Task {
                timeboundMinutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
                activitySort = (try? await appState.service.getPreference(key: PreferenceKey.menuBarActivitySort)) ?? "recent"
            }
        }
        .syncRhythmSelection($selectedRhythmOption)
    }

    private func startSessionForType(activity: Activity) async {
        let activityId = activity.id!
        // System activities cannot use rhythm sessions — fall back to work
        let effectiveType = (activity.isSystem && selectedSessionType == .rhythm) ? .work : selectedSessionType

        switch effectiveType {
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
                type: effectiveType
            )
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

    private func setActivitySort(_ sort: String) {
        activitySort = sort
        Task {
            try? await appState.service.setPreference(key: PreferenceKey.menuBarActivitySort, value: sort)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
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
                HStack(spacing: 4) {
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

// MARK: - Clear Search Button

private struct ClearSearchButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(isHovered ? .primary : .secondary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
