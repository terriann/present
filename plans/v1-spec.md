# Present V1 Spec — macOS Time Tracking App

> Present is a simple, intentional way to track time with focused sessions and effortless logging.

## Context

This is a greenfield macOS app built from scratch. The user has experience in PHP and Node.js but is new to macOS development. The spec covers the full V1 scope: a menu bar + windowed SwiftUI app, a CLI tool, local SQLite storage, and distribution as a signed DMG.

---

## 1. Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Language | Swift 6.0 | Native macOS, best performance, modern concurrency |
| UI Framework | SwiftUI | Declarative, Apple's current standard |
| Database | SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift) | Lightweight, shared between app and CLI, WAL mode for multi-process access |
| SwiftUI DB binding | [GRDBQuery](https://github.com/groue/GRDBQuery) | `@Query` property wrapper bridges GRDB observations into SwiftUI |
| CLI parsing | [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apple's official CLI library |
| Markdown parsing | [swift-markdown](https://github.com/swiftlang/swift-markdown) | Apple's GFM parser (supports checklists) |
| Code highlighting | [Splash](https://github.com/JohnSundell/Splash) | Syntax highlighting for fenced code blocks in notes |
| Charts | Swift Charts (system framework) | Native bar/pie charts for reports |
| Notifications | UserNotifications (system framework) | System notification delivery |
| Min deployment | macOS 15 Sequoia | Latest APIs, `@Observable`, Swift Charts pie support |
| Distribution | Signed/notarized DMG (direct download) | No App Store sandbox restrictions, CLI-friendly |

---

## 2. Architecture

**Pattern:** MVVM with `@Observable` + **PresentAPI protocol** (shared API contract) + GRDB as single source of truth.

### Design Principle: CLI Parity via Shared API

Every user-facing action in the app must be accessible through the CLI. This is enforced architecturally: both the UI and CLI consume the same `PresentAPI` protocol. **Adding a feature to the UI requires adding it to `PresentAPI` first**, which guarantees the CLI can expose it too.

```
┌──────────────────────────────────────────────────┐
│                 SwiftUI Views                     │
│  MenuBarView  DashboardView  LogView  ReportsView │
└──────────┬────────────────────────────────────────┘
           │ observe
┌──────────▼────────────────────────────────────────┐
│            @Observable ViewModels                  │
│  AppState  DashboardVM  LogVM  ReportsVM           │
└──────────┬────────────────────────────────────────┘
           │ call                          │ call
           │                               │
┌──────────▼───────────────────────────────▼────────┐
│               PresentAPI Protocol                  │
│  (Single contract for ALL user actions)            │
│                                                    │
│  Sessions: start / pause / resume / stop / cancel  │
│  Activities: create / update / archive / delete    │
│  Activities: list / get / search                   │
│  Notes: appendNote                                 │
│  Tags: create / delete / list                      │
│  Reports: daily / weekly / monthly / export CSV    │
│  Preferences: get / set                            │
│  Status: currentSession / todaySummary             │
└──────────┬────────────────────────────────────────┘
           │ implemented by
┌──────────▼────────────────────────────────────────┐
│          PresentService (concrete impl)            │
│  Orchestrates database + business logic            │
└──────────┬────────────────────────────────────────┘
           │ read/write
┌──────────▼────────────────────────────────────────┐
│            GRDB DatabasePool (WAL mode)            │
└──────────▲────────────────────────────────────────┘
           │ same PresentAPI
┌──────────┴────────────────────────────────────────┐
│               CLI (`present`)                      │
│  Commands → PresentAPI → DatabasePool + IPC notify │
└───────────────────────────────────────────────────┘
```

### PresentAPI Protocol (defined in PresentCore)

```swift
protocol PresentAPI {
    // Sessions
    func startSession(activityId: Int64, type: SessionType, timerMinutes: Int?) async throws -> Session
    func pauseSession() async throws -> Session
    func resumeSession() async throws -> Session
    func stopSession() async throws -> Session
    func cancelSession() async throws
    func currentSession() async throws -> (Session, Activity)?

    // Activities
    func createActivity(_ input: CreateActivityInput) async throws -> Activity
    func updateActivity(id: Int64, _ input: UpdateActivityInput) async throws -> Activity
    func archiveActivity(id: Int64) async throws -> ArchiveResult  // .archived or .promptDelete
    func deleteActivity(id: Int64) async throws
    func unarchiveActivity(id: Int64) async throws -> Activity
    func listActivities(includeArchived: Bool) async throws -> [Activity]
    func getActivity(id: Int64) async throws -> Activity
    func searchActivities(query: String) async throws -> [Activity]
    func recentActivities(limit: Int) async throws -> [Activity]

    // Notes
    func appendNote(activityId: Int64, text: String) async throws -> Activity

    // Tags
    func createTag(name: String) async throws -> Tag
    func deleteTag(id: Int64) async throws
    func listTags() async throws -> [Tag]
    func tagActivity(activityId: Int64, tagId: Int64) async throws
    func untagActivity(activityId: Int64, tagId: Int64) async throws

    // Reports
    func dailySummary(date: Date, includeArchived: Bool) async throws -> DailySummary
    func weeklySummary(weekOf: Date, includeArchived: Bool) async throws -> WeeklySummary
    func monthlySummary(monthOf: Date, includeArchived: Bool) async throws -> MonthlySummary
    func exportCSV(from: Date, to: Date, includeArchived: Bool) async throws -> Data

    // Preferences
    func getPreference(key: String) async throws -> String?
    func setPreference(key: String, value: String) async throws

    // Status
    func todaySummary() async throws -> TodaySummary
}
```

This protocol is the **single source of truth** for what the app can do. `PresentService` is the concrete implementation that both the UI ViewModels and CLI commands use.

### Key architectural rules
- **PresentCore** contains the `PresentAPI` protocol, its implementation (`PresentService`), models, database, and IPC — consumed by both the app and CLI.
- ViewModels use GRDB `ValueObservation` to reactively update when the database changes (including changes made by the CLI).
- No singletons; `DatabasePool` is injected via initializers for testability.
- The UI layer (ViewModels, Views) never accesses the database directly — always through `PresentAPI`.
- The CLI never accesses the database directly — always through `PresentAPI`.

---

## 3. Data Model (SQLite Schema)

### activity
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| title | TEXT NOT NULL | Activity name |
| externalId | TEXT | Appended to base URL from preferences |
| link | TEXT | Optional standalone URL |
| notes | TEXT | Markdown (GFM) stored as plain text |
| isArchived | INTEGER DEFAULT 0 | 0 = active, 1 = archived |
| createdAt | TEXT | ISO 8601 |
| updatedAt | TEXT | ISO 8601 |

### tag
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| name | TEXT NOT NULL UNIQUE | Tag label |

### activity_tag (join table)
| Column | Type |
|---|---|
| activityId | INTEGER FK → activity(id) ON DELETE CASCADE |
| tagId | INTEGER FK → tag(id) ON DELETE CASCADE |

### session
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| activityId | INTEGER FK | References activity(id) |
| sessionType | TEXT | `work`, `rhythm`, `timebound`, `timebox` |
| startedAt | TEXT | ISO 8601 |
| endedAt | TEXT | NULL while running |
| plannedStart | TEXT | Time Box only |
| plannedEnd | TEXT | Time Box only |
| durationSeconds | INTEGER | Computed on stop: `endedAt - startedAt - totalPausedSeconds` |
| timerLengthMinutes | INTEGER | Rhythm: 25/30/45; Timebound: user-specified |
| rhythmSessionIndex | INTEGER | 1–4 within Rhythm cycle (4th triggers long break) |
| state | TEXT | `running`, `paused`, `completed`, `cancelled` |
| totalPausedSeconds | INTEGER DEFAULT 0 | Accumulated pause time |
| lastPausedAt | TEXT | Set on pause, cleared on resume |
| createdAt | TEXT | ISO 8601 |

### preference (key-value)
| Column | Type |
|---|---|
| key | TEXT PK |
| value | TEXT NOT NULL |

Default keys: `externalIdBaseUrl`, `defaultRhythmMinutes` (25), `shortBreakMinutes` (5), `longBreakMinutes` (15), `notificationSound` (1), `includeArchivedInReports` (0).

### Full-text search
An FTS5 virtual table (`activity_fts`) indexes `title` and `notes` from the `activity` table using porter stemming. Kept in sync via `AFTER INSERT/UPDATE/DELETE` triggers.

---

## 4. Feature Spec

### 4.1 Session Types

Session type names and descriptions are defined in a single configuration file (`Sources/PresentCore/Models/SessionTypeConfig.swift`) so they can be easily renamed or updated without touching business logic.

**Work Session**
- Manual start/pause/stop.
- No time limit. Timer counts up.
- Only one session can be active at a time (across all types).
- *Description shown in app:* "An open-ended session for tracking work without a fixed time limit. Start when you begin, stop when you're done."

**Rhythm Session** *(working title — easy to rename)*
- User selects duration: 25, 30, or 45 minutes.
- Timer counts down. On expiry: session is logged as completed.
- Auto-suggest break: 5-min short break after sessions 1–3, 15-min long break after session 4, then cycle resets.
- User can accept or dismiss the break suggestion.
- Break time is NOT logged as activity time.
- User can end a rhythm session early (logged with actual elapsed time).
- *Description shown in app:* "A structured focus cycle with timed work sessions followed by short breaks. After four sessions, take a longer break to recharge."

**Timebound**
- User sets a fixed duration (freeform minutes input, not limited to presets).
- Timer counts down to zero. On expiry: gentle notification (same notification style as Rhythm Sessions).
- Unlike Rhythm Sessions, there is no break cycle — it's a standalone countdown.
- User can pause/resume or stop early.
- *Description shown in app:* "Set a fixed amount of time to focus. A gentle alert lets you know when time is up."

**Time Box**
- User sets a planned start and end time for a future activity.
- When the time box's start time arrives, a notification prompts the user to begin.
- Standalone — no calendar integration in V1.
- *Description shown in app:* "Plan a block of time for an activity with a specific start and end. You'll be reminded when it's time to begin."

Session type descriptions are displayed in the main app window (e.g., when creating a new session or in a help/info section) but are **not** shown in the menu bar popover to keep it minimal.

### 4.2 Activities

- **Fields:** title, link (optional URL), notes (rich text / Markdown), external ID, tags.
- **Limit:** 50 active activities globally. Enforced at the application layer with a clear error message.
- **Archiving:** Archived activities cannot be used for new sessions but still appear in reports. Archiving an activity with < 10 minutes total tracked time prompts the user to delete it instead.
- **Deletion:** Only available from the archive view.

### 4.3 External ID System

- User sets a base URL in Settings (e.g., `https://linear.app/team/issue/`).
- The external ID field on an activity is appended to the base URL to create a clickable link.
- Supports Jira, Asana, Linear, GitHub Issues, or any URL-based system without tight integration.

### 4.4 Notes Editor

- Rich text editing with live Markdown preview in the editor (similar to Bear/iA Writer style).
- Supported formatting: **bold**, *italic*, headings (H1–H3), bullet lists, numbered lists, links, fenced code blocks with syntax highlighting, GFM checklists (`- [ ]` / `- [x]`).
- Stored as plain Markdown text in the database.
- Implementation: `NSTextView` wrapped in `NSViewRepresentable` with a syntax-highlighting layer that applies `NSAttributedString` attributes as the user types.

### 4.5 Menu Bar

- **Icon + Timer:** SF Symbol that changes based on state — idle (clock), running (play/filled clock), paused (pause). When a session is active, the **elapsed time** (for Work sessions) or **time remaining** (for Rhythm/Timebound sessions) is displayed next to the icon in the menu bar text.
- **Popover** (`.menuBarExtraStyle(.window)`):
  - Current session status with start/pause/stop (or end for Rhythm/Timebound) controls.
  - Quick-start buttons for the 6 most recent activities.
  - Search field to find any activity.
  - "Open Present" button to launch the main window.
  - Session type descriptions are **not** shown here — the popover is kept minimal for quick actions.

### 4.6 Main App Window

Four sections accessible via a sidebar:

1. **Dashboard:** Today's summary (total time, sessions completed), current session display with controls, today's activity breakdown.
2. **Log:** Searchable, filterable list of all past sessions. Filter by activity, tag, session type, date range.
3. **Reports:** Daily/weekly/monthly time summaries per activity. Bar charts (time by activity), pie charts (time distribution). Filterable date ranges. Toggle to include/exclude archived activities. CSV export of filtered data.
4. **Settings/Preferences:** General (external ID base URL), Rhythm Sessions (default duration, break lengths), Notifications (sound on/off), About.

### 4.7 Notifications

- **System notifications** via `UserNotifications` framework when: Rhythm/Timebound timer expires (gentle notification), Time Box start time arrives, break suggestion.
- **In-app alert:** Menu bar icon changes (color/symbol) to signal state changes.
- **Sound:** Optional, configurable in Settings. Uses system default notification sound.

### 4.8 Visual Style

- **Mac-native, clean, modern** — follows Apple's Human Interface Guidelines.
- System adaptive: follows macOS light/dark mode automatically.
- Standard system controls and accent colors.
- Generous whitespace, clear typography, subtle depth via materials and vibrancy.
- Sidebar navigation uses `NavigationSplitView` with proper macOS styling.
- Consistent with native macOS apps like Reminders, Notes, and Calendar in feel.

---

## 5. CLI (`present`)

A full-control CLI built as a separate executable target sharing the `PresentCore` library.

### Commands

| Command | Description |
|---|---|
| `present status` | Show current session (default if no subcommand) |
| `present start "Activity name" [--type work\|rhythm\|timebound\|timebox]` | Start a session for an activity (create if doesn't exist) |
| `present stop` | Stop the current session |
| `present pause` | Pause the current session |
| `present resume` | Resume a paused session |
| `present note "Some text to append"` | Append text to the current activity's notes (Markdown) |
| `present log today` | Show today's logged sessions |
| `present log week` | Show this week's summary |
| `present activities` | List active activities |
| `present activities archive <id>` | Archive an activity |

### Architecture

- CLI commands instantiate `PresentService` (the same `PresentAPI` implementation the UI uses) and call methods on it.
- This guarantees 1:1 parity: if the UI can do it, the CLI can do it, because they share the same API contract.
- After mutations, the CLI sends an IPC notification to the running app via a Unix domain socket at `~/Library/Application Support/Present/present.sock`.
- If the app isn't running, the IPC send fails silently — the CLI works standalone.
- GRDB `ValueObservation` in WAL mode also detects external changes via polling, so the app will update even without the socket (just slightly delayed).

### Installation

- Included in the DMG alongside `Present.app`.
- Users can run `Present.app → Settings → Install CLI` which copies the binary to `/usr/local/bin/present`.
- Or manually copy from DMG.

---

## 6. App Lifecycle (Menu Bar + Window Coexistence)

```swift
@main
struct PresentApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Present", id: "main") {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
```

- `LSUIElement = YES` in Info.plist hides the dock icon by default.
- When the main window opens, switch to `.regular` activation policy (shows dock icon).
- When the main window closes, revert to `.accessory` policy (hides dock icon).
- Use `Window` (not `WindowGroup`) to enforce a single main window instance.

---

## 7. Project Structure

```
Present/
├── .github/
│   └── workflows/
│       └── ci.yml                   # Build + test on PRs and pushes to main
├── plans/
│   └── v1-spec.md                   # This spec, kept up to date alongside the code
├── Package.swift                    # SPM: PresentCore lib + PresentCLI executable
├── Present.xcodeproj/               # Xcode project (app target)
├── Sources/
│   ├── PresentCore/                 # Shared library
│   │   ├── API/
│   │   │   ├── PresentAPI.swift     # Protocol defining ALL user actions
│   │   │   ├── PresentService.swift # Concrete implementation of PresentAPI
│   │   │   └── DTOs.swift           # Input/output types (CreateActivityInput, etc.)
│   │   ├── Models/                  # Activity, Session, Tag, enums, SessionTypeConfig
│   │   ├── Database/                # DatabaseManager, Migrations, Queries/
│   │   ├── IPC/                     # IPCProtocol, IPCServer, IPCClient
│   │   └── Utilities/               # TimeFormatting, CSVExporter, Constants
│   └── PresentCLI/                  # CLI executable
│       ├── PresentCLI.swift         # @main AsyncParsableCommand
│       ├── Commands/                # Log, Start, Stop, Pause, Resume, Status, Note, Activities
│       └── Formatters/              # CLIOutputFormatter
├── PresentApp/                      # macOS app target
│   ├── PresentApp.swift             # @main App struct
│   ├── MenuBar/                     # MenuBarView, QuickStartRow, SearchView, Controls
│   ├── Views/
│   │   ├── Dashboard/               # DashboardView, TodaySummary, CurrentSession
│   │   ├── Log/                     # LogView, LogFilterBar, SessionRow
│   │   ├── Reports/                 # ReportsView, Charts, DateRangePicker, ExportButton
│   │   ├── Settings/                # SettingsView, General, Rhythm, Notifications tabs
│   │   ├── Activities/              # ActivityDetail, ActivityForm, TagEditor
│   │   └── Shared/                  # MarkdownEditor, ExternalIDLink, TimerDisplay
│   └── ViewModels/                  # AppState, DashboardVM, LogVM, ReportsVM
├── Tests/
│   ├── PresentCoreTests/            # Models, Services, Database, IPC unit tests
│   ├── PresentCLITests/             # Command parsing and output tests
│   └── PresentAppUITests/           # Xcode UI tests
├── Scripts/
│   ├── build-dmg.sh                 # Build + sign + create DMG
│   ├── notarize.sh                  # Apple notarization
│   └── install-cli.sh               # Copy CLI to /usr/local/bin
└── README.md
```

---

## 8. Testing Strategy

### Unit Tests (PresentCoreTests) — bulk of testing
- **PresentAPI contract tests:** Every method on `PresentAPI` has tests via `PresentService` with an in-memory database. This is the most important test suite — it validates the shared contract that both UI and CLI depend on.
- **Database:** In-memory `DatabaseQueue` for fast tests. Test migrations, all query helpers, FTS5 search.
- **Session lifecycle:** Start/pause/resume/stop lifecycle, duration calculation, pause accumulation, single-active-session enforcement.
- **Rhythm Session logic:** Timer progression, break suggestions, long break after 4th session, session index tracking.
- **Timebound logic:** Countdown timer, notification on expiry, pause/resume support.
- **Activity management:** CRUD, archive/unarchive, 50-limit enforcement, <10min archive deletion prompt.
- **Reports:** Daily/weekly/monthly aggregation, archived inclusion toggle, CSV output format.
- **IPC:** In-process server/client message round-trip.

### CLI Tests (PresentCLITests)
- Command parsing via `swift-argument-parser` test utilities.
- Output formatting verification.
- Integration tests against in-memory database.

### UI Tests (PresentAppUITests)
- Menu bar popover rendering and session controls.
- Dashboard data display.
- Log filtering and search.
- Reports chart rendering and CSV export.
- Settings persistence.

All tests use **Swift Testing** (`@Test`, `#expect`) — the modern standard for macOS 15+.

### CI: GitHub Actions Workflow

A `.github/workflows/ci.yml` workflow runs on every pull request and push to `main`:

1. **Build check** — `xcodebuild build` compiles the app target to catch compilation errors. This is standard for macOS apps and catches missing imports, type errors, and linker issues that `swift build` alone won't catch for the app target.
2. **Unit tests** — `swift test` runs `PresentCoreTests` and `PresentCLITests` (SPM targets).
3. **App tests** — `xcodebuild test` runs `PresentAppUITests` (Xcode UI test target). Requires a macOS runner with Xcode installed.
4. **CLI build** — `swift build -c release --product present` verifies the CLI binary builds in release mode.

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  build-and-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app
      - name: Build app
        run: xcodebuild build -project Present.xcodeproj -scheme Present -destination 'platform=macOS'
      - name: Run unit tests (SPM)
        run: swift test
      - name: Run UI tests
        run: xcodebuild test -project Present.xcodeproj -scheme Present -destination 'platform=macOS'
      - name: Build CLI (release)
        run: swift build -c release --product present
```

The `macos-15` runner provides macOS Sequoia with Xcode 16, matching our deployment target.

---

## 9. Implementation Phases

### Phase 1: Foundation
- Set up Xcode project + SPM package structure with `Package.swift`
- Implement `PresentCore`: models, `DatabaseManager`, migrations, schema
- Define the `PresentAPI` protocol with all user actions
- Implement `PresentService` (concrete `PresentAPI` implementation)
- Write unit tests for models, database, and the API contract

### Phase 2: App Shell
- Build `PresentApp` with `MenuBarExtra` + `Window` coexistence
- Implement `AppState` with `ValueObservation`
- Build menu bar popover (current session, recent activities, search)
- Build Dashboard view
- Implement session start/pause/stop UI flow

### Phase 3: Full App
- Build Log view with search/filter
- Build Reports view with Swift Charts (bar + pie)
- Build Settings view with all preference tabs
- Implement Markdown notes editor (`NSTextView` wrapper)
- Implement notifications (system + menu bar icon changes)
- CSV export

### Phase 4: CLI + IPC
- Build `PresentCLI` with all commands
- Implement Unix domain socket IPC (server in app, client in CLI)
- Test CLI-to-app data flow end-to-end

### Phase 5: Polish + Distribution
- UI tests
- Code signing, notarization, DMG build scripts
- README.md and local development setup guide
- CLI shell completions

---

## 10. Documentation Deliverables

1. **`plans/v1-spec.md`** — This spec document, kept in the repo alongside the code. Updated as the spec evolves.
2. **`README.md`** — Project overview, features, screenshots placeholder, installation instructions, CLI usage, development setup.
3. **`DEVELOPMENT.md`** — Step-by-step guide for setting up the project locally for development and testing, aimed at both human developers and AI agents. Covers: Xcode version, `swift build`, running tests, running the app, installing the CLI locally.

---

## 11. Verification Plan

1. **Unit tests pass:** `swift test` runs all `PresentCoreTests` and `PresentCLITests`.
2. **App launches:** Menu bar icon appears, popover opens on click, main window opens from popover.
3. **Session lifecycle:** Start a work session from the menu bar, pause it, resume it, stop it. Verify it appears in the Log and Dashboard.
4. **Rhythm Session flow:** Start a 25-min rhythm session, let it expire (or use a debug short timer), verify break suggestion appears, verify session is logged.
5. **Timebound flow:** Start a 10-min timebound session, let it count down to zero, verify gentle notification fires, verify session is logged.
6. **Menu bar timer:** Verify elapsed time shows for Work sessions, time remaining shows for Rhythm/Timebound sessions.
7. **Note appending:** Run `present note "test note"` from CLI, verify text is appended to the current activity's notes in the app.
8. **Activity limit:** Create 50 activities, verify the 51st is rejected with a clear message.
9. **Archive flow:** Archive an activity with <10min tracked, verify deletion prompt. Archive one with >10min, verify it disappears from active list but remains in reports.
10. **CLI round-trip:** Run `present start "Test"` from terminal, verify the app's menu bar updates. Run `present status`, verify output. Run `present stop`, verify session is logged in the app.
11. **Reports:** Verify bar/pie charts render with test data. Export CSV and verify contents.
12. **Search:** Create activities with various titles, search from menu bar and Log view, verify FTS5 results.
13. **External ID:** Set a base URL in Settings, create an activity with an external ID, verify the link is clickable and opens the correct URL.
