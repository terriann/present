# Apple Human Interface Guidelines: macOS Reference

Quick-scan reference for macOS design reviews. Organized by HIG section with actionable rules.

---

## Foundations

### Core Design Principles

- **Clarity** — text is legible at every size, icons are precise and lucid, adornments are subtle and appropriate, focus on functionality drives the design
- **Deference** — fluid motion and a crisp interface help people understand and interact with content without competing with it
- **Depth** — visual layers and realistic motion convey hierarchy, impart vitality, and facilitate understanding

### Accessibility

- **VoiceOver**: every interactive control needs an accessibility label; decorative images use `.accessibilityHidden(true)`
- **Keyboard navigation**: all interactive elements must be reachable via Tab/Shift+Tab; custom views need `.focusable()` and keyboard event handling
- **Dynamic Type**: use system text styles (`.body`, `.headline`, etc.) or relative sizing; never hard-code font sizes that prevent scaling
- **Color contrast**: minimum 4.5:1 for body text, 3:1 for large text (18pt+ or 14pt+ bold); never convey information by color alone
- **Reduce Motion**: honor `accessibilityReduceMotion`; replace spring animations with crossfades or opacity changes
- **Reduce Transparency**: honor `accessibilityReduceTransparency`; replace materials/vibrancy with solid backgrounds
- **Button shapes**: when enabled, buttons should have visible borders or fills
- **Minimum tap/click targets**: 24x24pt minimum for macOS controls

### Color

| Concept | Guidance |
|---|---|
| Semantic colors | Use `.primary`, `.secondary`, `.label`, `.systemBackground` instead of raw values |
| System accent | Respect the user's system accent color; use `Color.accentColor` or app-defined tint |
| Dark mode | Always support both appearances; test in both; use semantic colors that adapt |
| High contrast | Provide assets in the High Contrast variant; avoid thin lines as sole differentiators |
| Vibrancy | Use `.regularMaterial`, `.thickMaterial` etc. rather than raw opacity |
| Specification | Never use hard-coded RGB values for UI chrome; reserve for brand/data visualization |

**Present-specific**: Use `theme.accent`, `theme.success`, `theme.warning`, `theme.alert`. No raw SwiftUI colors (`.red`, `.blue`, etc.) in views. `.secondary` is fine for muted text.

### Typography

- **System font**: SF Pro (automatically available; do not bundle)
- **Text styles**: `.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.subheadline`, `.body`, `.callout`, `.caption`, `.caption2`, `.footnote`
- **Hierarchy**: use weight and size to establish hierarchy (title > headline > body > caption)
- **Monospaced digits**: use `.monospacedDigit()` for timers, counters, tabular numbers to prevent layout shift
- **Minimum body size**: 13pt on macOS (system default)
- **Line length**: aim for 50-75 characters per line for readability
- **Truncation**: prefer truncation over wrapping for single-line labels; use `.lineLimit(1)` with `.truncationMode(.tail)`

### Layout & Spacing

| Element | Standard Value |
|---|---|
| Window content margins | 20pt |
| Section spacing | 20pt between major sections |
| Control spacing | 8pt between related controls |
| Label-to-control | 8pt |
| Button spacing | 12pt between buttons |
| List row height | 22-28pt (standard), 44pt (with subtitle) |
| Sidebar width | 200-240pt default, 150pt minimum |
| Minimum window size | Wide enough for content + sidebar if applicable |

- **Grid alignment**: align controls to a consistent leading edge; use SwiftUI's alignment guides
- **Baseline alignment**: align text baselines across columns, not top edges
- **Consistent insets**: use the same padding throughout a single view

### Icons & SF Symbols

- **Rendering modes**: monochrome (default), hierarchical (depth), palette (custom colors), multicolor (fixed)
- **Weight matching**: symbol weight should match adjacent text weight; use `.font()` to size symbols
- **Sizing**: symbols inherit font size; use `.imageScale(.small/.medium/.large)` for relative adjustments
- **When to use SF Symbols**: standard actions, navigation, status indicators; prefer over custom icons when a suitable symbol exists
- **Custom symbols**: follow SF Symbol template geometry; export as SVG with proper alignment
- **Alignment**: use `.symbolRenderingMode()` and `.foregroundStyle()` for consistent rendering

### Materials & Vibrancy

- **Sidebar material**: `.sidebar` modifier or NavigationSplitView (automatic)
- **Window materials**: `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`, `.ultraThickMaterial`
- **When to use**: behind overlaid content (popovers, sheets, sidebars), never as primary content background
- **Vibrancy**: labels and symbols over materials get vibrancy automatically; don't fight it with opaque backgrounds
- **Performance**: materials have GPU cost; avoid stacking multiple material layers

### Motion & Animation

- **Spring animations**: prefer `.spring()` or `.interactiveSpring()` for natural feeling; avoid linear easing
- **Duration**: keep under 0.3s for micro-interactions, up to 0.5s for view transitions
- **Purpose**: animation should communicate change, not decorate; every animation should answer "what just happened?"
- **Reduce Motion**: wrap animations in checks or use `.animation(.default, value:)` which respects system settings
- **Matched geometry**: use `.matchedGeometryEffect()` for smooth transitions between states
- **Implicit vs explicit**: prefer implicit animations (`.animation()` modifier) for simple state changes; explicit (`withAnimation`) for coordinated changes

---

## macOS Platform Conventions

### Windows

| Window Type | Use Case | Notes |
|---|---|---|
| Standard window | Primary app content | Resizable, titlebar, toolbar |
| Settings window | App preferences | Use `Settings` scene in SwiftUI; tabs for organization |
| Utility panel | Floating tools | `.utilityPanel` style; stays in front |
| Sheet | Modal subtask | Attached to parent window; blocks interaction |
| Alert | Critical decision | Short message + 2-3 buttons; use sparingly |
| Popover | Contextual info | Attached to control; dismiss on click outside |

- **Minimum window size**: set `minWidth`/`minHeight` appropriate to content; never let window shrink to unusable
- **Resizing behavior**: content should reflow or add scrolling; never clip or overlap
- **Window restoration**: preserve window size and position across launches
- **Full screen**: support where appropriate; test toolbar/sidebar behavior in full screen
- **Title bar**: can hide in content-focused apps; always show when window has toolbar

### The Menu Bar

- **Standard menus**: App menu (About, Preferences, Quit), File, Edit, View, Window, Help — follow expected order
- **Keyboard shortcuts**: Cmd+Q (quit), Cmd+, (preferences), Cmd+W (close window), Cmd+H (hide), Cmd+M (minimize) are system-standard; never override
- **Menu bar extras**: use `MenuBarExtra` in SwiftUI; keep icon 18x18pt, template image style
- **Menu bar popover**: for quick-access UI; keep compact; provide way to open main window
- **Contextual menus**: right-click on relevant items; follow system verb order (Cut, Copy, Paste, Delete)

### Toolbars

- **Unified title/toolbar**: default in modern macOS; title integrated into toolbar area
- **Items**: use toolbar items for frequent actions; overflow into "more" automatically
- **Customization**: allow users to customize toolbar (`.toolbar` with `.customizationBehavior()`)
- **Segmented controls**: use in toolbar for view switching (not tabs)
- **Search**: toolbar search field for filtering/searching content

### Sidebars

- **Width**: 200-240pt default; user-resizable; 150pt minimum
- **Content**: navigation links, source list items, filters
- **Selection**: single selection highlighted with accent color; keyboard navigable
- **Collapsible**: support hiding/showing sidebar; persist state
- **Sections**: group related items with section headers
- **Badges**: use for counts (unread, items); keep concise

### Navigation

- **NavigationSplitView**: sidebar + detail (two-column) or sidebar + content + detail (three-column)
- **TabView**: top-level sections; macOS tabs in toolbar area; 3-7 tabs recommended
- **Disclosure groups**: for hierarchical content in lists/sidebars
- **Back navigation**: toolbar back button in detail panes; Cmd+[ shortcut
- **Breadcrumbs**: not a macOS pattern; use sidebar selection or back navigation instead
- **Deep linking**: support opening to specific content via URL scheme or Spotlight

---

## Components

### Buttons

| Style | Use Case |
|---|---|
| `.borderedProminent` | Primary action (1 per context) |
| `.bordered` | Secondary actions |
| `.borderless` | Tertiary, inline, toolbar |
| `.destructive` role | Delete, remove, cancel irrecoverably |

- **Button order (macOS)**: default/primary button is rightmost (opposite of iOS); cancel is left of default
- **Escape key**: dismisses sheets/dialogs (mapped to cancel button)
- **Return/Enter**: activates default button (blue/prominent)
- **Labeling**: use verbs ("Save", "Delete", "Send"); avoid "OK" for destructive actions — name the action
- **Disabled state**: grey out; provide reason via tooltip or helper text

### Text Fields & Labels

- **Placeholder text**: brief hint of expected format; disappears on input — don't use as the only label
- **Labels**: always provide a visible label above or beside the field; `.labelsHidden()` only when context is unambiguous
- **Validation**: inline errors below the field in red/alert color; validate on field exit, not on every keystroke
- **Search fields**: use `.searchable()` modifier; magnifying glass icon is standard; support Cmd+F
- **Secure fields**: use `SecureField` for passwords; show/hide toggle is acceptable
- **Character limits**: show remaining count if limit exists; prevent over-entry

### Tables & Lists

- **List selection**: single click to select, double-click to open/edit; support Cmd+click for multi-select
- **Sorting**: click column headers to sort; arrow indicator shows direction; support multiple sort keys
- **Empty states**: use `ContentUnavailableView` with icon, title, and action; never show blank space
- **Row actions**: swipe actions (trailing delete), contextual menu on right-click
- **Alternating rows**: `.alternatingRowBackgrounds()` for dense data tables
- **Column resizing**: allow user to resize columns; persist widths

**Present-specific**: empty states must be top-aligned, never vertically centered.

### Menus

| Type | Trigger | Use Case |
|---|---|---|
| Contextual | Right-click / Ctrl+click | Actions on selected item |
| Pop-up | Click button | Choose from options |
| Pull-down | Click button | Actions list |
| Menu bar | Click menu title | App-wide commands |

- **Naming**: use verbs for actions ("Delete", "Duplicate"), nouns for options ("Large", "Small")
- **Separator items**: group related actions; use sparingly
- **Keyboard shortcuts**: assign to frequent menu items; display in menu
- **Disabled items**: show but grey out; don't hide (users need to know the action exists)
- **Checkmarks/mixed state**: for toggle options and partially applied states

### Alerts & Dialogs

- **Alerts**: short title (statement or question), optional informative text, 2-3 buttons
- **Destructive alerts**: name the destructive action ("Delete", not "OK"); use `.destructive` role
- **Button order**: destructive action rightmost (macOS convention); cancel to its left
- **Sheets vs alerts**: sheets for complex input or multi-step; alerts for simple yes/no decisions
- **Don't overuse**: alerts interrupt flow; prefer inline messaging or undo for non-critical issues
- **Suppression**: offer "Don't show again" for informational alerts (not for destructive confirmations)

### Pickers, Toggles, Sliders

- **Toggle**: for binary on/off settings; label clearly describes the "on" state
- **Picker**: for selecting from 3+ mutually exclusive options; use segmented style for 2-4 visible options, menu style for 5+
- **Slider**: for continuous value ranges; show min/max labels; consider adding text field for precise input
- **Stepper**: for discrete numeric values; show current value in adjacent text field
- **Date picker**: use system `.datePicker` styles; support keyboard entry and calendar popup

---

## Behavioral Patterns

### Notifications

- **Frequency**: don't spam; group related notifications; respect Do Not Disturb
- **Content**: title (app or context), subtitle (specific item), body (brief detail)
- **Actions**: 1-2 action buttons max; one can be destructive; default action on click opens relevant content
- **Sound**: use default notification sound or no sound; custom sounds must be short (< 5s)
- **Authorization**: request permission at a meaningful moment, not on first launch; explain value before requesting
- **Categories**: register `UNNotificationCategory` for actionable notifications
- **Grouping**: use thread identifiers to group related notifications

**Present-specific**: controlled by `soundEffectsEnabled` preference; sounds reserved for meaningful state transitions only.

### Settings/Preferences

- **Settings scene**: use SwiftUI `Settings` scene (Cmd+, shortcut automatic)
- **Tab organization**: group into logical tabs (General, Appearance, Notifications, etc.)
- **Immediate application**: changes apply instantly; no "Save" button; use `@AppStorage` or `UserDefaults`
- **Defaults**: ship with sensible defaults; user shouldn't need to configure before first use
- **Reset**: consider offering "Restore Defaults" per section
- **Labels**: describe what the setting does, not the technical mechanism

### Undo/Redo

- **Cmd+Z / Cmd+Shift+Z**: universal shortcuts; register with `UndoManager`
- **Edit menu**: always include Undo/Redo in Edit menu; show what will be undone ("Undo Delete")
- **Scope**: undo operates on the focused context (document, field, etc.)
- **Multi-level**: support multiple undo levels when practical
- **Destructive actions**: prefer undo over confirmation dialogs for non-critical deletions

### Drag and Drop

- **Visual feedback**: show drop target highlighting; change cursor; preview dragged content
- **Spring-loaded**: hovering over a container should open it (folders, tabs)
- **UTI types**: declare supported types; accept standard pasteboard types when applicable
- **Cancel**: Escape cancels drag; return item to origin with animation

### Right-to-Left Layout

- **Leading/trailing**: use `.leading`/`.trailing` instead of `.left`/`.right`
- **Bidirectional text**: use natural text alignment; system handles most cases
- **Icons**: directional icons (arrows, chevrons) should flip; non-directional (checkmark, search) should not
- **Testing**: enable RTL in scheme settings to verify layout

---

## Design Review Checklist

### Layout & Structure
- [ ] Content top-aligned (not vertically centered, unless explicitly intentional)
- [ ] Consistent margins and spacing throughout
- [ ] Window has appropriate minimum size
- [ ] Sidebar at standard width (200-240pt default)
- [ ] Empty states use `ContentUnavailableView`, top-aligned
- [ ] Leading/trailing used instead of left/right

### Typography
- [ ] System text styles used (not hard-coded sizes)
- [ ] Clear visual hierarchy (title > headline > body > caption)
- [ ] `.monospacedDigit()` for timers and numeric displays
- [ ] Labels are legible at default size
- [ ] Truncation preferred over wrapping for single-line labels

### Color & Theming
- [ ] No raw colors (`.red`, `.blue`) — using theme tokens
- [ ] Tested in both light and dark mode
- [ ] Sufficient contrast ratios (4.5:1 body, 3:1 large text)
- [ ] Information not conveyed by color alone
- [ ] Semantic colors used for standard UI chrome

### Interaction
- [ ] All interactive elements keyboard-accessible
- [ ] Buttons labeled with verbs, not "OK"
- [ ] Destructive actions use `.destructive` role
- [ ] Button order: cancel left, primary/default rightmost (macOS)
- [ ] Escape dismisses sheets/popovers
- [ ] Return/Enter activates primary action
- [ ] Right-click contextual menus where appropriate

### Accessibility
- [ ] VoiceOver labels on all interactive controls
- [ ] Decorative images hidden from accessibility
- [ ] Reduce Motion honored (no gratuitous animation)
- [ ] Reduce Transparency honored
- [ ] Minimum 24x24pt click targets

### Feedback & State
- [ ] Loading states shown for async operations
- [ ] Error states displayed inline, not just logged
- [ ] Success feedback provided (animation, sound, or message)
- [ ] Disabled controls have visible state + reason
- [ ] Undo available for non-critical destructive actions

### macOS Conventions
- [ ] Standard keyboard shortcuts not overridden (Cmd+Q, Cmd+W, Cmd+,)
- [ ] Settings in Settings scene (not a custom window)
- [ ] Menu bar follows standard menu order
- [ ] Window state restored on relaunch
- [ ] Contextual menus on right-click for actionable items

### Sound (Present-specific)
- [ ] Sounds only on meaningful state transitions
- [ ] Uses `SoundManager.shared.play(.effect)`, not direct audio
- [ ] Controlled by `soundEffectsEnabled` preference
- [ ] No sounds on: button clicks, tab switches, selection changes, hover
