# Floating Alert Design Patterns

Design reference for the floating alert system used when timed sessions
complete. These patterns ensure visual consistency across alert types
(timebound, rhythm focus, rhythm break, standalone break) and serve as
the blueprint for future floating alert windows.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Header](#header)
  - [Icons](#icons)
  - [Title and Duration](#title-and-duration)
  - [Badge Pills](#badge-pills)
- [Button Tiers](#button-tiers)
  - [Primary Action Card](#primary-action-card)
  - [Muted Action Card](#muted-action-card)
  - [Dismiss Button](#dismiss-button)
- [Icon Transitions](#icon-transitions)
- [Animation Standards](#animation-standards)
- [Reusable Components](#reusable-components)
- [Source File Reference](#source-file-reference)

## Architecture Overview

A floating alert is an `NSPanel` managed by
`FloatingAlertPanelManager`. The panel floats above all windows and
spaces, uses a translucent material background, and is dismissed
programmatically after the user takes an action.

```text
TimerCompletionContext
  --> FloatingAlertPanelManager
        --> NSPanel
              |-- FloatingAlertView (SwiftUI)
                    |-- Header
                    |-- Divider
                    |-- Actions (cards / buttons)
```

Key panel properties:

- **Level**: `.floating` -- stays above standard windows.
- **Collection behavior**:
  `.canJoinAllSpaces, .fullScreenAuxiliary` --
  visible on every desktop and in full screen.
- **Background**: `.regularMaterial` in a 16pt rounded rectangle.
- **Width**: Fixed at 320pt.
- **Positioning**: Centered on the main screen.
- **Dismissal**: `orderOut` immediately, then `close()` on the
  next run loop tick to avoid corrupting SwiftUI's view update
  cycle.

## Header

### Icons

Header icons communicate session type at a glance. Rhythm sessions
use muted custom icons in `.tertiary` color rather than accented
SF Symbols. This keeps the tone calm and avoids visual urgency.

| Session Type | Icon | Color | Animation |
| --- | --- | --- | --- |
| Timebound | `timer` (SF Symbol) | `.tertiary` | None |
| Rhythm Focus | `FocusBrainIcon` | `.tertiary` | None (static) |
| Rhythm Break | `SteamingCupIcon` | `.tertiary` | Steam wisps |
| Standalone Break | `SteamingCupIcon` | `.tertiary` | Steam wisps |

**Rhythm icon details:**

- `FocusBrainIcon` -- Horizontally flipped
  `brain.filled.head.profile` at `.tertiary`. Static display,
  matching the visual weight of SteamingCupIcon's cup.
- `SteamingCupIcon(size:)` -- `cup.and.saucer` at `.tertiary`
  with three steam wisp paths above the rim. Each wisp animates
  independently with a randomized duration (1.5--2.8s) and
  initial delay, producing organic drift. Pass `size: 28` for
  inline use in alert headers; the default 48pt is for detail
  views.

### Title and Duration

- **Title**: `.headline` weight, centered, up to two lines.
  Examples: "Focus Session Complete", "Break Complete",
  "\<Activity Name\> Complete".
- **Duration display**: All session types use `Xm / Ym` where
  `Xm` is the elapsed value and `/ Ym` is the total. The total
  portion uses `.secondary.opacity(0.5)` so it reads as
  supplementary context rather than a primary value. Both parts
  use `.timerDisplay` font.

Badge pills have been removed from all alert types. The icon,
title, and action cards provide sufficient context.

## Button Tiers

The most likely action stands out immediately. Everything else
starts grey and reveals its intent on hover.

### Design Principle

- **One primary action** per alert, shown in `theme.primary`
  even at rest. This is the action the user most likely wants.
- **All other options start grey** (`Color.secondary.opacity(0.3)`).
  Hover reveals what kind of action it is:
  - **Primary hover** (`theme.primary`): A typical, safe action.
  - **Danger hover** (`theme.alert`): A riskier or more final
    action (ending a session, discarding progress).

This keeps the alert visually calm while making the recommended
path obvious at a glance.

### Primary Action Card

The action the user most likely wants. Uses `ResumeActivityCard`.

- **Background**: `theme.primary` at 0.45 opacity, deepening to
  0.65 on hover.
- **Text**: White title (`.callout.weight(.medium)`) and subtitle
  (`.caption` at 0.85 opacity).
- **Icon**: White, `.callout` font, in a fixed 16pt frame.
- **Corner radius**: 8pt.
- **Example**: "Resume \<Activity\>" after a break, "Continue \<Activity\>" after a timebound session.

### Secondary Action Card

A valid alternative. Grey at rest, reveals `theme.primary` on
hover to signal it is a safe action. Uses `ResumeActivityCard`
with `muted: true`.

- **Background**: `Color.secondary.opacity(0.3)` at rest,
  transitioning to `theme.primary.opacity(0.45)` on hover.
- **Text and icon**: Same styling as primary cards (white).
- **Example**: "No break this time" when a focus session offers a break.

### Dismiss Button

Ends or cancels the session. Grey at rest, reveals `theme.alert`
on hover to signal this is a more final action. Uses
`DismissButton`.

- **Background**: `Color.secondary.opacity(0.3)` at rest. Hover
  reveals `theme.alert.opacity(0.2)`.
- **Text**: White, always.
- **Icon**: White at rest, shifts to `theme.alert` on hover.
  Uses `.symbolEffect(.replace)` to swap from `icon` to
  `hoverIcon`.
- **Default label**: "Done for now".
- **Default icons**: `stop.fill` at rest, `moon.zzz.fill` on hover.

### Button Phrasing by Alert Type

Action verbs follow the conventions in the Voice & Tone section
of `CLAUDE.md`. The verb signals what just happened and what
the button will do next.

| Alert | Primary Card | Secondary Card | Dismiss |
| --- | --- | --- | --- |
| Timebound expiry | Continue \<Activity\> | -- | Done for now |
| Rhythm focus expiry | Start Xm Break | No break this time · \<Activity\> | End Rhythm Session |
| Rhythm break expiry | Resume \<Activity\> | -- | Done for now |
| Standalone break expiry | Resume \<Activity\> | -- | Done for now |

**Why "Resume" vs "Continue":**

- **Resume** appears after a break. The user was working on
  this activity before the break interrupted; tapping resumes
  where they left off.
- **Continue** appears after a completed timebound session.
  Nothing was interrupted; tapping starts a fresh session of
  the same kind.

## Alert Type: Standalone Break

When a standalone timebound break completes (not part of a rhythm
session), the alert shows "Break Complete" with the `SteamingCupIcon`
header, matching the rhythm break visual style.

**Actions layout:**

- **If a recent non-system session exists** (within 24 hours):
  A primary `ResumeActivityCard` showing the activity title,
  with a subtitle indicating the session type and duration
  (e.g., "Timebound \u{00B7} 25m"). Tapping resumes the
  same activity with the same session type and timer.
- **If no recent session exists**: The resume card is omitted.
  Only the dismiss button appears.
- **Always**: A `DismissButton` with the default "Done for now"
  label.

This is modeled by `CompletionType.timeboundBreakExpiry`, which
carries optional fields for the recent session. The 24-hour
lookback window prevents surfacing stale sessions from days ago.

## Icon Transitions

All action icons use
`.contentTransition(.symbolEffect(.replace))` -- the icon swaps
to a different symbol on hover, reinforcing the action's meaning.

| Action | Default | Hover | Why |
| --- | --- | --- | --- |
| Resume focus | `arrow.counterclockwise` | `play.fill` | Restart becomes play |
| Start break | `play.fill` | `cup.and.saucer.fill` | Play becomes rest |
| No break this time | `forward.fill` | `brain.filled.head.profile` (flipped) | Skip ahead to focus |
| Done / End | `stop.fill` | `moon.zzz.fill` | Stop becomes rest |

**Prefer filled icons.** Use filled variants (`play.fill`,
`forward.fill`, `stop.fill`, `cup.and.saucer.fill`) over outline
versions. Filled icons provide stronger visual contrast against
the card backgrounds, especially at small sizes.

Fixed-width icon frames (16pt for cards) prevent text from
shifting when icons swap.

`IconHoverEffect` also defines `.nudge` (3pt rightward offset)
and `.lift` (2pt upward + 1.15x scale) effects for future use:

| Effect | Animation | When to Use |
| --- | --- | --- |
| `.replace(hover:, flipHover:)` | Symbol swap (optional horizontal flip) | Action changes meaning |
| `.nudge` | 3pt rightward offset | Forward/skip actions |
| `.lift` | 2pt up + 1.15x scale | Calm/settling actions |

## Animation Standards

- **Hover transitions**: All floating alert hover states use the
  shared `alertHoverAnimation` constant
  (`.easeInOut(duration: 0.3)`) via
  `withAdaptiveAnimation(alertHoverAnimation)`. This is the
  imperative adaptive animation wrapper, not raw `withAnimation`.
  The constant is defined once at the top of
  `FloatingAlertView.swift` so timing changes apply everywhere.
- **Continuous animations** (steam wisps): Longer durations
  (1.5--2.8s) with `.repeatForever(autoreverses: true)`. These
  run through SwiftUI's `.animation()` modifier directly because
  they are perpetual view-level effects, not user-triggered state
  changes.
- **Reduce Motion**: All animations respect
  `@Environment(\.accessibilityReduceMotion)`. Continuous
  animations stop entirely and display at a static opacity.
  Hover transitions fall back to `.linear(duration: 0.15)` via
  `withAdaptiveAnimation`.
- **Symbol transitions**:
  `.contentTransition(.symbolEffect(.replace))` for icon swaps
  handles reduce motion automatically.

## Reusable Components

- **`ResumeActivityCard`** (`FloatingAlertView.swift`) --
  Configurable card-style action button. Accepts `title`,
  `subtitle`, `icon`, `iconEffect`, and `muted` flag.
- **`DismissButton`** (`FloatingAlertView.swift`) -- Secondary
  dismiss button with alert-colored hover state. Configurable
  `label`, `icon`, and `hoverIcon`.
- **`FocusBrainIcon`** (`FloatingAlertView.swift`) -- Flipped
  `brain.filled.head.profile` at `.tertiary`. Static display,
  private to the floating alert module.
- **`SteamingCupIcon`** (`Views/Shared/SteamingCupIcon.swift`) --
  Animated steam cup icon. Shared component, scalable via `size`
  parameter.
- **`IconHoverEffect`** (`FloatingAlertView.swift`) -- Enum
  defining three hover animation styles for card icons.

## Source File Reference

| File | Path |
| --- | --- |
| Alert view | `PresentApp/FloatingAlert/FloatingAlertView.swift` |
| Panel manager | `PresentApp/FloatingAlert/FloatingAlertPanelManager.swift` |
| Steaming cup | `PresentApp/Views/Shared/SteamingCupIcon.swift` |
| Animations | `PresentApp/Views/Shared/AdaptiveAnimation.swift` |
| Context model | `Sources/PresentCore/Models/TimerCompletionContext.swift` |
