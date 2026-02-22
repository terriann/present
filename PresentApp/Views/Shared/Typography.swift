import SwiftUI

extension Font {
    // MARK: - Display

    /// Large greeting displayed on the Dashboard header (~2x largeTitle, rounded design).
    /// Intentional fixed size — scaled visually by ZoomContainer.
    static let dashboardGreeting = Font.system(size: 52, weight: .bold)

    /// Period/date label shared between the Dashboard header and the Reports toolbar.
    static let periodHeader = Font.headline

    /// Main timer readout in Dashboard active-timer panel and MenuBar.
    static let timerDisplay = Font.largeTitle.weight(.light).monospacedDigit()

    /// Section card headings ("Today", chart card titles).
    static let cardTitle = Font.largeTitle.bold()

    // MARK: - Values & Rows

    /// Stat item numbers and activity title headings.
    static let statValue = Font.title.bold()

    /// Duration display in session rows and breakdown lists.
    static let durationValue = Font.title3.monospacedDigit()

    /// Duration in detail/sub-rows (expanded breakdown, activity detail).
    static let durationDetail = Font.body.monospacedDigit()

    // MARK: - Data & Charts

    /// Tooltip headers, donut center titles — bold caption.
    static let dataLabel = Font.caption.bold()

    /// Tooltip numeric values, donut values — monospaced caption.
    static let dataValue = Font.caption.monospacedDigit()

    /// Tooltip totals — bold + monospaced caption.
    static let dataBoldValue = Font.caption.bold().monospacedDigit()

    // MARK: - Icons

    /// Session control buttons (play/pause/stop).
    static let controlIcon = Font.title

    /// Secondary controls (discard), stat icons.
    static let controlIconSmall = Font.title2

    // MARK: - Code

    /// CLI command text in promo cards.
    static let codeBlock = Font.system(.body, design: .monospaced)

    /// CLI output text in promo cards.
    static let codeCaption = Font.system(.caption, design: .monospaced)
}
