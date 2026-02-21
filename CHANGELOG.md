# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-02-20

Initial release of Present — a simple, intentional time tracking app for macOS.

Requires:

* macOS 15 (Sequoia) or later

### Added

**Sessions**

* feat(session): track work sessions with three types — Work (open-ended), Rhythm (Pomodoro-style cycles with configurable focus/break durations), and Timebound (fixed countdown)
* feat(session): start, pause, resume, stop, and cancel sessions from the menu bar or CLI
* feat(session): pair break duration with focus time in rhythm session options
* feat(api): add backdated session creation for logging sessions after the fact

**Menu Bar**

* feat(menubar): menu bar timer showing elapsed or remaining time at a glance
* feat(menubar): quick-create activity field, row redesign, and inline activity editing
* feat(menubar): activity search with clear button and dynamic label
* feat(menubar): session type picker for selecting Work, Rhythm, or Timebound
* feat(menubar): recent session restart suggestion
* feat(menubar): show activity names in right-click context menu actions
* feat(menubar): SF Symbol icons in right-click context menu
* feat(menubar): timer linger with flash/fade and enhanced recent session display
* feat(menubar): settings gear icon replaces bottom bar buttons

**Activities**

* feat(activity): create and manage activities with names, external IDs, and links
* feat(activity): inline editing for activity name, external ID, and links with hover-to-edit UX
* feat(activity): Cmd+N keyboard shortcut to create a new activity
* feat(activity): action buttons in footer with creation and update timestamps
* feat(activity): archive and unarchive activities

**Notes**

* feat(notes): per-activity markdown notes editor with smart list continuation

**Tags**

* feat(api): tag management with setActivityTags for flexible activity organization

**Dashboard**

* feat(dashboard): today's summary with current session display and activity breakdown
* feat(dashboard): expandable activity breakdown with striped rows
* feat(dashboard): weekly stacked bar chart with weekend background bands

**Reports**

* feat(reports): daily, weekly, and monthly summaries with bar and donut charts
* feat(reports): stacked bar chart breakdown for tag distribution
* feat(reports): external ID breakdown donut chart with interactive legend
* feat(reports): session log consolidated into reports page
* feat(reports): empty state placeholder for periods with no sessions
* feat(reports): CSV export (CLI only, with archive flag)

**CLI**

* feat(cli): full `present-cli <noun> <verb>` command structure — session, activity, tag, report, config
* feat(cli): `session start`, `stop`, `pause`, `resume`, `cancel`, `status`, and `add` (backdated)
* feat(cli): `activity list`, `get`, `add`, `update`, `delete`, `archive`, `unarchive`, `note`, and `tag` subgroup
* feat(cli): `report` command with `--after`/`--before` flags and `--format` (json, text, csv)
* feat(cli): `--field` flag to extract a single top-level field value from JSON output
* feat(cli): auto-generated CLI reference documentation
* feat(cli): input validation with helpful error messages

**Settings**

* feat(settings): configurable week start day
* feat(settings): configurable default Timebound duration
* feat(settings): configurable Rhythm cycle length
* feat(settings): CLI version status with outdated install warning
* feat(settings): About tab with app version
* feat(settings): danger zone with bulk data deletion operations
* feat(settings): data management controls

**Appearance**

* feat(core): dynamic color palette system with Basic and Modern themes
* feat(app): visual palette picker in Settings
* feat(app): app icon — lotus clock design

**Sound**

* feat(sound): semantic sound effects for session lifecycle events (start, stop, cancel, break suggestion)

**Foundation**

* feat(core): PresentCore shared library — models, API protocol, service, database, IPC, utilities
* feat(core): local SQLite database via GRDB with WAL mode and FTS5 full-text search
* feat(ipc): Unix domain socket IPC so CLI mutations are reflected in the running app in real time
* feat(app): user-facing error feedback for failed operations

[Unreleased]: https://github.com/terriann/present/compare/1.0.0...HEAD
[1.0.0]: https://github.com/terriann/present/releases/tag/1.0.0
