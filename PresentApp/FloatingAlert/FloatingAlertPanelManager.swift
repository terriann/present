import AppKit
import SwiftUI
import PresentCore

@MainActor
final class FloatingAlertPanelManager {
    private var panel: NSPanel?
    private let appState: AppState
    private let themeManager: ThemeManager

    init(appState: AppState, themeManager: ThemeManager) {
        self.appState = appState
        self.themeManager = themeManager
    }

    func showAlert(context: TimerCompletionContext) {
        dismissAlert()

        let contentView = FloatingAlertView(context: context)
            .environment(appState)
            .environment(themeManager)
            .tint(themeManager.accent)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panelWidth = max(hostingView.fittingSize.width, 320)
        let panelHeight = hostingView.fittingSize.height

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isOpaque = false

        newPanel.contentView = hostingView

        // Center on the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.midY - panelHeight / 2
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        newPanel.orderFrontRegardless()
        panel = newPanel
    }

    func dismissAlert() {
        guard let panel else { return }
        // Hide immediately but defer close to the next run loop iteration.
        // Calling close() synchronously can destroy the NSHostingView while
        // SwiftUI is still processing a button action inside the panel,
        // which corrupts the view update cycle and crashes.
        panel.orderOut(nil)
        let panelToClose = panel
        self.panel = nil
        DispatchQueue.main.async {
            panelToClose.close()
        }
    }
}
