import SwiftUI
import PresentCore

struct ReportCLIPromoCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentCommandIndex = 0

    private static let cliCommands: [(command: String, output: String)] = [
        ("$ present-cli session start \"Deep Work\"", "\u{2713} Session started (Focus: 25m)"),
        ("$ present-cli report export --period weekly", "\u{2713} Exported to weekly-report.csv"),
        ("$ present-cli activity list", "  Reading \u{00B7} Writing \u{00B7} Deep Work"),
        ("$ present-cli session stop", "\u{2713} Session saved \u{2014} 1h 23m"),
    ]

    var body: some View {
        let pair = Self.cliCommands[currentCommandIndex]

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                        Text("Power up with ")
                            .foregroundStyle(.primary)
                        + Text("present-cli")
                            .font(.codeBlock)
                            .foregroundStyle(.primary)
                    }
                    .font(.headline)

                    Text("Export reports, manage sessions, and automate your workflow from the terminal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pair.command)
                            .font(.codeCaption)
                            .foregroundStyle(theme.success)
                        Text(pair.output)
                            .font(.codeCaption)
                            .foregroundStyle(theme.success.opacity(0.7))
                    }
                    .id(currentCommandIndex)
                    .contentTransition(.opacity)
                    .adaptiveAnimation(.easeInOut(duration: 0.4), reduced: .linear(duration: 0.25), value: currentCommandIndex)
                    .padding(Constants.spacingCard)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.constantBlack.opacity(0.85))
                    )

                    Button {
                        appState.navigate(to: .showSettings(.cli))
                    } label: {
                        Text("Install CLI")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                }
            }
            .padding(Constants.spacingTight)
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion else { return }
            currentCommandIndex = (currentCommandIndex + 1) % Self.cliCommands.count
        }
    }
}
