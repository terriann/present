# Architecture

This document covers the internal architecture of the Present macOS app.
For the high-level system overview (PresentCore, PresentCLI, PresentApp),
see [CLAUDE.md](../.claude/CLAUDE.md). For database schema and queries,
see [database.md](database.md).

## Table of Contents

- [AppState Manager Decomposition](#appstate-manager-decomposition)
  - [Coordinator Pattern](#coordinator-pattern)
  - [File Reference](#file-reference)
  - [Data Flow](#data-flow)
  - [Navigation](#navigation)
  - [Design Rules](#design-rules)
  - [Forwarding Shims](#forwarding-shims)
  - [Callbacks](#callbacks)
  - [Adding a New Manager](#adding-a-new-manager)

## AppState Manager Decomposition

`AppState` was decomposed from a single 620-line `@Observable` class into
a coordinator that delegates to four focused managers. Each manager owns
one domain of state and logic. Views are unaffected — they still access
everything through `@Environment(AppState.self)`.

### Coordinator Pattern

```text
Views → @Environment(AppState.self) → AppState (coordinator)
                                         ├── ZoomManager
                                         ├── TimerManager
                                         ├── DataRefreshCoordinator
                                         ├── SessionManager
                                         └── navigate(to:) → pendingNavigation
                                                              ↓ onChange
                                                           MenuBarLabelView
                                                           (openWindow / openSettings)
```

`AppState` is the only object injected into the SwiftUI environment.
Managers are internal implementation details that views never reference
directly.

**AppState** coordinates cross-cutting concerns:

- Owns `currentSession` and `currentActivity` as central state.
- Chains calls across managers (e.g., start session → start timer →
  play sound → refresh data).
- Handles timer completion flow and alert actions.
- Runs `refreshAll()` to sync session state, data, and preferences.

**Managers** each own a single domain:

| Manager | Domain |
| ------- | ------ |
| `ZoomManager` | Zoom scale, persistence |
| `TimerManager` | Tick loop, elapsed time, countdown |
| `DataRefreshCoordinator` | Data queries, polling, IPC |
| `SessionManager` | `PresentService` session wrapper |

### File Reference

All files live in `PresentApp/ViewModels/`:

- **`AppState.swift`** — Coordinator. Owns managers, forwards
  properties, handles cross-manager coordination.
- **`ZoomManager.swift`** — Zoom scale state, preference
  persistence, zoom in/out/reset actions.
- **`TimerManager.swift`** — Timer tick loop, elapsed seconds,
  completed timer linger, break context persistence
  (UserDefaults), preference resolvers for break/cycle settings.
- **`DataRefreshCoordinator.swift`** — All data state (today
  summary, weekly summary, activities, tags, rhythm options).
  Owns polling loop and IPC server.
- **`SessionManager.swift`** — Thin wrapper. Each method calls
  `PresentService` and returns the result. AppState handles
  timer/sound/refresh/error coordination around it.
- **`AppError.swift`** — `ErrorScene` enum and `AppError` struct
  for scoped error alerts.
- **`SidebarItem.swift`** — Navigation enum for the sidebar.
- **`SettingsTab.swift`** — Settings tab enum, shared between
  `SettingsView` and `NavigationAction`.
- **`NavigationAction.swift`** — Centralized navigation action
  enum consumed by `AppState.navigate(to:)`.

### Data Flow

A session start illustrates how the coordinator chains calls across
managers:

```text
1. View calls          appState.startSession(activityId:type:...)
2. AppState calls      timer.clearCompletedTimerLinger()
3. AppState calls      sessionMgr.startSession(...)  → PresentService
4. AppState updates    currentSession, currentActivity
5. AppState calls      timer.startTimer(session:)
6. AppState calls      SoundManager.shared.play(.blow)
7. AppState calls      refreshAll()
   7a.                   service.currentSession()     → sync session state
   7b.                   dataRefresh.refreshData(...)  → fetch summaries
   7c.                   zoom.loadFromPreferences()    → sync zoom
```

Timer completion flows in the opposite direction — the timer tick loop
detects countdown expiry and invokes a callback on AppState:

```text
1. TimerManager tick   detects elapsed >= countdown target
2. TimerManager calls  onCountdownCompleted callback
3. AppState runs       handleTimerCompletion()
   3a.                   builds TimerCompletionContext
   3b.                   sends notification, plays sound
   3c.                   starts completed timer linger
   3d.                   calls stopSession()
   3e.                   sets timerCompletionContext for floating alert
```

### Navigation

All cross-context navigation (menu bar → main window, any view → settings)
flows through `AppState.navigate(to:)`. This replaces the previous
`NotificationCenter`-based pattern with a single, observable property.

**`NavigationAction`** (`NavigationAction.swift`) defines the possible
navigation targets:

| Action | Effect |
| ------ | ------ |
| `.launchMainWindow` | Show dock icon, bring main window forward |
| `.showDashboard` | Set sidebar to dashboard, open main window |
| `.showActivity(id)` | Set sidebar to activities, set `navigateToActivityId`, open main window |
| `.showSettings(tab?)` | Open main window, then open settings (optionally selecting a tab) |

**How it works:**

```text
1. Caller invokes        appState.navigate(to: .showSettings(.cli))
2. AppState sets         pendingSettingsTab = .cli
3. AppState sets         pendingNavigation = .showSettings(.cli)
4. MenuBarLabelView      onChange fires → shows dock icon, opens window,
                         opens settings after 0.3s delay
5. SettingsView          onChange fires → sets selectedTab = .cli,
                         clears pendingSettingsTab
```

`MenuBarLabelView` is the bridge between `AppState` (observable) and
SwiftUI environment actions (`openWindow`, `openSettings`). It observes
`pendingNavigation`, clears it immediately, then executes the
corresponding SwiftUI action.

**Same-context navigation** (sidebar tab switching within the main window)
still uses direct property assignment (`appState.selectedSidebarItem = .activities`).
This is intentional — routing in-window navigation through `navigate(to:)`
would add unnecessary overhead.

### Design Rules

1. **No manager-to-manager references.** Managers are independent.
   AppState is the only place that chains calls across managers. If
   a new feature requires coordination between two managers, that
   logic belongs in AppState.

2. **Two callbacks only.** `TimerManager.onCountdownCompleted` and
   `DataRefreshCoordinator.onRefreshNeeded`. Both are set once during
   `AppState.init()`. All other communication is through direct method
   calls from AppState to managers.

3. **Managers do not trigger side effects.** Sound, notifications,
   error handling, and IPC are AppState's responsibility. Managers
   return results or update their own state; AppState decides what
   else happens.

4. **`currentSession` lives on AppState.** `TimerManager` holds a
   copy (`timer.currentSession`) for the tick loop to read session
   info (timer length, pause state) without a callback. AppState
   keeps both in sync.

### Forwarding Shims

AppState exposes manager state through forwarding computed properties
so views never need to know about managers:

```swift
// AppState.swift
var timerElapsedSeconds: Int { timer.timerElapsedSeconds }
var zoomScale: CGFloat { zoom.zoomScale }
var todayTotalSeconds: Int { dataRefresh.todayTotalSeconds }
```

Because managers are `@Observable` and AppState's forwarding properties
read from them, SwiftUI correctly tracks dependencies through the
chain. A view reading `appState.timerElapsedSeconds` will re-render
when `TimerManager.timerElapsedSeconds` changes.

For actions, AppState either forwards directly or wraps with
coordination logic:

```swift
// Direct forwarding (no coordination needed)
func zoomIn() { zoom.zoomIn() }

// Wrapped with coordination (session start needs timer + sound + refresh)
func startSession(...) async {
    timer.clearCompletedTimerLinger()
    let (session, activity) = try await sessionMgr.startSession(...)
    currentSession = session
    timer.startTimer(session: session)
    SoundManager.shared.play(.blow)
    await refreshAll()
}
```

### Callbacks

Both callbacks use `async` closures set during `AppState.init()`:

```swift
// TimerManager → AppState: countdown finished
timer.onCountdownCompleted = { [weak self] in
    await self?.handleTimerCompletion()
}

// DataRefreshCoordinator → AppState: polling cycle fired
dataRefresh.onRefreshNeeded = { [weak self] in
    await self?.refreshAll()
}
```

`[weak self]` prevents retain cycles. Both callbacks are fire-and-forget
from the manager's perspective — the manager does not read return values
or catch errors from them.

### Adding a New Manager

1. Create a new `@MainActor @Observable final class` in
   `PresentApp/ViewModels/`.
2. Accept `PresentService` (or other dependencies) via `init`.
3. Add the manager as a property on `AppState` and initialize it in
   `AppState.init()`.
4. Add forwarding computed properties on `AppState` for any state
   views need to read.
5. Add forwarding methods on `AppState` for any actions views need
   to call. Wrap with coordination logic if the action involves
   multiple managers.
6. If the manager needs to notify AppState asynchronously, add a
   single callback property (following the existing pattern). Set it
   in `AppState.init()`.
