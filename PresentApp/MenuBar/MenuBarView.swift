import SwiftUI
import PresentCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedSessionType: SessionType = .work
    @State private var selectedRhythmOption: RhythmOption?
    @State private var timeboundMinutes: Int = 25
    @State private var newActivityTitle = ""

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

                Divider()

                bottomBar
            }
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
                                Text("\(option.focusMinutes) m / \(option.breakMinutes) m")
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

            // Search
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
            }
            .padding(.horizontal, Constants.spacingCard * zoomScale)
            .padding(.vertical, Constants.spacingCompact * zoomScale)

            // Activity list heading
            Text(searchText.isEmpty ? "Recent Activities" : "Search Results")
                .font(scaledFont(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Constants.spacingCard * zoomScale)
                .padding(.top, Constants.spacingTight * zoomScale)

            // Activity list
            let activities = filteredActivities
            if activities.isEmpty && !searchText.isEmpty {
                Text("No matching activities")
                    .font(scaledFont(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Constants.spacingCard * zoomScale)
                    .padding(.vertical, Constants.spacingTight * zoomScale)
            } else {
                ForEach(activities) { activity in
                    QuickStartRow(activity: activity, onTap: {
                        Task {
                            await startSessionForType(activity: activity)
                        }
                    }, onEdit: {
                        dismiss()
                        appState.navigateToActivityId = activity.id
                        appState.selectedSidebarItem = .activities
                        NSApplication.shared.setActivationPolicy(.regular)
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: StatusItemMenuManager.openMainWindowNotification,
                                object: nil
                            )
                        }
                    })
                }
            }

            // Quick-create activity
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
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
            Task {
                timeboundMinutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            }
        }
        .onChange(of: appState.rhythmDurationOptions) {
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
        }
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
        let source = searchText.isEmpty ? appState.recentActivities : appState.allActivities
        if searchText.isEmpty {
            return source
        }
        return source.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Spacer()

            Button {
                dismiss()
                NSApplication.shared.setActivationPolicy(.regular)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: StatusItemMenuManager.openMainWindowNotification,
                        object: nil
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: StatusItemMenuManager.openSettingsNotification,
                        object: nil
                    )
                }
            } label: {
                Image(systemName: "gear")
                    .font(scaledFont(.body))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, Constants.spacingCard * zoomScale)
        .padding(.vertical, Constants.spacingCompact * zoomScale)
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
