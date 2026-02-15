import AppKit
import PresentCore

/// Adds a right-click context menu to the menu bar status item.
///
/// SwiftUI's `MenuBarExtra` doesn't natively support right-click menus, so this
/// class monitors for right-click events on the status bar window and displays
/// an `NSMenu` with session controls and app actions.
///
/// Window/settings opening uses `NotificationCenter` and `NSApp.sendAction` to
/// avoid fragile closure wiring between AppKit and SwiftUI contexts.
///
/// All methods run on the main thread (event monitors, NSMenuItem actions).
/// The class is nonisolated with `nonisolated(unsafe)` references, using
/// `MainActor.assumeIsolated` where actor-isolated access is needed.
final class StatusItemMenuManager: NSObject, @unchecked Sendable {
    /// Posted when the user selects "Open Present" from the right-click menu.
    /// Observed by `MenuBarLabelView` which has access to SwiftUI's `openWindow`.
    static let openMainWindowNotification = Notification.Name("Present.openMainWindow")

    /// Posted when the user selects "Settings…" from the right-click menu.
    /// Observed by `MenuBarLabelView` which has access to SwiftUI's `openSettings`.
    static let openSettingsNotification = Notification.Name("Present.openSettings")

    // Safe: only accessed from main thread (event monitors and NSMenuItem actions)
    nonisolated(unsafe) private weak var appState: AppState?
    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func start() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }

            guard let window = event.window else { return event }
            let className = String(describing: type(of: window))
            guard className.contains("NSStatusBar") else { return event }

            MainActor.assumeIsolated {
                self.showMenu(in: window)
            }
            return nil
        }
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Menu Building

    private func showMenu(in window: NSWindow) {
        let menu = buildMenu()
        guard let view = window.contentView else { return }
        // Position first item at the bottom edge of the status bar button.
        // If the view is flipped (origin top-left), bottom edge is at bounds.height.
        let y: CGFloat = view.isFlipped ? view.bounds.height : 0
        menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: y), in: view)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let isActive = MainActor.assumeIsolated { appState?.isSessionActive ?? false }
        let isRunning = MainActor.assumeIsolated { appState?.isSessionRunning ?? false }
        let activityTitle = MainActor.assumeIsolated { appState?.currentActivity?.title }

        if isActive {
            addSessionItems(to: menu, isRunning: isRunning, activityTitle: activityTitle)
            menu.addItem(.separator())
        } else {
            let suggestion = MainActor.assumeIsolated { appState?.recentSessionSuggestion }
            if let suggestion {
                addRecentSuggestionItem(to: menu, session: suggestion.session, activity: suggestion.activity)
                menu.addItem(.separator())
            }
        }

        let openItem = NSMenuItem(title: "Open Present", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Present", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addSessionItems(to menu: NSMenu, isRunning: Bool, activityTitle: String?) {
        let suffix = activityTitle.map { " \u{2014} \($0)" } ?? ""

        if isRunning {
            let pauseItem = NSMenuItem(title: "Pause\(suffix)", action: #selector(pauseSession), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)
        } else {
            let resumeItem = NSMenuItem(title: "Resume\(suffix)", action: #selector(resumeSession), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        }

        let stopItem = NSMenuItem(title: "Stop\(suffix)", action: #selector(stopSession), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
    }

    private func addRecentSuggestionItem(to menu: NSMenu, session: Session, activity: Activity) {
        let item = NSMenuItem(
            title: "Start \(activity.title)",
            action: #selector(restartRecentSession),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func pauseSession() {
        Task { @MainActor in
            await appState?.pauseSession()
        }
    }

    @objc private func resumeSession() {
        Task { @MainActor in
            await appState?.resumeSession()
        }
    }

    @objc private func stopSession() {
        Task { @MainActor in
            await appState?.stopSession()
        }
    }

    @objc private func restartRecentSession() {
        Task { @MainActor in
            guard let suggestion = appState?.recentSessionSuggestion,
                  let activityId = suggestion.activity.id else { return }
            await appState?.startSession(
                activityId: activityId,
                type: suggestion.session.sessionType,
                timerMinutes: suggestion.session.timerLengthMinutes
            )
        }
    }

    @objc private func openApp() {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        // Defer to next run loop so activation policy takes effect before SwiftUI opens the window.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.openMainWindowNotification, object: nil)
        }
    }

    @objc private func openSettings() {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        // Open main window first (settings needs an active window), then settings after a delay.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.openMainWindowNotification, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
        }
    }

    @objc private func quitApp() {
        MainActor.assumeIsolated {
            NSApplication.shared.terminate(nil)
        }
    }
}
