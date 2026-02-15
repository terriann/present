# Present — Claude Project Instructions

A macOS time tracking app with menu bar timer, windowed app, and CLI. All backed by local SQLite.

See [README.md](../README.md) for features, installation, and CLI usage.
See [plans/v1-spec.md](../plans/v1-spec.md) for the full V1 specification.
See [DEVELOPMENT.md](../DEVELOPMENT.md) for build, test, and contributor setup.

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
- Views access via `@Environment(AppState.self)` and use `@Bindable var state = appState` for two-way binding.
- GRDB `ValueObservation` for reactive database updates.

### Views (SwiftUI)
- Extract complex subviews into computed properties with `// MARK: -` comments.
- Use SF Symbols for icons. `.monospacedDigit()` for timer displays.
- Standard section order: properties, body, MARK subviews, MARK helpers.
- All tabs and panes align content to the top — use `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)`. Empty states (`ContentUnavailableView`) must also be top-aligned, never vertically centered.

### CLI Commands
- Each command in a separate file under `Commands/`.
- Conform to `AsyncParsableCommand` with static `configuration`.
- Use `CLIServiceFactory.makeService()` to get the service instance.
- Send IPC message after mutations. Print human-friendly output (not JSON).

### Database
- GRDB with WAL mode. `DatabaseManager` handles setup and migrations.
- Named migrations: `"v1-create-tables"`, etc.
- Parameterized queries always — never string interpolation for values.
- FTS5 virtual table for activity search.

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

**Key distinction**: UI layout fixes, visual corrections, and alignment issues are `fix`, not `chore`. If something looks wrong or behaves incorrectly, it's a `fix`.

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
fix(menubar): prevent timer from flickering on pause
refactor(api): extract duration calculation to utility
test(cli): add workflow tests for cancel command
docs(readme): update CLI usage examples
```

When a change spans multiple scopes, use the most significant one. If truly cross-cutting, omit the scope: `refactor: rename session states for clarity`.
