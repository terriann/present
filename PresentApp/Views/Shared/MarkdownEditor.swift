import SwiftUI
import AppKit

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var focusOnAppear: Bool = false
    var onCommit: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        // Build scroll view + text view from scratch so we can use our CommittableTextView subclass.
        // NSTextView.scrollablePlainDocumentContentTextView() creates a standard NSTextView that
        // can't be swapped out, so we replicate its setup here.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = CommittableTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticLinkDetectionEnabled = false
        let coordinator = context.coordinator
        textView.onResignFirstResponder = { [weak coordinator] in
            coordinator?.onCommit?()
        }

        textView.string = text
        scrollView.documentView = textView
        context.coordinator.applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onCommit = onCommit
        context.coordinator.onEscape = onEscape
        if let committable = textView as? CommittableTextView {
            let coordinator = context.coordinator
            committable.onResignFirstResponder = { [weak coordinator] in
                coordinator?.onCommit?()
            }
        }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyHighlighting(to: textView)
        }
        textView.isEditable = isEditable

        if focusOnAppear && !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onEscape: onEscape)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCommit: (() -> Void)?
        var onEscape: (() -> Void)?
        var didFocus = false

        init(text: Binding<String>, onCommit: (() -> Void)?, onEscape: (() -> Void)?) {
            self.text = text
            self.onCommit = onCommit
            self.onEscape = onEscape
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            applyHighlighting(to: textView)
        }

        // MARK: - List Auto-Continuation

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if let onEscape {
                    onEscape()
                    return true
                }
                return false
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            return handleListContinuation(in: textView)
        }

        @MainActor private func handleListContinuation(in textView: NSTextView) -> Bool {
            let content = textView.string as NSString
            let cursorLocation = textView.selectedRange().location

            // Find the current line
            let lineRange = content.lineRange(for: NSRange(location: cursorLocation, length: 0))
            let currentLine = content.substring(with: lineRange)

            // Try to match a list prefix
            guard let match = matchListPrefix(currentLine) else {
                return false
            }

            let lineContent = match.contentAfterPrefix

            // If the line content after the prefix is empty, remove the prefix and add blank line
            if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                let deleteRange = NSRange(location: lineRange.location, length: lineRange.length)
                // Replace the empty list item with a blank line
                textView.insertText("\n", replacementRange: deleteRange)
                return true
            }

            // Insert newline + the next list prefix
            let nextPrefix = match.nextPrefix
            textView.insertText("\n\(nextPrefix)", replacementRange: textView.selectedRange())
            return true
        }

        private struct ListMatch {
            let contentAfterPrefix: String
            let nextPrefix: String
        }

        private func matchListPrefix(_ line: String) -> ListMatch? {
            // Checkbox: "- [ ] " or "- [x] " or "- [X] "
            if let range = line.range(of: #"^(\s*)- \[[ xX]\] "#, options: .regularExpression) {
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                let content = String(line[range.upperBound...])
                return ListMatch(contentAfterPrefix: content, nextPrefix: "\(indent)- [ ] ")
            }

            // Unordered list: "- " or "* "
            if let range = line.range(of: #"^(\s*)[-*] "#, options: .regularExpression) {
                let marker = line.contains("- ") ? "- " : "* "
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                let content = String(line[range.upperBound...])
                return ListMatch(contentAfterPrefix: content, nextPrefix: "\(indent)\(marker)")
            }

            // Ordered list: "1. ", "2. ", etc.
            if let range = line.range(of: #"^(\s*)(\d+)\. "#, options: .regularExpression) {
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                // Extract the number and increment
                let numberStr = String(line[line.index(line.startIndex, offsetBy: indent.count)...])
                    .prefix(while: { $0.isNumber })
                let number = Int(numberStr) ?? 0
                let content = String(line[range.upperBound...])
                return ListMatch(contentAfterPrefix: content, nextPrefix: "\(indent)\(number + 1). ")
            }

            return nil
        }

        // MARK: - Syntax Highlighting

        @MainActor func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let content = textStorage.string

            // Reset to base style
            let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            textStorage.beginEditing()
            textStorage.addAttribute(.font, value: baseFont, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            textStorage.removeAttribute(.strikethroughStyle, range: fullRange)

            let lines = content as NSString

            // Heading patterns
            applyPattern(#"^#{1,3}\s+.*$"#, to: textStorage, in: lines,
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .bold),
                            .foregroundColor: NSColor.labelColor
                        ])

            // Bold **text** or __text__
            applyPattern(#"(\*\*|__)(.*?)\1"#, to: textStorage, in: lines,
                        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)])

            // Italic *text* or _text_ (not preceded by * or _)
            applyPattern(#"(?<![*_])([*_])(?![*_])(.*?)\1(?![*_])"#, to: textStorage, in: lines,
                        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular).withTraits(.italicFontMask)])

            // Inline code `text`
            applyPattern(#"`[^`]+`"#, to: textStorage, in: lines,
                        attributes: [
                            .foregroundColor: NSColor.systemPink,
                            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                        ])

            // Fenced code blocks ```
            applyPattern(#"```[\s\S]*?```"#, to: textStorage, in: lines,
                        attributes: [
                            .foregroundColor: NSColor.systemGreen,
                            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                        ])

            // Links [text](url) — apply .link attribute for clickable links
            textStorage.removeAttribute(.link, range: fullRange)
            applyLinkAttributes(to: textStorage, in: lines)

            // Checklist items - [ ] and - [x]
            applyPattern(#"^- \[[ xX]\]"#, to: textStorage, in: lines,
                        attributes: [.foregroundColor: NSColor.systemBlue])

            // Checked items: strikethrough + muted color for the entire line
            applyPattern(#"^- \[[xX]\].*$"#, to: textStorage, in: lines,
                        attributes: [
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: NSColor.secondaryLabelColor
                        ])

            // List markers (- or * or numbers)
            applyPattern(#"^[\t ]*[-*]\s"#, to: textStorage, in: lines,
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            applyPattern(#"^[\t ]*\d+\.\s"#, to: textStorage, in: lines,
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor])

            textStorage.endEditing()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            NSWorkspace.shared.open(url)
            return true
        }

        private func applyLinkAttributes(to textStorage: NSTextStorage, in string: NSString) {
            let pattern = #"\[([^\]]+)\]\(([^\)]+)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let fullRange = NSRange(location: 0, length: string.length)
            regex.enumerateMatches(in: string as String, range: fullRange) { match, _, _ in
                guard let matchRange = match?.range,
                      let urlRange = match?.range(at: 2) else { return }
                let urlString = string.substring(with: urlRange)
                if let url = URL(string: urlString) {
                    textStorage.addAttribute(.link, value: url, range: matchRange)
                }
            }
        }

        private func applyPattern(_ pattern: String, to textStorage: NSTextStorage, in string: NSString,
                                  attributes: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let fullRange = NSRange(location: 0, length: string.length)
            regex.enumerateMatches(in: string as String, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    textStorage.addAttributes(attributes, range: range)
                }
            }
        }
    }
}

// MARK: - CommittableTextView

/// NSTextView subclass that fires a callback when it loses first responder (blur).
///
/// In macOS, clicking on non-interactive SwiftUI areas (backgrounds, labels) doesn't cause
/// the current first responder to resign. This subclass installs a click-outside monitor
/// when it becomes first responder, forcing a resign when the user clicks outside the
/// editor's scroll area.
private final class CommittableTextView: NSTextView {
    var onResignFirstResponder: (() -> Void)?
    private var clickMonitor: Any?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { installClickOutsideMonitor() }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            removeClickOutsideMonitor()
            onResignFirstResponder?()
        }
        return resigned
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            // Use the enclosing scroll view bounds so clicks on scrollbar or empty
            // space below text don't count as "outside" the editor area.
            let container = self.enclosingScrollView ?? self
            let point = container.convert(event.locationInWindow, from: nil)
            if !container.bounds.contains(point) {
                self.window?.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            removeClickOutsideMonitor()
        }
    }
}

private extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: UInt32(traits.rawValue)))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
