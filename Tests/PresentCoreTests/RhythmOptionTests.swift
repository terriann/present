import Testing
import Foundation
@testable import PresentCore

@Suite("RhythmOption Tests")
struct RhythmOptionTests {

    // MARK: - displayLabel

    @Test func displayLabelStandardOption() {
        let option = RhythmOption(focusMinutes: 25, breakMinutes: 5)
        #expect(option.displayLabel == "25m / 5m")
    }

    @Test func displayLabelLongerDurations() {
        let option = RhythmOption(focusMinutes: 50, breakMinutes: 10)
        #expect(option.displayLabel == "50m / 10m")
    }

    @Test func displayLabelEdgeSingleMinute() {
        let option = RhythmOption(focusMinutes: 1, breakMinutes: 1)
        #expect(option.displayLabel == "1m / 1m")
    }

    @Test func displayLabelBoundaryMaxValues() {
        let option = RhythmOption(
            focusMinutes: Constants.rhythmDurationRange.upperBound,
            breakMinutes: Constants.breakDurationRange.upperBound
        )
        #expect(option.displayLabel == "120m / 60m")
    }

    @Test func displayLabelBoundaryMinValues() {
        let option = RhythmOption(
            focusMinutes: Constants.rhythmDurationRange.lowerBound,
            breakMinutes: Constants.breakDurationRange.lowerBound
        )
        #expect(option.displayLabel == "1m / 1m")
    }

    // MARK: - settingsLabel

    @Test func settingsLabelStandardOption() {
        let option = RhythmOption(focusMinutes: 25, breakMinutes: 5)
        #expect(option.settingsLabel == "25 minute focus / 5 minute break")
    }

    @Test func settingsLabelLongerDurations() {
        let option = RhythmOption(focusMinutes: 50, breakMinutes: 10)
        #expect(option.settingsLabel == "50 minute focus / 10 minute break")
    }

    @Test func settingsLabelEdgeSingleMinute() {
        let option = RhythmOption(focusMinutes: 1, breakMinutes: 1)
        #expect(option.settingsLabel == "1 minute focus / 1 minute break")
    }

    @Test func settingsLabelBoundaryMaxValues() {
        let option = RhythmOption(
            focusMinutes: Constants.rhythmDurationRange.upperBound,
            breakMinutes: Constants.breakDurationRange.upperBound
        )
        #expect(option.settingsLabel == "120 minute focus / 60 minute break")
    }

    @Test func settingsLabelBoundaryMinValues() {
        let option = RhythmOption(
            focusMinutes: Constants.rhythmDurationRange.lowerBound,
            breakMinutes: Constants.breakDurationRange.lowerBound
        )
        #expect(option.settingsLabel == "1 minute focus / 1 minute break")
    }
}
