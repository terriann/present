import SwiftUI
import PresentCore

@main
struct PresentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        let _ = startStatusItemMenu()
        let _ = loadPalette()

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(themeManager)
                .tint(themeManager.accent)
        } label: {
            MenuBarLabelView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Present", id: "main") {
            ContentView()
                .environment(appState)
                .environment(themeManager)
                .tint(themeManager.accent)
                .onAppear {
                    appDelegate.appState = appState
                    appState.showDockIcon(true)
                }
                .onDisappear { appState.showDockIcon(false) }
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(themeManager)
                .tint(themeManager.accent)
        }
    }

    private func loadPalette() {
        Task {
            if let value = try? await appState.service.getPreference(key: PreferenceKey.colorPalette),
               let palette = ColorPalette(rawValue: value) {
                themeManager.activePalette = palette
            }
        }
    }

    private func startStatusItemMenu() {
        guard appDelegate.statusItemMenuManager == nil else { return }
        let manager = StatusItemMenuManager(appState: appState)
        appDelegate.statusItemMenuManager = manager
        manager.start()
    }
}

/// Menu bar icon + timer label. Always visible, so it can observe notifications
/// from `StatusItemMenuManager` and bridge them to SwiftUI environment actions.
private struct MenuBarLabelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var flashVisible: Bool = true
    @State private var flashTask: Task<Void, Never>?
    @State private var fadeOpacity: Double = Constants.menuBarTimerLingerOpacity

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.menuBarIcon)
            if let timerText = appState.menuBarTimerText {
                Text(timerText)
                    .monospacedDigit()
                    .opacity(timerTextOpacity)
            }
        }
        .onChange(of: appState.isCountdownCompletion) { _, isCountdown in
            if isCountdown {
                startFlashAnimation()
            } else {
                stopFlashAnimation()
            }
        }
        .onChange(of: appState.isCompletedTimerFading) { _, isFading in
            if isFading {
                withAnimation(.easeOut(duration: Double(Constants.completedTimerFadeSeconds))) {
                    fadeOpacity = 0.0
                }
            } else {
                fadeOpacity = Constants.menuBarTimerLingerOpacity
            }
        }
        .onChange(of: appState.completedTimerText) { _, newValue in
            if newValue == nil {
                // Linger cleared — reset animation state
                stopFlashAnimation()
                fadeOpacity = Constants.menuBarTimerLingerOpacity
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StatusItemMenuManager.openMainWindowNotification)) { _ in
            openWindow(id: "main")
            DispatchQueue.main.async {
                NSApplication.shared.activate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StatusItemMenuManager.openSettingsNotification)) { _ in
            openSettings()
            DispatchQueue.main.async {
                NSApplication.shared.activate()
            }
        }
    }

    // MARK: - Timer Opacity

    private var timerTextOpacity: Double {
        if appState.isCompletedTimerFading {
            return fadeOpacity
        }
        if appState.completedTimerText != nil {
            return flashVisible ? Constants.menuBarTimerLingerOpacity : 0.0
        }
        if appState.currentSession?.state == .paused {
            return Constants.menuBarTimerPausedOpacity
        }
        return 1.0
    }

    // MARK: - Flash Animation

    private func startFlashAnimation() {
        flashVisible = true
        flashTask?.cancel()
        flashTask = Task {
            let interval: Duration = .milliseconds(500)
            let totalFlashes = Constants.completedTimerFlashSeconds * 2 // 2 toggles per second
            for _ in 0..<totalFlashes {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                flashVisible.toggle()
            }
            // After flashing, hold visible
            flashVisible = true
        }
    }

    private func stopFlashAnimation() {
        flashTask?.cancel()
        flashTask = nil
        flashVisible = true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var statusItemMenuManager: StatusItemMenuManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.isSessionActive else {
            return .terminateNow
        }

        Task { @MainActor in
            await appState.stopSession()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
