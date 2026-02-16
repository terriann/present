# Development Guide

Guide for setting up Present for local development, building, testing, and
contributing.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Building](#building)
  - [CLI (via SPM)](#cli-via-spm)
  - [App (via Xcode)](#app-via-xcode)
- [Testing](#testing)
  - [Test Suites](#test-suites)
- [CI](#ci)
- [Project Layout](#project-layout)
- [Database](#database)
- [IPC](#ipc)
- [Code Style](#code-style)
- [Distribution](#distribution)
- [Versioning](#versioning)
- [Common Tasks](#common-tasks)
  - [Adding a New CLI Command](#adding-a-new-cli-command)
  - [Adding a New API Method](#adding-a-new-api-method)
  - [Adding a New View](#adding-a-new-view)
  - [Regenerating the Xcode Project](#regenerating-the-xcode-project)
- [Contributing Workflow](#contributing-workflow)
- [Troubleshooting](#troubleshooting)

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| macOS | 15.0+ (Sequoia) | -- |
| Xcode | 16.0+ | Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/) |
| Swift | 6.0+ | Included with Xcode |
| XcodeGen | Latest | `brew install xcodegen` |

## Setup

```bash
# Clone the repo
git clone https://github.com/terriann/present.git
cd present

# Resolve SPM dependencies (fetches GRDB, swift-argument-parser, swift-testing)
swift package resolve

# Generate the Xcode project
xcodegen generate
```

## Building

### CLI (via SPM)

```bash
swift build                               # Debug build
swift build -c release --product present-cli  # Release build
.build/debug/present-cli --help               # Run CLI
```

### App (via Xcode)

```bash
xcodegen generate                    # Regenerate after changing project.yml
open Present.xcodeproj               # Open in Xcode, then Cmd+R to run
```

Or from the command line:

```bash
xcodebuild build \
  -project Present.xcodeproj \
  -scheme Present \
  -destination 'platform=macOS'
```

## Testing

All tests use the [Swift Testing](https://github.com/swiftlang/swift-testing)
framework (not XCTest). Tests run against in-memory SQLite databases, so
they execute quickly and do not affect your local data.

```bash
# Run all tests (68 tests across 2 test targets)
swift test

# Run a specific test suite
swift test --filter PresentServiceTests
swift test --filter IPCTests
swift test --filter CLITests
swift test --filter ModelTests
swift test --filter DatabaseManagerTests
```

### Test Suites

| Target | Suite | Tests | Covers |
|--------|-------|------:|--------|
| PresentCoreTests | PresentServiceTests | 32 | Activity CRUD, sessions, notes, tags, reports, CSV export |
| PresentCoreTests | IPCTests | 8 | Message serialization, client/server round-trip |
| PresentCoreTests | ModelTests | 8 | Record defaults, session types, time formatting |
| PresentCoreTests | DatabaseManagerTests | 4 | Schema creation, migrations, default preferences |
| PresentCLITests | CLITests | 16 | CLI workflows, error cases, session type validation |

## CI

The project uses GitHub Actions for continuous integration. The workflow runs
on macOS 15 runners on every push to `main` and on all pull requests.

CI steps:

1. Select Xcode 16
2. Generate the Xcode project with XcodeGen
3. Build the macOS app via `xcodebuild`
4. Run all SPM tests via `swift test`
5. Build the CLI in release mode

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the full
configuration.

## Project Layout

- **`Package.swift`** -- SPM manifest. Defines `PresentCore` (library),
  `PresentCLI` (executable), and test targets.
- **`project.yml`** -- XcodeGen spec. Generates `Present.xcodeproj` (which
  is gitignored).
- **`Sources/PresentCore/`** -- Shared library consumed by both the app
  and CLI.
  - `API/` -- `PresentAPI` protocol, `PresentService` implementation, and
    DTOs.
  - `Models/` -- GRDB record types (`Activity`, `Session`, `Tag`,
    `Preference`, `SessionType`, etc.).
  - `Database/` -- `DatabaseManager`, migrations, schema.
  - `IPC/` -- Unix domain socket server/client for CLI-to-app notifications.
  - `Utilities/` -- Time formatting, CSV export, constants.
- **`Sources/PresentCLI/`** -- CLI entry point, `CLIServiceFactory`, and
  commands (one file per command in `Commands/`).
- **`PresentApp/`** -- macOS app target (not an SPM target, built via Xcode).
  - `PresentApp.swift` -- `@main` App struct with MenuBarExtra + Window
    scenes.
  - `ViewModels/` -- `AppState` (the core `@Observable` view model).
  - `MenuBar/` -- Menu bar popover views.
  - `Views/` -- Dashboard, Log, Reports, Activities, Settings, and shared
    components.
  - `Notifications/` -- `NotificationManager` for system notifications.
- **`Tests/`** -- Swift Testing test suites (see [Testing](#testing)).
- **`Scripts/`** -- Shell scripts for building, notarizing, and installing
  (`build-dmg.sh`, `notarize.sh`, `install-cli.sh`).

## Database

Present uses SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
with WAL mode for concurrent read/write access between the app and CLI.

- **Production path:** `~/Library/Application Support/Present/present.db`
- **Tests:** In-memory `DatabaseQueue` (no file I/O).

To inspect the database:

```bash
sqlite3 ~/Library/Application\ Support/Present/present.db ".tables"
sqlite3 ~/Library/Application\ Support/Present/present.db "SELECT * FROM activity;"
```

The schema includes five tables: `activity`, `session`, `tag`,
`activity_tag`, and `preference`. An FTS table (`activity_fts`) supports
full-text search on activity titles.

## IPC

The app runs a Unix domain socket server at
`~/Library/Application Support/Present/present.sock`. When the CLI performs a
mutation (start, stop, pause, etc.), it sends a JSON message over this socket
so the app can refresh immediately.

If the app is not running, the CLI works standalone. IPC send fails silently.
The app also polls the database every 2 seconds as a fallback.

## Code Style

Present uses **Swift 6** with **strict concurrency checking** enabled. Follow
these conventions when contributing:

- **Concurrency:** All shared mutable state must be concurrency-safe. Use
  actors or `@MainActor` where appropriate.
- **SwiftUI:** Use the Observation framework (`@Observable`) for view models
  instead of `ObservableObject`/`@Published`.
- **Testing:** Use the Swift Testing framework (`import Testing`, `@Test`,
  `#expect`). Do not use XCTest.
- **Database records:** Model types conform to GRDB's `FetchableRecord`,
  `PersistableRecord`, and `Codable`.
- **Naming:** Follow Swift API Design Guidelines. CLI commands use
  lowercase with hyphens (e.g., `present-cli activities list`).
- **File organization:** One type per file. CLI commands live in
  `Sources/PresentCLI/Commands/`, one file per command.
- **Error handling:** Prefer typed errors. CLI commands surface user-facing
  error messages via `ValidationError`.

## Distribution

```bash
# Build signed DMG (set SIGNING_IDENTITY for real signing)
./Scripts/build-dmg.sh

# Notarize (requires Apple Developer credentials)
APPLE_ID=you@example.com TEAM_ID=XXXXX APP_PASSWORD=xxxx ./Scripts/notarize.sh

# Install CLI locally
./Scripts/install-cli.sh
```

## Versioning

Present tracks two version identifiers in `PresentApp/Info.plist`:

- **`CFBundleShortVersionString`** (currently `1.0`) -- The user-facing
  marketing version, following
  [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).
- **`CFBundleVersion`** (currently `1`) -- The internal build number, an
  integer that must always increment. macOS uses this to determine whether
  a build is newer, and it is required by the App Store and TestFlight.

### When to increment

- **Marketing version** (`CFBundleShortVersionString`): Bump according to
  semver. MAJOR for breaking changes, MINOR for new features, PATCH for bug
  fixes.
- **Build number** (`CFBundleVersion`): Increment with every release build,
  regardless of version bump type. It must never go backwards. If you ship
  v1.2.0 as build 5, the next release (even v1.2.1) must be build 6 or
  higher.

### Guidelines

- Never decrement the build number.
- Update both values together at release time.
- During development, the version in `Info.plist` reflects the *next*
  planned release.
- Git tags use the format `v1.2.0` (prefixed with `v`) and should match the
  marketing version.

> [!NOTE]
> A version bump script (`Scripts/bump-version.sh`) is planned to automate
> updates to both values. See [GitHub issue #3](https://github.com/terriann/present/issues/3).

## Common Tasks

### Adding a New CLI Command

1. Create `Sources/PresentCLI/Commands/YourCommand.swift`.
2. Add it to the `subcommands` array in
   `Sources/PresentCLI/PresentCLI.swift`.
3. If it mutates data, call `IPCClient().send(.dataChanged)` at the end.
4. Add tests in `Tests/PresentCLITests/CLITests.swift`.

### Adding a New API Method

1. Add the method signature to
   `Sources/PresentCore/API/PresentAPI.swift`.
2. Implement it in `Sources/PresentCore/API/PresentService.swift`.
3. Add tests in `Tests/PresentCoreTests/PresentServiceTests.swift`.
4. Both the app and CLI can now use the new method.

### Adding a New View

1. Create the SwiftUI view file in the appropriate subdirectory under
   `PresentApp/Views/` (e.g., `Dashboard/`, `Settings/`).
2. Wire it into `ContentView.swift` or the relevant parent view.
3. If the view needs data, add methods to `AppState` in
   `PresentApp/ViewModels/AppState.swift`.
4. Run `xcodegen generate` to pick up the new file.

### Regenerating the Xcode Project

After modifying `project.yml` or adding new source files to `PresentApp/`:

```bash
xcodegen generate
```

The generated `Present.xcodeproj/` is gitignored.

## Contributing Workflow

1. Fork the repository and clone your fork.
2. Create a feature branch from `main`.
3. Follow the [Setup](#setup) steps to prepare your environment.
4. Make changes, keeping each PR focused on a single logical change.
5. Run `swift test` and verify all 68 tests pass.
6. If you added files to `PresentApp/`, run `xcodegen generate` and confirm
   the app builds.
7. Open a pull request against `main`. CI will run automatically.

## Troubleshooting

### `xcodegen generate` fails

Make sure XcodeGen is installed (`brew install xcodegen`) and you are running
the command from the project root.

### `swift build` fails with dependency errors

Try resolving dependencies first:

```bash
swift package resolve
```

If the issue persists, clear the build cache:

```bash
swift package clean
swift package resolve
swift build
```

### CLI cannot connect to the app (IPC)

The CLI sends IPC messages to
`~/Library/Application Support/Present/present.sock`. If the app is not
running, these messages are silently dropped, which is expected. The CLI
still works fully without the app.

If the app is running but not reflecting CLI changes, try restarting the app.
The app also polls the database every 2 seconds as a fallback.

### Database locked errors

Present uses WAL mode to allow concurrent access. If you see locked errors,
make sure you are not running `sqlite3` with a write transaction while the
app or CLI is also writing.
