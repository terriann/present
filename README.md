# Present

A simple, intentional way to track time on macOS. Present combines a menu bar
timer with a full windowed app and a CLI tool, all backed by a local SQLite
database.

[![CI](https://github.com/terriann/present/actions/workflows/ci.yml/badge.svg)](https://github.com/terriann/present/actions/workflows/ci.yml)

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [From Source](#from-source)
- [Quick Start](#quick-start)
- [CLI Usage](#cli-usage)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Menu bar timer** -- Start, pause, and stop sessions from the menu bar.
  See elapsed or remaining time at a glance.
- **Four session types** -- Work (open-ended), Rhythm (Pomodoro-style cycles
  with breaks), Timebound (fixed countdown), and Time Box (planned
  start/end).
- **Main app window** -- Dashboard with today's summary, searchable session
  log, reports with charts, and activity management.
- **CLI tool** -- Full control from the terminal. Start sessions, append
  notes, view logs, and manage activities. Everything the app can do.
- **Markdown notes** -- Rich notes editor with live syntax highlighting for
  each activity.
- **Tags and external IDs** -- Organize activities with tags and link to
  external tools (Jira, Linear, GitHub Issues, etc.).
- **Reports and CSV export** -- Daily, weekly, and monthly summaries with
  bar and pie charts. Export to CSV.
- **System notifications** -- Gentle alerts when timers complete and break
  suggestions after rhythm sessions.
- **Local and private** -- All data stored locally in SQLite via
  [GRDB](https://github.com/groue/GRDB.swift). No accounts, no cloud sync.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ (for building from source)

## Installation

### From Source

```bash
git clone https://github.com/terriann/present.git
cd present

# Build and run the CLI
swift build
.build/debug/present --help

# Generate Xcode project and build the app
brew install xcodegen  # if not installed
xcodegen generate
open Present.xcodeproj
```

## Quick Start

Once the app is running, you can start tracking time immediately:

1. **From the menu bar:** Click the Present icon, select an activity (or
   create one), and start a session.
2. **From the CLI:** Run `present start "My Task"` to begin a work session.
   The activity is created automatically if it does not exist.
3. **View your day:** Open the main window for a dashboard summary, or run
   `present log today` in the terminal.

## CLI Usage

```text
present                           # Show current session status (default)
present status                    # Same as above (explicit status command)
present start "Activity name"     # Start a work session (creates activity if needed)
present start "Task" --type rhythm --minutes 25
present stop                      # Stop the current session
present pause                     # Pause the current session
present resume                    # Resume a paused session
present cancel                    # Cancel without logging
present note "Some text"          # Append text to current activity's notes
present log                       # Show today's sessions (default)
present log today                 # Show today's sessions
present log week                  # Show this week's summary
present activities                # List active activities (default)
present activities list           # List active activities
present activities list --include-archived
present activities archive <id>   # Archive an activity
```

Session types: `work` (default), `rhythm`, `timebound`, `timebox`.

Run `present --help` or `present <command> --help` for full option details.

The CLI shares the same SQLite database as the app. Changes made in the CLI
are reflected in the app (and vice versa) via IPC notifications and database
polling.

## Architecture

```text
SwiftUI Views -> @Observable ViewModels -> PresentAPI Protocol -> PresentService -> GRDB/SQLite
                                                  ^
CLI Commands ─────────────────────────────────────┘
```

Both the app and CLI consume the same `PresentAPI` protocol, which
guarantees feature parity. Key architectural decisions:

- **Swift 6** with strict concurrency checking enabled.
- **GRDB** for SQLite with WAL mode, enabling concurrent reads and writes
  between the app and CLI.
- **`@Observable`** (Observation framework) for SwiftUI view models instead
  of the older `ObservableObject`/`@Published` pattern.
- **Swift Testing** framework for all test suites (not XCTest).
- **XcodeGen** generates the Xcode project from `project.yml`. The generated
  `.xcodeproj` is gitignored.
- **Unix domain socket IPC** allows the CLI to notify the running app of
  data changes in real time.

See [plans/v1-spec.md](plans/v1-spec.md) for the full specification.

## Project Structure

```text
present/
├── Sources/
│   ├── PresentCore/            # Shared library (models, API, database, IPC)
│   │   ├── API/                # PresentAPI protocol, PresentService, DTOs
│   │   ├── Database/           # DatabaseManager, migrations, schema
│   │   ├── IPC/                # Unix domain socket server/client
│   │   ├── Models/             # GRDB record types (Activity, Session, Tag, etc.)
│   │   └── Utilities/          # Time formatting, CSV export, constants
│   └── PresentCLI/             # CLI executable (swift-argument-parser)
│       └── Commands/           # One file per CLI command
├── PresentApp/                 # macOS app (SwiftUI, not an SPM target)
│   ├── ViewModels/             # AppState (@Observable)
│   ├── MenuBar/                # Menu bar popover and session controls
│   ├── Views/                  # Dashboard, Log, Reports, Activities, Settings
│   │   └── Shared/             # Reusable components (MarkdownEditor, etc.)
│   └── Notifications/          # System notification manager
├── Tests/
│   ├── PresentCoreTests/       # Service, IPC, model, and database tests
│   └── PresentCLITests/        # CLI workflow and integration tests
├── Scripts/                    # Build, notarize, and install scripts
├── plans/                      # Specification documents
├── Package.swift               # SPM manifest (PresentCore + PresentCLI)
└── project.yml                 # XcodeGen project definition
```

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup instructions, building,
testing, and contributor workflows.

The project has 68 tests across 5 test suites (in 2 test targets) covering
the service layer, IPC, models, database, and CLI workflows. All tests use
in-memory SQLite databases for fast, isolated execution.

```bash
swift test   # Run all tests
```

## Contributing

1. Fork the repository and create a feature branch.
2. Run `xcodegen generate` after cloning or pulling changes.
3. Make your changes and verify all tests pass with `swift test`.
4. Open a pull request against `main`.

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed setup and coding
conventions.

## License

All rights reserved.
