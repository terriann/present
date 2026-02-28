import Foundation

/// Centralized navigation actions for the app.
///
/// Views and managers call `appState.navigate(to:)` instead of posting
/// notifications or manually setting activation policy. The action is
/// consumed by `onChange` observers in `MenuBarLabelView` (window opening)
/// and `SettingsView` (tab selection).
enum NavigationAction: Equatable {
    /// Bring the main window to the foreground.
    case launchMainWindow

    /// Navigate to the dashboard tab and bring the main window forward.
    case showDashboard

    /// Navigate to a specific activity in the activities tab and bring the main window forward.
    case showActivity(Int64)

    /// Open the settings window, optionally selecting a specific tab.
    case showSettings(SettingsTab?)
}
