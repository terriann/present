# Present — Claude Project Instructions

A macOS time tracking app with menu bar timer, windowed app, and CLI. All backed by local SQLite.

See [README.md](../README.md) for features, installation, and CLI usage.
See [plans/v1-spec.md](../plans/v1-spec.md) for the full V1 specification.
See [DEVELOPMENT.md](../DEVELOPMENT.md) for build, test, and contributor setup.
See [docs/patterns.md](../docs/patterns.md) for the UI pattern catalog (canonical examples for cards, charts, rows, editing, controls).

## Voice & Tone

Present speaks like a calm, thoughtful companion — never a demanding boss or a gamified coach. The app is a flexible tool that respects how each person chooses to track and report their time; it never prescribes a "right" way.

- **Patient**: No urgency, no guilt. Time is observed, not judged.
- **Clear**: Plain language, short sentences. Say what you mean without hedging.
- **Warm**: Friendly but not bubbly. Encouraging without cheerleading.
- **Humble**: The app serves the user, not the other way around. No boasting, no superlatives.
- **Educational**: Explain when helpful (tooltips, onboarding, empty states), but step back once the user knows the way.

### Anti-patterns
- No guilt language ("You haven't tracked anything today!")
- No gamification pressure ("Keep your streak going!")
- No corporate speak ("Optimize your productivity workflow")
- No condescension ("It's easy! Just...")
- No false enthusiasm ("Amazing! You tracked 8 hours!")
- No prescriptive workflows ("You should track every task")

### Settings & configuration
Brevity takes a back seat to clarity in settings UI and CLI configuration. Use enough words to remove ambiguity about what a value controls, what the valid options are, and what will change when the user saves. A slightly longer label or description is better than a confused setting.

### Prefer positive framing
Use affirmative conditions: "Show notifications" rather than "Disable notifications", "Include archived" rather than "Don't hide archived". Negative framing (double negatives, "don't", "disable") forces extra mental parsing. Reserve negative phrasing only when the negative action is genuinely the primary concept (e.g., "Mute sounds" where silence is the point).

Apply this voice to all user-facing copy: UI labels, empty states, error messages, notifications, CLI help text, and documentation.

### Action verb conventions

Use consistent verbs for session actions across alerts, buttons, and menus. The verb signals the relationship between what just ended and what happens next.

- **Resume**: The user is returning to an activity after a break. The break interrupted their work; this picks it back up. Example: "Resume Writing" after a rhythm or standalone break completes.
- **Continue**: The user's session completed normally and they may want another round. No interruption occurred; this starts a fresh session of the same kind. Example: "Continue Writing" after a timebound session expires.
- **Start**: Beginning something new or unrelated to the previous context. Example: "Start 5m Break" when offering a break after focus.

Avoid "Restart" for completed sessions — it implies the previous session failed rather than finishing successfully. Reserve "Restart" for genuinely interrupted or cancelled sessions if needed.

For dismiss actions, prefer descriptive labels over mechanical ones. Use "Done for now" (warm, acknowledges autonomy) rather than "Dismiss" (cold, UI jargon). Use specific labels like "End Rhythm Session" when the action has a distinct consequence.

Always say "Launch Present" — never "Open Present." Launch conveys intent and action. Open is generic, passive, and carries connotations of unwrapping something precious. Time is a gift; this app is just a tool.

### Interaction design

Everything should be effortlessly editable through simple interactions that do not distract. These principles make that concrete:

- **Edits happen in place** — prefer inline editing over sheets or navigation when the edit is a single field or short text. The user should feel like they can reach out and change something without leaving their current context.
- **Stay in context** — don't navigate the user away from what they're looking at to make a change. If an edit can happen in a popover, inline field, or the current view, it should.
- **Commit without ceremony** — save on blur, on return, or on dismiss. Don't require explicit save buttons or confirmation for low-risk, easily reversible edits. Reserve confirmation for destructive or irreversible actions (delete, cancel, discard).
- **Signal navigation with ellipsis** — if an action opens a separate window, sheet, or dialog, suffix the label with an ellipsis (`…`). This tells the user the action won't complete inline and another view is coming (e.g., "Export…", "Edit Details…").
- **No hover highlights on standard navigation** — macOS sidebar and list navigation items use a two-state model (unselected / selected) with no hover intermediate. This follows [Apple HIG — Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) and native app conventions (Finder, Mail, Notes, Music, Safari, Xcode). Do not add background-fill hover effects to sidebar items, tab bars, or standard list navigation. Reserve `HoverHighlightModifier` / `.hoverHighlight()` for contexts where hover reveals additional information or controls (e.g., action buttons on list rows, chart tooltips, card interactions). See also [Apple HIG — Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices).

## Architecture

```
SwiftUI Views → @Observable ViewModels → PresentAPI Protocol → PresentService → GRDB/SQLite
                                                ^
CLI Commands ───────────────────────────────────┘
```

- **PresentCore** (SPM library): shared models, API protocol, service, database, IPC, utilities. Consumed by both app and CLI.
- **PresentCLI** (SPM executable): CLI commands via swift-argument-parser, uses PresentCore.
- **PresentApp** (Xcode target via XcodeGen): SwiftUI app with menu bar + windowed UI, uses PresentCore. Not an SPM target.
- Both app and CLI consume the same `PresentAPI` protocol. Adding a feature to the UI requires adding it to `PresentAPI` first.

## Key Patterns

### API Layer (DRY)
- All user actions go through `PresentAPI` protocol — never access the database directly from views, viewmodels, or CLI commands.
- `PresentService` is the single concrete implementation. One place for business logic.
- DTOs use `Input` suffix (`CreateActivityInput`, `UpdateActivityInput`). Result types use descriptive names (`DailySummary`, `ArchiveResult`).

### Models
- Conform to `Codable`, `Sendable`, `Identifiable`, `Equatable`, `FetchableRecord`, `PersistableRecord`.
- Define `databaseTableName` and nested `Columns` enum with static let properties.
- One model per file.

### ViewModels
- `AppState` is `@MainActor @Observable` (Observation framework, not `ObservableObject`/`@Published`).
- `AppState` delegates to focused managers (`ZoomManager`, `TimerManager`, `DataRefreshCoordinator`, `SessionManager`) and forwards their state via computed properties. No manager-to-manager references — AppState coordinates all cross-manager logic. See [docs/architecture.md](../docs/architecture.md) for the full decomposition.
- Views access via `@Environment(AppState.self)` and use `@Bindable var state = appState` for two-way binding.
- GRDB `ValueObservation` for reactive database updates.

### Views (SwiftUI)
- Extract complex subviews into computed properties with `// MARK: -` comments.
- Use SF Symbols for icons. `.monospacedDigit()` for timer displays.
- Standard section order: properties, body, MARK subviews, MARK helpers.
- All tabs and panes align content to the top — use `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)`. Empty states (`ContentUnavailableView`) must also be top-aligned, never vertically centered.
- **File naming**: Feature-scoped view files use their directory as a prefix (`Dashboard/DashboardWeeklyChartCard.swift`, `Activities/ActivitiesDetailView.swift`, `Reports/ReportStackedBarChart.swift`). Generic shared components in `Shared/` skip the prefix (`SpinningClockIcon.swift`, `ChartTooltip.swift`).
- **Pattern catalog**: See [docs/patterns.md](../docs/patterns.md) for the canonical reference of recurring UI patterns (cards, charts, rows, editing, controls). When building new UI, find the matching pattern and follow its canonical example. When a pattern changes or a new one emerges, update the catalog before committing.

### Typography
- Semantic font tokens are defined in `PresentApp/Views/Shared/Typography.swift` as `Font` static properties.
- Use tokens for recurring font treatments: `.font(.timerDisplay)`, `.font(.dataLabel)`, `.font(.controlIcon)`, etc.
- Single text styles without modifiers (`.caption`, `.body`, `.headline`) stay as-is — wrapping adds indirection without semantic value.
- **Display**: `dashboardGreeting`, `periodHeader`, `timerDisplay`, `cardTitle`.
- **Values & Rows**: `statValue`, `durationValue`, `durationDetail`.
- **Data & Charts**: `dataLabel` (bold caption), `dataValue` (mono caption), `dataBoldValue` (bold+mono caption).
- **Icons**: `controlIcon` (.title), `controlIconSmall` (.title2).
- **Code**: `codeBlock` (mono body), `codeCaption` (mono caption).
- To add a new token: add a static property to the `Font` extension in `Typography.swift` with a doc comment explaining its semantic purpose.

### Time Display
- **Duration format**: `Xh Ym` (e.g., "2h 15m") or `Xm` for sub-hour. Use `TimeFormatting.formatDuration(seconds:)`.
- **Timer format**: `H:MM:SS` or `M:SS` for the live timer display. Use `TimeFormatting.formatTimer(seconds:)`.
- **Round at session level**: The database stores exact seconds, but UI durations are floored to the minute. When summing durations across sessions (activity totals, daily totals), round each session to the minute first using `TimeFormatting.floorToMinute(_:)`, then sum. This ensures the total matches the individually displayed values.
- **Cross-midnight times**: When a time falls on a different calendar day than the reference context, append the day name in parentheses (e.g., "11:23 PM (Saturday)"). Use `TimeFormatting.formatTime(_:referenceDate:)`.
- **Rhythm durations**: Use `RhythmOption.displayLabel` for compact format (`25m / 5m`) and `RhythmOption.settingsLabel` for settings/configuration (`25 minute focus / 5 minute break`).
- **UI vs CLI precision**: The UI rounds each session to the nearest minute before summing (via `TimeFormatting.floorToMinute`), so totals always match the individually displayed values. The CLI returns exact seconds and sums unrounded values. This is intentional — the UI prioritizes readability, the CLI prioritizes precision. Never "fix" the CLI to match the UI rounding or vice versa.

### Spacing & Layout
- **Page** (`Constants.spacingPage`, 20pt): Main content areas — ScrollView roots in Dashboard, ActivityDetail, Reports, and sheets.
- **Toolbar** (`Constants.spacingToolbar`, 16pt): Toolbars and navigation bars.
- **Card** (`Constants.spacingCard`, 12pt): Card/GroupBox internals, menu bar sections, chart cards.
- **Compact** (`Constants.spacingCompact`, 8pt): Dense UI — menu bar items, pills, badges, inline spacing.
- **Tight** (`Constants.spacingTight`, 4pt): Inner wrappers inside GroupBox content.
- **System default** (`.padding()`): Forms and system controls (e.g., SettingsView tabs).
- New code should use `Constants.spacing*` values. Existing code migrates incrementally.

### CLI Commands
- **Noun-verb pattern**: All commands follow `present-cli <noun> <verb>` (e.g., `present-cli session start`, not `present-cli start`).
- **Standard CRUD verbs**: `add` (create), `get` (read one), `list` (read many), `update` (modify), `delete` (remove). Domain-specific verbs for specialized actions: `start`, `search`, `archive`, `unarchive`, `note`.
- **SALR pattern for sub-resources**: `activity tag` is a subcommand group with `add`, `remove`, `set`, `list` — not flat `tag`/`untag` verbs.
- **Session `current` group**: Active session commands (`status`, `stop`, `pause`, `resume`, `cancel`) live under `session current`. `session start` stays top-level. `session current` defaults to `status`.
- **`session add`**: Creates backdated completed sessions. Takes `--started-at`/`--ended-at` (ISO8601), validates overlap.
- **Unified `report`**: Single leaf command with `--after`/`--before` flags (defaults to today). No subcommands.
- **File structure**: `Commands/<Noun>/<Noun><Verb>Command.swift`. Each noun group has a parent `<Noun>Command.swift` that registers subcommands. Nested groups use `<Noun><Group>Command.swift` (e.g., `SessionCurrentCommand.swift`).
- **Naming**: Structs are `<Noun><Verb>Command` (e.g., `SessionStartCommand`) or `<Noun><Group><Verb>Command` (e.g., `SessionCurrentStatusCommand`). File name matches struct name.
- **Adding a new command**: Create file in `Commands/<Noun>/`, register in `<Noun>Command.swift`'s `subcommands` array.
- **Output format**: Include `@OptionGroup var outputOptions: OutputOptions` for `-f`/`--format` support (json, text, csv). **Default is `json`**. Not all formats apply to every command — throw `ExitCode.failure` for unsupported formats.
- **`--field` option**: Extracts a single top-level field value from the response. With `-o json` (default), prints the raw value. With `-o text`, prints the human-formatted value. Not supported with `-o csv` or list output. Exits with failure if the field doesn't exist.
- **Model serialization**: Use `toJSONDict()` and `toTextFields()` extensions on models (`Activity`, `Session`, `Tag`, summary types) defined in `ModelJSON.swift`. Commands should use these for consistent field names across the CLI. Action-specific fields (e.g., `deleted: true`) are merged into the model dict.
- **JSON nesting**: A session contains its activity as a nested object (`"activity": {...}`). Top-level objects use `"id"`; nested objects use prefixed keys (`"activityId"`, `"tagId"`). Use `toNestedJSONDict()` when embedding a model inside another response.
- **Service**: Use `CLIServiceFactory.makeService()` to get the service instance.
- **IPC**: Send IPC message after mutations (`IPCClient().send(.eventName)`). Read-only commands skip IPC.
- **Parameters**: `--after`/`--before` for dates (YYYY-MM-DD, inclusive), `--page` for pagination (1-indexed, max 100/page), `--type` for enum filters.
- Conform to `AsyncParsableCommand` with static `configuration`.
- **Versioning**: App and CLI share a single version in `Constants.appVersion` (`Sources/PresentCore/Utilities/Constants.swift`). The bump script (`Scripts/bump-version.sh`) updates it automatically at release time. **Whenever a change affects CLI commands, service methods, the `PresentAPI` protocol, or the database schema, do all three:**
  1. Regenerate `docs/cli-reference.md` before committing: `bash Scripts/generate-cli-docs.sh` — then include the updated file in the commit.
  2. Remind user to rebuild the app in Xcode so the new version string appears in the About tab.
  3. Remind user to reinstall the CLI: _"The CLI at `/usr/local/bin/present-cli` is still the old version — run `swift build -c release && cp .build/release/present-cli /usr/local/bin/present-cli` to pick up these changes."_

### Database
- GRDB with WAL mode. `DatabaseManager` handles setup and migrations.
- Named migrations: `"v1-create-tables"`, etc.
- Parameterized queries always — never string interpolation for values.
- FTS5 virtual table for activity search.
- See `docs/database.md` for schema reference, file location, and debug queries.

### IPC
- Unix domain socket at `~/Library/Application Support/Present/present.sock`.
- `IPCMessage` enum (Codable, Sendable) for event types.
- CLI sends fire-and-forget. App listens in background. Fails silently if app isn't running.

### Testing
- **Swift Testing** framework (`@Suite`, `@Test`, `#expect`) — not XCTest.
- All tests use in-memory SQLite via `DatabaseManager(inMemory: true)`.
- Each suite has a `makeService()` helper.
- Test names describe behavior. Group with `// MARK: -` comments.

### Error Handling
- `PresentError` enum with `LocalizedError` conformance.
- Services throw, CLI catches and prints `localizedDescription`, SwiftUI catches in Task.

### Concurrency
- Swift 6 strict concurrency. All models and DTOs conform to `Sendable`.
- `@unchecked Sendable` used sparingly for thread-safe classes with locks.
- All service methods are `async throws`.

### Constants
- Magic numbers extracted to `Constants.swift` with `public static let`.
- Preference keys in `PreferenceKey` enum with static lets.

### Sound Design
- Four semantic sounds: `.approach` (attention needed), `.blow` (activation/beginning), `.dip` (negative/destructive), `.shimmer` (positive).
- Always use `SoundManager.shared.play(.effect)` — never load audio files directly.
- Sounds reinforce UX but are not excessive — reserved for **meaningful state transitions** only.
- Good: session start/resume, session complete, cancel/discard, break suggestions.
- Bad: button clicks, tab switches, selection changes, hover states, opening/closing panels.
- Controlled by `soundEffectsEnabled` preference (separate from notification sounds).

### Colors
- `ThemeManager` is a `@MainActor @Observable` class (`Sources/PresentCore/Utilities/Color+Theme.swift`), guarded by `#if canImport(SwiftUI)`.
- Injected into the SwiftUI environment. Views access via `@Environment(ThemeManager.self) private var theme`.
- Seven tokens: `primary` (brand identity), `accent` (interactive elements), `success`, `warning`, `alert`, `constantBlack`, `constantWhite`.
- **`primary` vs `accent`**: In basic palette these are identical (brand blue). In modern palette, primary is navy and accent is blue. Use `theme.accent` for interactive elements (buttons, selections, links). Use `theme.primary` for brand identity/chrome.
- Two palettes available: **basic** (current brand colors) and **modern** (navy/teal/coral/purple).
- `ColorPalette` enum (`Sources/PresentCore/Models/ColorPalette.swift`) stores palette choice. Persisted via `PreferenceKey.colorPalette`.
- All tokens adapt between light and dark mode automatically.
- `AccentColor` asset catalog entry (`PresentApp/Resources/Assets.xcassets/AccentColor.colorset/`) sets the system accent color app-wide.
- **`constantBlack` / `constantWhite`**: Palette-independent colors for UI elements that must stay fixed (e.g. terminal mock backgrounds, chart grid lines, weekend shading). Use instead of raw `Color.black` / `Color.white`.
- **Never use raw colors** (`.red`, `.green`, `.orange`, `.blue`, `Color.black`, `Color.white`, `Color.accentColor`) in views. Use the appropriate `theme.*` token.
- `.secondary` (system) is fine for non-semantic muted text — no theme wrapper needed.
- To add a new palette: add a case to `ColorPalette`, add color definitions in `ThemeManager`'s computed properties.

### Swift Safety
- **Never force unwrap** (`!`) optionals. Use `if let`, `guard let`, `??` (nil coalescing), or `compactMap` instead. Force unwraps compile fine but crash at runtime when the value is `nil` — use safe alternatives that handle the nil case gracefully.

### Animations & Reduce Motion
- **Never use raw `.animation()` or `withAnimation()`** — use the adaptive wrappers in `PresentApp/Views/Shared/AdaptiveAnimation.swift`.
- Declarative: `.adaptiveAnimation(_:reduced:value:)` — drop-in replacement for `.animation(_:value:)`.
- Imperative: `withAdaptiveAnimation(_:reduced:_:)` — drop-in replacement for `withAnimation(_:_:)`.
- Both default `reduced` to `.linear(duration: 0.15)`. Override for longer animations (e.g., `reduced: .linear(duration: 0.6)` for a 2s fadeout).
- **Auto-rotating content** (carousels, timed transitions): disable the rotation entirely when reduce motion is on. Read `@Environment(\.accessibilityReduceMotion)` and guard the timer callback.
- `.contentTransition(.numericText())` respects reduce motion automatically — no wrapper needed.

### Accessibility (VoiceOver)
- **Icon-only buttons** must have `.accessibilityLabel("Description")`. `.help()` provides a tooltip but is not announced by VoiceOver — always add both.
- **Decorative icons** (paired with a text label, or redundant with nearby content like a status message) get `.accessibilityHidden(true)`.
- **Buttons with text labels** need no extra accessibility work — SwiftUI derives the accessible name from the label content automatically.
- When adding any new icon or image-only control, decide: is it interactive or decorative? Apply the appropriate modifier before committing.

### Scripts

- **`Scripts/preview-icons.sh`**: Renders Icon Composer (`.icon`) files at all standard macOS sizes into an HTML preview. Uses `ictool` (bundled with Xcode's Icon Composer). Renders Default and Dark renditions at 16–512pt (1x and 2x). When multiple files are passed, includes a side-by-side comparison section. Opens the HTML in the default browser.
  ```bash
  bash Scripts/preview-icons.sh local-assets/*.icon
  bash Scripts/preview-icons.sh file1.icon file2.icon file3.icon
  ```
  Note: `ictool` does not add the transparent margin macOS applies to Dock/Finder icons — previews will appear slightly larger than in production.

- **`Scripts/generate-cli-docs.sh`**: Regenerates `docs/cli-reference.md` from the CLI binary. Run after any CLI command change.

## Pull Requests
- Default PR base branch is `main` unless otherwise specified.
- **Never commit directly to `main`.** Before making any commit, check the current branch. If on `main`, stop and ask which feature branch to use (or whether to create a new one). This applies even for small fixes.

## Conventional Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) format: `type(scope): description`

### Types

| Type | When to use |
|---|---|
| `feat` | New user-facing functionality or behavior that didn't exist before |
| `fix` | Corrects broken behavior, layout issues, visual bugs, or data errors |
| `refactor` | Restructures code without changing behavior (renames, extractions, cleanup) |
| `style` | Code formatting only (whitespace, semicolons, linting). No logic changes |
| `perf` | Improves performance without changing functionality |
| `test` | Adds or updates tests. No production code changes |
| `docs` | Documentation only (README, claude.md, code comments) |
| `build` | Build system, dependencies, XcodeGen, Package.swift |
| `ci` | CI/CD pipeline and GitHub Actions changes |
| `chore` | Maintenance that doesn't fit above (gitignore, config files, tooling setup) |

**Key distinction**: UI layout fixes, visual corrections, and alignment issues are `fix`, not `chore`. If something looks wrong or behaves incorrectly, it's a `fix`. Note: the `chore` commit type maps to the `type/chore` GitHub label.

**When unsure** whether a change is `feat` or `fix`, ask before committing.

### Scopes

| Scope | Area |
|---|---|
| `core` | PresentCore shared library (models, utilities, constants) |
| `api` | PresentAPI protocol and PresentService |
| `cli` | CLI commands, parsing, output formatting |
| `app` | SwiftUI app shell, lifecycle, window management |
| `menubar` | Menu bar popover, timer display, quick-start |
| `dashboard` | Dashboard view and today's summary |
| `log` | Log view, filtering, search |
| `reports` | Reports, charts, CSV export |
| `db` | Database manager, migrations, queries, FTS5 |
| `ipc` | Unix domain socket server/client |
| `session` | Session lifecycle (start/pause/resume/stop/cancel) |
| `activity` | Activity CRUD, archiving, limits |
| `notes` | Markdown notes editor |
| `tags` | Tag management |
| `notifications` | System notifications |
| `sound` | SoundManager and sound effects |
| `settings` | Preferences and settings views |
| `appstate` | AppState ViewModel, observation |
| `ci` | GitHub Actions, workflows |
| `build` | Build scripts, XcodeGen, Package.swift |

### Examples

```
feat(session): add rhythm session break suggestions
feat(cli): add session add command for backdated sessions
fix(menubar): prevent timer from flickering on pause
refactor(api): extract duration calculation to utility
refactor(cli): restructure activity tag as SALR subcommand group
test(cli): add workflow tests for cancel command
docs(readme): update CLI usage examples
```

When a change spans multiple scopes, use the most significant one. If truly cross-cutting, omit the scope: `refactor: rename session states for clarity`.

## Filing Issues & Project Management

**Always delegate bug reports, feature requests, triage, and milestone planning to the project manager agent** (`.claude/agents/project-manager.md`). Do not create GitHub issues directly.

This applies when the user:
- Reports a bug or unexpected behavior
- Requests a new feature or enhancement
- Asks to "file an issue", "create a ticket", or "document this bug"
- Describes a problem that should be tracked rather than fixed immediately
- Asks to triage, audit, size, or prioritize issues
- Asks to plan or propose milestones

The project manager agent handles issue creation (via the `/issue` skill), triage, labeling, sizing, and milestone management.

### Milestones

- **Future** — Placeholder milestone for far-future ideas and explorations. Not tied to a release. Assign issues here to keep the backlog filtered to actionable work. Do not use for anything with a concrete timeline.

## Code Review & Codebase Audits

**Always delegate codebase audits, code quality reviews, and architecture assessments to the code-reviewer agent** (`.claude/agents/code-reviewer.md`).

This applies when the user:
- Asks for a codebase audit or code review
- Wants to check for SOLID, SoC, or DRY violations, force unwraps, or security concerns
- Asks to "review the code", "audit the codebase", or "check code quality"
- Wants a pre-release quality check

The code-reviewer agent explores the codebase, produces categorized findings, and delegates issue filing to the project manager agent. It does not implement fixes.
