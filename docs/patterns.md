# UI Pattern Catalog

A living reference of Present's recurring UI patterns. Each entry names
the pattern, explains when to reach for it, describes its structure, and
points to a canonical implementation in the codebase.

**How to use this catalog:**

1. Before building a new view, scan the categories below for a pattern
   that fits the need.
2. Open the **canonical example** file and study its implementation.
   Line ranges are approximate and may drift as the codebase evolves;
   use them as a starting point, not a guarantee.
3. Follow the structure described here. When a pattern evolves, update
   the canonical reference so future work stays consistent.

> [!TIP]
> AI systems parsing this document can treat each pattern as a
> self-contained reference. Every entry includes the pattern name,
> selection criteria, structural specification, and file path(s) needed
> to generate conforming code.

## Table of Contents

- [Cards and Containers](#cards-and-containers)
  - [Chart Card](#chart-card)
  - [Empty State](#empty-state)
- [Data Display](#data-display)
  - [Stat Item](#stat-item)
- [Charts](#charts)
  - [Stacked Bar Chart (Vertical)](#stacked-bar-chart-vertical)
  - [Donut Chart](#donut-chart)
  - [Horizontal Bar Chart](#horizontal-bar-chart)
  - [Day Timeline](#day-timeline)
- [Chart Support Components](#chart-support-components)
  - [Chart Tooltip](#chart-tooltip)
  - [Hoverable Chart Legend](#hoverable-chart-legend)
- [Lists and Rows](#lists-and-rows)
  - [Activity Row](#activity-row)
  - [Expandable Group Header](#expandable-group-header)
  - [Session Row (Grouped)](#session-row-grouped)
- [Editing and Input](#editing-and-input)
  - [Inline Editable Text](#inline-editable-text)
  - [Tag Pill Input](#tag-pill-input)
  - [Session Inline Edit Form](#session-inline-edit-form)
- [Controls](#controls)
  - [Themed Toggle](#themed-toggle)
  - [Hover Highlight](#hover-highlight)
- [Settings](#settings)
  - [Settings Form Section](#settings-form-section)
- [Background Tints Reference](#background-tints-reference)

---

## Cards and Containers

### Chart Card

A titled card that wraps chart content with an optional subtitle and
trailing controls.

**When to use:** Any chart, data visualization, or grouped content block
that needs a heading.

**Structure:**

- `GroupBox` wrapper
- Header: `HStack(alignment: .top)` with title (`.font(.cardTitle)`) +
  optional subtitle (`.font(.periodHeader)`, `.secondary`) + optional
  trailing controls
- Content provided via `@ViewBuilder`
- Internal padding: `Constants.spacingCard` (12pt)

**Canonical example:**
`PresentApp/Views/Shared/ChartCard.swift:4-45`

**Usage:**
`DashboardWeeklyChartCard`, `ReportStackedBarChart`,
`ReportActivityPieChart`, `ReportTagBarChart`,
`ReportExternalIdChart`, `ReportDayTimelineCard`

---

### Empty State

Top-aligned placeholder shown when a view has no data.

**When to use:** Any list, card, or content area that can be empty.

**Structure:**

- `ContentUnavailableView(title, systemImage:, description: Text(...))`
- Styled with `.emptyStateStyle()` modifier
- The modifier applies
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)`
  and `.padding(.vertical, 40)`
- Often wrapped in a `GroupBox` when inside a card context

**Canonical example:**
`PresentApp/Views/Shared/EmptyStateStyle.swift:1-9`

**Anti-pattern:** Never vertically center an empty state. Always
top-align.

**Usage:**
`ActivitiesListView:58-64`, `ActivitySessionCard:32-38`,
`ReportsView:86-96`

---

## Data Display

### Stat Item

A compact vertical unit showing an icon, a bold value, and a label.

**When to use:** Summary statistics in headers or overview sections
(e.g., "Today at a Glance", Reports summary bar).

**Structure:**

- `VStack` with `Constants.spacingCompact` (8pt) spacing
- Optional SF Symbol icon: `.font(.controlIconSmall)`,
  `.foregroundStyle(.secondary)`, `.accessibilityHidden(true)`
- Value: `.font(.statValue)` (title, bold)
- Label: `.font(.caption)`, `.foregroundStyle(.secondary)`

**Canonical example:**
`PresentApp/Views/Shared/StatItem.swift:3-31`

**Layout:** Group multiple `StatItem` views in an
`HStack(spacing: 40)`.

**Usage:**
`DashboardView:263-279`, `ReportsView:411-431`

---

## Charts

### Stacked Bar Chart (Vertical)

Multi-activity time distribution across time periods with hover tooltips
and an interactive legend.

**When to use:** Showing how time breaks down by activity across days,
weeks, or months.

**Structure:**

- `Chart` with `BarMark` (x: period label, y: duration), stacked via
  `.foregroundStyle(by:)`
- Color mapping:
  `.chartForegroundStyleScale(domain:, range:)` from shared activity
  color map
- Weekend highlighting: `RectangleMark` with
  `Constants.alternatingRowBackground`, `zIndex: -1`
- Y-axis labels with unit suffix (`"Xh"` or `"Xm"`)
- Hover overlay via `.chartOverlay` with `GeometryReader` and
  `ChartTooltip`
- Legend below chart via `HoverableChartLegend`
- Active session bars pulse via `ActivePulseState`
- Accessibility:
  `.accessibilityElement(children: .combine)` + label + value summary
- Height: `.frame(height: 250)`, padding: `Constants.spacingCard`
- Wrapped in `ChartCard`

**Canonical example:**
`PresentApp/Views/Reports/ReportStackedBarChart.swift:76-160`

**Also see:**
`PresentApp/Views/Dashboard/DashboardWeeklyChartCard.swift:65-153`
(weekly variant)

---

### Donut Chart

Proportional breakdown with a center tooltip on hover and an interactive
legend.

**When to use:** Showing percentage distribution of activities or
categories.

**Structure:**

- `Chart` with `SectorMark`: `innerRadius: .ratio(0.5)`,
  `angularInset: 1`
- Color mapping:
  `.chartForegroundStyleScale(domain:, range:)`
- Hover detection: `.chartAngleSelection(value:)` bound to `@State`
- Center tooltip: `DonutCenterTooltip` positioned at plot frame center,
  showing title + duration + percentage
- Legend below: `HoverableChartLegend` with optional
  `onHoverStart`/`onHoverEnd` callbacks
- Opacity: hovered sector 1.0, others 0.4; active sector pulses via
  `ActivePulseState`
- Accessibility:
  `.accessibilityElement(children: .combine)` + label + value with
  percentages
- Height: `.frame(height: 250)`, padding: `Constants.spacingCard`
- Wrapped in `ChartCard`

**Canonical example:**
`PresentApp/Views/Reports/ReportActivityPieChart.swift:53-107`

**Also see:**
`PresentApp/Views/Reports/ReportExternalIdChart.swift:63-125`

---

### Horizontal Bar Chart

Horizontal stacked bars for tag or category comparison.

**When to use:** Comparing totals across tags or categories where the
list is variable-length.

**Structure:**

- `Chart` with `BarMark` (x: hours, y: tag label), stacked by activity
- Y-axis labels include metadata:
  `"\(tagName) · \(duration) (\(count))"`
- Dynamic height: `max(120, CGFloat(count) * 36 + 40)`
- Hover overlay with `ChartTooltip`
- Accessibility:
  `.accessibilityElement(children: .combine)` + label + value summary
- Wrapped in `ChartCard`

**Canonical example:**
`PresentApp/Views/Reports/ReportTagBarChart.swift:71-131`

---

### Day Timeline

A horizontal bar showing colored session blocks across a 24-hour track.
This is a custom `GeometryReader` layout, not a Swift Chart.

**When to use:** Visualizing when sessions occurred during a single day.

**Structure:**

- Outer `VStack(alignment: .leading, spacing: Constants.spacingCompact)`
- `GeometryReader` containing a `ZStack(alignment: .leading)`:
  - Track background: `RoundedRectangle(cornerRadius: 8)`,
    `Color.gray.opacity(0.12)`, height 48pt
  - Session blocks: `RoundedRectangle(cornerRadius: 2.5)` positioned
    proportionally via start/end times
  - Tick marks: `Rectangle()` at 3-hour intervals,
    `theme.constantWhite.opacity(0.15)`, 1pt wide
- X-axis labels below: `.font(.caption2)`,
  `.foregroundStyle(.secondary)` at 3-hour intervals
- Hover: `onContinuousHover` with `ChartTooltip` overlay above bar
- Live segment: `.activePulse()` modifier
- Legend: `HoverableChartLegend` at bottom
- Accessibility: `.accessibilityElement(children: .combine)` on outer
  `VStack`

**Canonical example:**
`PresentApp/Views/Shared/DayTimelineChart.swift:80-165`

---

### Chart Data Transition

Native Swift Charts animation when chart data changes, letting marks
grow/shrink, slices morph, and axes rescale smoothly.

**When to use:** Any view that reloads chart data on user interaction
(period change, date navigation, filter toggle).

**How:** Wrap state assignments in `withAdaptiveAnimation(.easeInOut(duration: 0.35))`
at the data-loading site (e.g., `ReportsView.loadReport()`). Swift Charts
interpolates mark transitions automatically. Reduce Motion uses a faster
linear animation via `withAdaptiveAnimation`.

**Canonical example:** `ReportsView.swift` — `loadReport()` method

**Key rule:** Do not clear chart data before reloading (`clearData: false`).
Old data stays visible while new data loads, preventing empty-state flashes.

---

## Chart Support Components

### Chart Tooltip

Floating frosted-glass tooltip for chart hover states.

**When to use:** Any chart that reveals details on hover.

**Structure:**

- `VStack(alignment: .leading, spacing: 3)` content
- Padding: `Constants.spacingCompact` (8pt)
- Background: `.ultraThickMaterial` with
  `RoundedRectangle(cornerRadius: 8)`
- Shadow: `.black.opacity(0.15)`, radius 4, y-offset 2
- `.allowsHitTesting(false)`
- Position via `tooltipPosition(cursor:containerSize:)` utility

**Typography inside tooltips:**

- Header: `.font(.dataLabel)` (bold caption)
- Values: `.font(.dataValue)` (mono caption)
- Totals: `.font(.dataBoldValue)` (bold + mono caption)
- Metadata: `.font(.caption2)`, `.foregroundStyle(.secondary)`

**Canonical example:**
`PresentApp/Views/Shared/ChartTooltip.swift:5-18`

**Donut center variant:**
`ChartTooltip.swift:21-31` -- `VStack(spacing: 2)`, max width 100,
centered text

---

### Hoverable Chart Legend

Interactive color legend with flow layout. Hovering an item dims other
chart elements.

**When to use:** Below any chart that uses activity or category colors.

**Structure:**

- `FlowLayout(spacing: 8)` container
- Each item: `HStack` with 8pt colored `Circle` + `.font(.caption)`
  label
- Pill padding: `.vertical(2)`, `.horizontal(6)`
- Hover background: `RoundedRectangle(cornerRadius: 4)` with
  `Color.primary.opacity(0.08)`
- `@Binding var hoveredLabel` for chart opacity coordination
- Optional `onHoverStart`/`onHoverEnd` callbacks

**Outside padding:**
`.padding(.horizontal, Constants.spacingCard)`,
`.padding(.bottom, Constants.spacingCard)`

**Canonical example:**
`PresentApp/Views/Shared/HoverableChartLegend.swift:3-38`

---

## Lists and Rows

### Activity Row

A list row showing an activity's title, metadata badges, and secondary
info.

**When to use:** Activity list items in the sidebar or selection views.

**Structure:**

- Primary text: `.font(.body.bold())` or `.font(.headline)`
- Secondary row: `.font(.caption2)`, `.foregroundStyle(.secondary)`
  with metadata (system badge, archived badge, tag pills)
- Tag pills: capsule with colored background at 0.15 opacity
- Padding: `.padding(.vertical, Constants.spacingTight)` (4pt)

**Canonical example:**
`PresentApp/Views/Activities/ActivitiesListView.swift:250-321`

---

### Expandable Group Header

A clickable header with chevron, color dot, title, count, and
right-aligned duration. Expands to reveal child rows.

**When to use:** Grouped session lists where sessions are organized by
activity.

**Structure:**

- `HStack`: chevron (rotates 90 degrees when expanded) +
  color `Circle(8pt)` + title `VStack` + `Spacer` + duration
- Duration: `.font(.durationValue)` with
  `.contentTransition(.numericText())`
- Background: alternating `Constants.alternatingRowBackground` for every other
  group
- Hover: `.hoverHighlight()` modifier
- Expand animation:
  `withAdaptiveAnimation(.easeInOut(duration: 0.2))`

**Canonical example:**
`PresentApp/Views/Shared/ActivitySessionCard.swift:192-251`

---

### Session Row (Grouped)

A session row nested under an expandable activity header.

**When to use:** Inside expanded activity groups in
`ActivitySessionCard`.

**Structure:**

- Active session: `SpinningClockIcon` + type label + metadata badges +
  duration
- Completed session: state icon + type label + time range + metadata
  badges + duration
- Sub-row background: `Color.gray.opacity(0.04)` (subtler than group
  headers)
- Hover: `.hoverHighlight()`
- Metadata badges: `TicketBadge` (capsule, accent background at
  0.12 opacity) + optional note indicator icon

**Canonical example:**
`PresentApp/Views/Shared/ActivitySessionCard.swift:349-373`

---

## Editing and Input

### Inline Editable Text

A text display that toggles to an editable field on click, with a
hover-revealed Edit pill.

**When to use:** Single-field edits that should happen in place without
navigation (e.g., activity title, session notes).

**Structure:**

- **Display state:** clickable text with pointer cursor;
  `EditPillButton` appears on hover and expands to show "Edit" label
- **Edit state:** `TextField` with `.textFieldStyle(.roundedBorder)` +
  save/cancel buttons (`.buttonStyle(.bordered)`)
- Save button: `.tint(theme.success)`;
  cancel button: `.tint(theme.alert)`
- Focus: `@FocusState` for auto-focus on edit
- Commit: save on blur, Return key, or explicit save button
- Animation: `.adaptiveAnimation(.easeInOut(duration: 0.15))`

**Canonical example:**
`PresentApp/Views/Shared/InlineEditableField.swift:4-144`

**Usage:**
`ActivitiesDetailView:119-135`

---

### Tag Pill Input

Flow layout of tag pills with remove buttons and a free-type input with
autocomplete.

**When to use:** Managing tags on an activity or session.

**Structure:**

- `FlowLayout(spacing: 6)` containing tag pills + input field
- Tag pill: `HStack` with tag name + xmark remove button
- Pill styling:
  `.padding(.horizontal, Constants.spacingCompact)`,
  `.padding(.vertical, Constants.spacingTight)`,
  `.background(color.opacity(0.15), in: Capsule())`
- Input: `TextField` with `.frame(width: 100)`, `.fixedSize()`
- Add on Return key or explicit button
- Dropdown menu for browsing unassigned tags

**Canonical example:**
`PresentApp/Views/Activities/ActivitiesDetailView.swift:564-618`

---

### Session Inline Edit Form

A full-width form that replaces a session row for in-place editing.

**When to use:** Editing session details (activity, times, notes)
without navigation.

**Structure:**

- `VStack(alignment: .leading)` with control row and note row
- Top row: Activity `Picker` + start/end `DatePicker`
  (`.stepperField` style) + optional paused-time label + Done button
- Note row: `MarkdownEditor` with
  `.frame(minHeight: 60, maxHeight: 100)`
- Error display: `.font(.body)`, `.foregroundStyle(theme.alert)`
- Background: `Color.primary.opacity(0.06)` in
  `RoundedRectangle(cornerRadius: 8)`
- Field labels: `.font(.fieldLabel)` (subheadline, bold); changes to
  alert color on validation error
- Escape key: reverts changes

**Canonical example:**
`PresentApp/Views/Shared/SessionInlineEditForm.swift:9-274`

---

## Controls

### Themed Toggle

A custom switch-style toggle with theme-aware accent color.

**When to use:** Settings and preference forms where a prominent on/off
switch is appropriate. For secondary filter controls in toolbars, prefer
the Filter Menu pattern instead.

**Structure:**

- Track: `RoundedRectangle(cornerRadius: 16)`, filled with `tintColor`
  when on, `.secondary.opacity(0.3)` when off
- Thumb: white `Circle()` with shadow, offset left/right based on state
- Size: 44pt wide x 26pt tall
- Animation: `withAdaptiveAnimation(.snappy(duration: 0.15))`

**Canonical example:**
`PresentApp/Views/Shared/ThemedToggleStyle.swift:8-34`

**Usage:**
`.toggleStyle(ThemedToggleStyle(tintColor: theme.accent))`

---

### Filter Menu

A single icon button that collapses multiple boolean filter toggles into
a popover. The icon fills and tints with the accent color when any
filter differs from its default, providing a subtle visual cue without
competing with primary content. Uses a popover (not a native `Menu`) so
the panel stays within the application window.

**When to use:** Secondary filter controls in toolbars or control bars
where full-size toggles are too visually prominent. Ideal for 2-4
boolean options that the user adjusts infrequently.

**Structure:**

- Icon: `line.3.horizontal.decrease.circle` (unfilled) /
  `line.3.horizontal.decrease.circle.fill` (filled when non-default)
- Color: `.secondary` when default, `theme.accent` when non-default
- Font: `.controlIcon`
- Popover: `VStack` of native `Toggle` views with a bold header,
  `.fixedSize()`, padding `Constants.spacingPage`, arrow edge `.trailing`
- Defaults: define `hasNonDefaultFilters` by comparing each toggle to its
  initial value (e.g., `showArchived` defaults to `true`, so `!showArchived`
  is non-default)
- Always show all filter options; disable those that are irrelevant
  rather than hiding them
- Accessibility: `.accessibilityLabel("Chart filters")` on the button,
  `.accessibilityValue("Active" / "Default")` for filter state,
  `.help("Chart filters")` for tooltip

**Canonical example:**
`PresentApp/Views/Reports/ReportsView.swift` — `chartFilterMenu`
computed property

**Usage:**
```swift
@State private var showFilterPopover = false

/// Defaults: showArchived=true, showActiveSessions=false.
private var hasNonDefaultFilters: Bool {
    !showArchived || showActiveSessions
}

Button {
    showFilterPopover.toggle()
} label: {
    Image(systemName: hasNonDefaultFilters
        ? "line.3.horizontal.decrease.circle.fill"
        : "line.3.horizontal.decrease.circle")
        .foregroundStyle(hasNonDefaultFilters
            ? AnyShapeStyle(theme.accent)
            : AnyShapeStyle(.secondary))
        .font(.controlIcon)
}
.buttonStyle(.plain)
.accessibilityLabel("Chart filters")
.accessibilityValue(hasNonDefaultFilters ? "Active" : "Default")
.popover(isPresented: $showFilterPopover, arrowEdge: .trailing) {
    VStack(alignment: .leading, spacing: Constants.spacingCard) {
        Text("Filters")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            Toggle("Include archived activities", isOn: $showArchived)
            Toggle("Include active session", isOn: $showActiveSessions)
                .disabled(!isRelevant)
        }
    }
    .padding(Constants.spacingPage)
    .fixedSize()
}
```

---

### Hover Highlight

Subtle background highlight on hover for interactive rows.

**When to use:** List rows, session rows, expandable headers -- any row
the user can interact with. **Not** for sidebar navigation or tab bars
(per Apple HIG).

**Structure:**

- `@State private var isHovered`
- Background: `Color.primary.opacity(0.10)` when hovered,
  `Color.clear` otherwise
- Applied via `.hoverHighlight()` view modifier

**Canonical example:**
`PresentApp/Views/Shared/HoverHighlight.swift:8-24`

---

## Settings

### Settings Form Section

A grouped form section with header, controls, and optional descriptive
footer.

**When to use:** All settings tabs.

**Structure:**

- `Form` with `.formStyle(.grouped)` and `.padding()`
- `Section` with `Text(title)` header
- Footer (when needed): `Text(description)` with `.font(.caption)`,
  `.foregroundStyle(.secondary)`
- Toggles: `ThemedToggleStyle(tintColor: theme.accent)`
- Pickers: `.pickerStyle(.menu)` or `.pickerStyle(.segmented)`
- Danger sections: header with `theme.alert` color and alert icon

**Canonical example:**
`PresentApp/Views/Settings/SettingsView.swift:68-661`

---

## Background Tints Reference

Consistent opacity values for layered backgrounds across the app:

| Context | Color | Opacity | Example |
| --- | --- | --- | --- |
| Weekend chart columns | `Color.gray` | 0.08 | `ReportStackedBarChart` |
| Alternating group rows | `Color.gray` | 0.08 | `ActivitySessionCard` |
| Sub-rows (nested) | `Color.gray` | 0.04 | `ActivitySessionCard` |
| Timeline track | `Color.gray` | 0.12 | `DayTimelineChart` |
| Hover highlight | `Color.primary` | 0.10 | `HoverHighlight` |
| Legend hover pill | `Color.primary` | 0.08 | `HoverableChartLegend` |
| Inline edit form bg | `Color.primary` | 0.06 | `SessionInlineEditForm` |
| Tag pill fill | activity color | 0.15 | `ActivitiesDetailView` |
| Ticket badge fill | `theme.accent` | 0.12 | `TicketBadge` |
