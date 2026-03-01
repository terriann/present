import SwiftUI

/// Maps a string to a consistent palette color using the djb2 hash algorithm.
///
/// Unlike Swift's built-in `hashValue` (randomized per process, SE-0206),
/// djb2 produces the same result across launches, so an activity title
/// always maps to the same palette slot.
func stableColor(for title: String, palette: [Color]) -> Color {
    guard !palette.isEmpty else { return .gray }
    let hash = djb2Hash(title)
    return palette[hash % palette.count]
}

/// Classic djb2 string hash — deterministic across process launches.
private func djb2Hash(_ string: String) -> Int {
    var hash: UInt64 = 5381
    for byte in string.utf8 {
        hash = hash &* 33 &+ UInt64(byte)
    }
    return Int(hash % UInt64(Int.max))
}
