# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [0.2.1] - 2026-03-22

### Added
- unified click-to-edit panel in menu bar and dashboard
- double-click row to open inline edit form
- restyle convert section layout
- generate categorized changelog in beta-release script
- show external IDs in activity disclosure rows
- compact time-only pickers in inline edit form (#289)
- refine external ID chart legend layout and data
- replace native date picker with custom calendar grid
- enhance custom tab bar with keyboard shortcuts and a11y
- animate chart mark transitions natively
- add VoiceOver accessibility to all 6 charts
- replace TagPicker with inline tag input
- add "Edit Activity" context menu item to session rows
- collapsible metadata timestamps on detail view
- add Markdown help popover to note headers
- add milestone assignment after issue creation
- group system activities into separate list section
- add /ship skill for push-PR-benchmark workflow
- show tags and external ID in activity list rows
- add 4 palette variants and improve contrast (#52)
- add tabNavigatesFocus param to MarkdownEditor
- collapse activity list while session is running (#145)
- surface ticket IDs and note indicators in session rows
- restore icon+text segmented picker for appearance mode
- upgrade note field to MarkdownEditor with ticket preview
- expand chart palettes from 10 to 15 colors
- auto-extract ticket URL from notes when no link is provided
- add --baseline flag to benchmark against a git ref
- auto-focus primary field when sheets open
- add DatabaseChangeNotifier for GRDB-backed change streams
- add --compare-only mode and improve comparison output
- add hash lookup and markdown output to benchmark comparison
- add benchmark shell script runner
- add repeat action to session context menu
- add hover effect to session control buttons (#67)
- inject active session into pie, tag, and external ID charts (#77)
- inject active session into bar chart and timeline (#77)
- add active session toggle and summary stats (#77)
- add note/link inline editing, remove Edit Note & Link sheet (#86)
- add inline quick-edit for sessions (#86)
- support session editing and simplify type conversion
- auto-switch sort order based on session state
- extract unified ActivitySessionCard shared component
- replace session log with activity breakdown card
- add sort order picker to activity breakdown card
- enable rhythm session conversion in both directions
- add mid-session type conversion UI (phases 3-5)
- wire countdown offset for converted sessions
- add FTS search to session list and reports log
- display and edit session notes and ticket links in UI
- add convertSessionType for mid-session type conversion
- add session notes, ticket links, and ticket ID extraction (#72)
- add keyboard navigation to activity list
- merge search and create into single input
- replace recent list with full scrollable activity list
- add Launch on Login preference
- add Light/Dark/System appearance mode preference
- add daily timeline chart to single-day report

### Changed
- extract shared _classify_commit() to deduplicate parsing
- extract shared release helpers and add production release script
- extract dismissEditForm to deduplicate onSave/onCancel closures
- replace magic number with Constants.spacingCard in convert button
- extract corner radius magic number to Constants
- remove unused SessionTypeConvertLabel struct
- remove unused reduceMotion environment value
- extract timeline gap coalesce threshold to Constants
- remove dead ActivePulseState class
- remove non-date filter controls
- push archived filter to database query
- remove unused exportCSV method and CSVExporter
- batch daily summaries into a single read per range
- extract cornerRadiusSmall constant (4pt)
- push activity filters into recentActivities subquery
- optimize recentActivities query with covering index
- add indexes on session_segment for join and range queries
- extract closed session states into a constant
- drop ORDER BY from set-returning date queries
- add session table indexes to eliminate full table scans
- replace listSessions with lightweight date queries in date picker
- replace deprecated foregroundColor with foregroundStyle
- replace magic number 4 with Constants.spacingTight
- extract weekendBackground constant for chart shading
- remove MonthCell dead code and magic number
- extract alternating row background to shared constant
- extract loadDefaultTimeboundMinutes helper and SessionAction enum
- cache DateFormatter instances in TimeFormatting and ModelJSON
- migrate remaining raw spacing to Constants tokens
- remove unused SessionRow component
- add API facade methods, prevent direct service access
- depend on PresentAPI protocol, not concrete service
- remove externalIdBaseUrl preference
- randomize sample data generation
- use LazyVStack for session card lists
- cache DateFormatter instances in chart views
- reduce pulse animation update rate to ~6.7fps
- centralize chart color map across dashboard and report charts
- convert SessionInlineEditForm to blur-to-save
- remove links form, convert notes to blur-to-save
- remove external ID and link form fields
- extract shared TicketBadge view to eliminate duplication
- use fieldLabel token for form field labels
- replace ad-hoc caption bold with dataLabel token
- unify app and CLI version into Constants.appVersion
- remove unused SessionEditSheet
- extract shared TimeboundDurationField component
- remove full activity scan from refresh hot path
- skip db queries while app is hidden
- replace polling with GRDB ValueObservation
- guard all DataRefreshCoordinator assignments
- extract typeDescription and unify repeat language
- extract pulse animation into shared abstractions
- replace raw SQL with GRDB query builder in listSessions
- extract durationProgress helper in FloatingAlertView
- consolidate search and pickers into single toolbar row
- unify session row layout in ungrouped view
- replace ReportActivityBreakdownCard with shared ActivitySessionCard
- inject calendar into date formatting methods for testability
- extract DayTimelineChart to shared component
- consolidate rhythm selection validation into ViewModifier
- rename view files to use directory-based prefixes
- extract session log, CLI promo, and ReportPeriod to own files
- extract chart sections into own files (#118)
- extract WeeklyChartCard to own file
- extract DayTimelineView, ActivityBreakdownCard, SpinningClockIcon to own files
- centralize navigation via NavigationAction enum
- extract ErrorScene, AppError, and SidebarItem to own files
- extract session calls into SessionManager
- extract data refresh into DataRefreshCoordinator
- extract timer state into TimerManager
- extract zoom state into ZoomManager

### Fixed
- handle empty grep in release.sh previous tag lookup
- fix release.sh guards for bump-then-release workflow
- fix awk newline handling in bump-version.sh
- validate semver format in resolve_version
- clean up tmpdir on interrupt in generate_changelog
- include root commit in changelog when no prior tags exist
- restore HEAD~1 in get_last_tag to avoid empty changelog
- guard "What's Changed" heading and remove nested helper
- rename logger category to reflect shared usage
- replace secondary opacity with primary in convert controls
- fix X button hit target and convert section state
- suppress CancellationError logs in refreshData
- floor ZoomContainer frame dimensions to whole points
- preserve structural identity in ZoomContainer across zoom levels
- use animation nil instead of disablesAnimations on charts
- include active session in day timeline segments
- prevent chart crashes and suppress cancellation alerts
- remove pulse from aggregate charts, fix resize lag
- coalesce sub-90s pause gaps in day timeline
- include active session in reports by default
- remove activePulse from session rows
- refresh coordinator data on view appear
- address PR #295 review feedback
- deduplicate chart legend items by label
- hide row separators around selected list item
- replace toggle switches with filter icon popover
- add .geometryGroup() to session row types
- split and deduplicate external ID badges in session log
- log errors from buffered changes flush instead of swallowing
- remove orphaned MARK header in MonthlySummaryTests
- rotate calendar icon when date picker is expanded
- dismiss inline edit form on click outside (#290)
- make external ID legend rows keyboard and VoiceOver accessible
- add toJSONDict() for TagSummary and ExternalIdSummary
- prevent system activities from storing external IDs or links
- address review feedback on #288
- replace magic spacing numbers with Constants tokens
- harden externalId summary query
- show day annotation only for cross-midnight times in daily view
- sync session logs table with active session toggle
- use session ticketId over activity externalId in chart
- filter stale bar entries to prevent Charts crash
- move new indexes to v11 migration
- cancel in-flight loading task on popover dismiss
- log orphan segment cleanup count in v10 migration
- replace DateFormatter with thread-safe date parsing
- apply localtime modifier to date queries
- refresh dot indicators when navigating months
- add .help() tooltips to period nav buttons
- add tooltip to month nav buttons in calendar grid
- always enable quick jump button in date picker
- add accessibility labels to year nav buttons
- eliminate AttributeGraph cycles in month picker
- resolve AttributeGraph cycles, date picker crash, and refine period nav
- align monthly picker visuals with day/week grid
- expand calendar day cell tap target to full cell area
- extend weekend shading to full chart height
- darken Indigo dark-mode accent to fix black text on segmented control
- surface load errors instead of failing silently
- add heading traits to in-page section headings
- replace raw colors with theme tokens
- use neutral copy for data section and reports empty state
- make Archive the default action in archive confirmation
- restrict socket permissions and log startup errors
- show recovery alert instead of fatalError on DB init failure
- remove force unwraps in infrastructure code
- address accessibility gaps in settings and session card
- replace raw animations with adaptive wrappers in icon views
- remove dead code causing tag flash on activity switch
- guard against nil activity.id in SessionTypePickerSheet
- eliminate force unwraps in protocol and client
- add isHeader trait to modal/sheet heading Text views
- highlight new activity after creation
- scope "Edit Activity" to correct row in grouped view
- restore tag pill colors in detail view
- add SF Symbol icons to inline edit form labels
- pick lowest version milestone as current in issue skill
- add bottom padding to detail header row
- use .dataLabel token for Markdown hint in notes header
- refine activity list row layout and tag colors
- clear search state after activity tap and on dismiss
- apply semantic colors to archived activity actions
- clear selection after deleting activity
- pass force: true when archiving from low-time alert
- advance week loop from weekStart not current
- replace new activity sheet with inline creation
- remove redundant nil coalescing on Bool comparison
- show switch-task bar when session is paused
- remove lotus bloom animation
- remove hover highlight from sidebar nav items
- apply NSApp appearance to fix popover color scheme
- add hover state to rhythm duration pill buttons
- soften edit pill hover to match session type tab style
- add hover state to session type tabs
- validate overlap for active sessions on start time edit
- clear switch-activity state on disappear
- refine switch-activity confirmation UI
- replace switch-activity alert with inline confirmation
- collapse expanded rows on date range change
- switch activities atomically to prevent session loss
- snapshot activity title when switch alert is triggered
- announce expanded/collapsed state on chevron toggle
- use adaptive animation for scroll proxy
- remove icons from session type picker tabs
- play shimmer on manual session stop
- add accent background to active sort button
- group sort buttons in HStack to remove excess spacing
- let Tab move focus instead of inserting tab chars
- chain focus between rhythm duration fields on Return
- commit inline edit on blur instead of cancel
- preserve scroll position on inline session edit
- make inline edit form a persistent editing surface
- stabilize chart visibility guard and pulse animation teardown
- show charts when active session is the only session
- close popover on Escape key press
- wrap main-actor call in deinit with assumeIsolated
- move effectiveAppearance read to @MainActor context
- derive monthly totals from filtered daily breakdowns
- prevent crash when tag chart activities are missing from color domain
- restore auto-focus when opening inline session editor
- intercept Escape in NSTextView to revert or dismiss
- include bar entry activities in chart color domain
- stabilize appearance mode picker
- make blur-to-save reliable in notes editor
- unify chart color assignment across Dashboard and Reports
- split appearance into two sections with icon picker
- eliminate force unwraps in UI and menu bar code
- unify link and note behavior (#159)
- add accessibility labels to custom search TextFields
- pre-select correct target type when converting sessions
- fix focus timing for session inline edit and duration field
- auto-focus search field when Activities tab appears
- auto-focus search field when popover opens
- fix Picker a11y label and use positive toggle framing
- replace onTapGesture with Button in ThemedToggleStyle
- watch full todayActivities array in onChange
- exclude benchmarks from CI and anchor seeder to yesterday
- restore stripe pattern for active session row
- remove includeElapsed from convert views
- refine session control hover treatment
- skip negative-duration segments when summing elapsed time
- guard against socket paths exceeding sun_path limit
- restrict link validation to http/https schemes
- highlight field labels on focus in inline edit form
- polish inline edit form layout and add future-time guard
- update session subcommand count in test
- add accessibility labels to icon-only controls
- standardize activity session card titles
- align search and filter field typography
- allow Escape to clear search in activity card
- restore stacked layout for grouped session rows
- match ungrouped active session row to SessionRow layout
- refine type conversion controls UI (#89)
- require explicit confirmation for all session type conversions
- swap activity row icons to filled variant on hover
- refresh app state on incoming IPC messages
- replace force unwraps with safe guard let in ActivityDetailView
- replace force unwraps in GRDB row decoding
- refresh app state on incoming IPC messages

### Other
- Merge pull request #313 from terriann/fix/bump-version-awk
- Merge pull request #312 from terriann/feat/release-script
- Merge pull request #310 from terriann/feat/0.2-milestone
- Merge pull request #305 from terriann/feat/0.2.0
- Merge pull request #299 from terriann/fix/issue-skill-pm-delegation
- Merge pull request #297 from terriann/feat/0.2.0
- Merge pull request #295 from terriann/feat/0.2.0
- Merge pull request #292 from terriann/feat/0.2.0
- Merge pull request #288 from terriann/feat/0.2.0
- Merge pull request #286 from terriann/feat/0.2.0
- Merge pull request #285 from terriann/feat/0.2.0
- Merge pull request #283 from terriann/feat/0.2.0
- Merge pull request #276 from terriann/feat/0.2.0
- Merge pull request #251 from terriann/feat/0.2.0
- Merge pull request #248 from terriann/feat/0.2.0
- Merge pull request #246 from terriann/feat/0.2.0
- Merge pull request #244 from terriann/feat/0.2.0
- Merge pull request #216 from terriann/feat/0.2.0
- Merge pull request #208 from terriann/feat/0.2.0
- Merge pull request #206 from terriann/feat/0.2.0
- Merge pull request #197 from terriann/feat/0.2.0
- Merge pull request #183 from terriann/feat/0.2.0
- Merge pull request #182 from terriann/feat/0.2.0
- Merge pull request #178 from terriann/feat/0.2.0
- Merge pull request #172 from terriann/feat/0.2.0
- Merge pull request #170 from terriann/feat/0.2.0
- Merge pull request #169 from terriann/feat/benchmark-infra
- Merge pull request #166 from terriann/feat/0.2.0
- Merge pull request #141 from terriann/feat/0.2/refactor

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

[Unreleased]: https://github.com/terriann/present/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/terriann/present/compare/v0.1.0-beta.5...v0.2.1
[1.0.0]: https://github.com/terriann/present/releases/tag/v0.1.0-beta.1
