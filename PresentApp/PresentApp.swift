import AppKit
import SwiftUI
import PresentCore

// MARK: - Window Activation

extension NSApplication {
    /// Brings the app to the foreground, above all other windows.
    ///
    /// Uses `NSRunningApplication.current.activate()` to ensure the app
    /// comes forward even when another application currently has focus.
    /// Call this **before** opening a window (e.g., `openWindow(id:)`)
    /// so the window appears in front.
    @MainActor static func bringToFront() {
        NSRunningApplication.current.activate()
    }
}

@main
struct PresentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        let _ = startStatusItemMenu()
        let _ = loadThemeSettings()
        let _ = configureAppDelegate()

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(themeManager)
                .tint(themeManager.accent)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .modifier(ErrorAlertModifier(appState: appState, scene: .menuBar))
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
                .preferredColorScheme(themeManager.preferredColorScheme)
                .modifier(ErrorAlertModifier(appState: appState, scene: .mainWindow))
                .onAppear {
                    appState.showDockIcon(true)
                }
                .onChange(of: appState.timerCompletionContext) { _, newValue in
                    if let ctx = newValue {
                        appDelegate.floatingAlertManager?.showAlert(context: ctx)
                    } else {
                        appDelegate.floatingAlertManager?.dismissAlert()
                    }
                }
                .onChange(of: themeManager.appearanceMode) {
                    themeManager.applyAppearance()
                    appDelegate.floatingAlertManager?.updatePanelAppearance()
                }
                .onDisappear { appState.showDockIcon(false) }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Zoom In") { appState.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!appState.canZoomIn)
                Button("Zoom Out") { appState.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!appState.canZoomOut)
                Button("Actual Size") { appState.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(appState.isDefaultZoom)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(themeManager)
                .tint(themeManager.accent)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .modifier(ErrorAlertModifier(appState: appState, scene: .settings))
        }
    }

    private func configureAppDelegate() {
        guard appDelegate.appState == nil else { return }
        appDelegate.appState = appState
        appDelegate.floatingAlertManager = FloatingAlertPanelManager(
            appState: appState, themeManager: themeManager
        )
    }

    private func loadThemeSettings() {
        Task {
            if let value = try? await appState.service.getPreference(key: PreferenceKey.colorPalette),
               let palette = ColorPalette(rawValue: value) {
                themeManager.activePalette = palette
            }
            if let value = try? await appState.service.getPreference(key: PreferenceKey.appearanceMode),
               let mode = AppearanceMode(rawValue: value) {
                themeManager.appearanceMode = mode
            }
            themeManager.applyAppearance()
        }
    }

    private func startStatusItemMenu() {
        guard appDelegate.statusItemMenuManager == nil else { return }
        let manager = StatusItemMenuManager(appState: appState)
        appDelegate.statusItemMenuManager = manager
        manager.start()
    }
}

// MARK: - Error Alert Modifier

private struct ErrorAlertModifier: ViewModifier {
    @Bindable var appState: AppState
    let scene: ErrorScene

    func body(content: Content) -> some View {
        content.alert(
            appState.presentedError?.title ?? "Error",
            isPresented: Binding(
                get: { appState.presentedError?.scene == scene },
                set: { if !$0 { appState.presentedError = nil } }
            )
        ) {
            Button("OK") { }
        } message: {
            Text(appState.presentedError?.message ?? "")
        }
    }
}

/// Menu bar icon + timer label. Always visible, so it can observe
/// `pendingNavigation` changes on `AppState` and bridge them to SwiftUI
/// environment actions (`openWindow`, `openSettings`).
private struct MenuBarLabelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.menuBarIcon)
            if let timerText = appState.menuBarTimerText {
                Text(timerText)
                    .monospacedDigit()
            }
        }
        .task {
            // On a normal launch, open the main window. On a login‐item
            // launch the app starts silently in the menu bar.
            if let delegate = NSApp.delegate as? AppDelegate,
               !delegate.launchedAsLoginItem {
                appState.pendingNavigation = .launchMainWindow
            }
        }
        .onChange(of: appState.pendingNavigation) { _, action in
            guard let action else { return }
            appState.pendingNavigation = nil

            switch action {
            case .launchMainWindow, .showDashboard, .showActivity:
                appState.showDockIcon(true)
                NSApplication.bringToFront()
                openWindow(id: "main")

            case .showSettings:
                appState.showDockIcon(true)
                NSApplication.bringToFront()
                openWindow(id: "main")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    openSettings()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var statusItemMenuManager: StatusItemMenuManager?
    var floatingAlertManager: FloatingAlertPanelManager?
    private(set) var launchedAsLoginItem = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Detect whether the system launched us as a login item.
        // 'logi' (0x6C6F6769) is keyAELaunchedAsLogInItem from AEDataModel.h.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication {
            launchedAsLoginItem = event.paramDescriptor(
                forKeyword: AEKeyword(0x6C6F_6769)
            )?.booleanValue ?? false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            appState?.navigate(to: .launchMainWindow)
        }
        return true
    }

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
