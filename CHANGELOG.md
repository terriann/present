# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-03-22

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
- add findOrCreateTag to prevent duplicate tag errors
- add duplicate check and cross-linking to issue skill
- surface full version string including pre-release identifiers
- expand settings gear into labeled pill on hover
- add hover highlight to Launch Present footer row
- add "Launch Present" footer link and macwindow icon
- extend session context menu to active sessions
- add delete session via right-click context menu
- version DMG filenames and remove broken stable release workflow
- add standalone break expiry alert with session context (#49)
- overhaul floating alert UI for rhythm focus expiry (#49)
- polish break expiry alert UI
- add EditPillButton shared component
- round UI durations to nearest minute before summing
- show live duration for active session in breakdown card
- add day labels for cross-midnight session times
- add informational panel for Break system activity
- surface Break as read-only system activity in UI
- add timer-end floating alert with break and restart actions (#49)
- improve activity breakdown card legibility
- add lotus bloom animation to header
- add rich hover tooltip to day timeline
- add semantic typography tokens and migrate views
- add zoom support with scaled fonts
- add Cmd+/- text zoom for main window
- edit icon opens activity in main app
- add session delete command
- add day timeline graph to today's summary
- show active sessions in breakdown with live timer and spinning icon; fix state icons per session type
- replace session/summary cards with unified header
- auto-label new issues with Claude Code
- add local-assets directory to .gitignore
- simplify data management section
- expandable activity breakdown with striped rows
- add onHoverStart callback for hover events
- add weekend background bands to bar charts
- add weekly stacked bar chart
- surface CLI version and outdated install warning
- show CLI version status in CLI settings tab
- add session add command and rename search to list
- add backdated session, setActivityTags, and activitySummary
- add Cmd+N keyboard shortcut for New Activity
- consolidate session log into reports page
- add empty state placeholder for periods with no sessions
- replace bottom bar buttons with settings gear icon
- add external ID breakdown donut chart
- replace click-to-edit links with always-editable fields
- add smart list continuation in markdown editor
- add inline editing for activity links with hover-to-edit UX
- add explicit cancel actions for inline editing
- move action buttons to footer with timestamps
- replace modal edit with inline editing and redesigned layout
- display user-facing error feedback for failed operations
- add stacked bar chart breakdown for tag distribution
- add interactive legend to donut chart
- smooth fade-out animation for cancel button
- add week start preference picker
- redesign charts with consistent axes and improved layout
- make CSV export CLI-only with archive flag
- add timer linger with flash/fade and enhance recent session display
- add dusty palette and visual picker in settings
- add dynamic color palette system with basic and modern themes
- add layered Icon Composer format with dynamic gradient
- update app icon to v3 lotus clock design and set version to 0.1
- restructure to noun-verb pattern with input validation
- route all issue filing and PM tasks through PM agent
- add pm agent for issue triage and backlog management
- add auto-generated CLI reference documentation
- add configurable default timebound duration
- add app icon asset catalog and display in About page
- pair break duration with focus time in rhythm options
- add SF Symbol icons to right-click context menu items
- show activity names in context menu actions
- add danger zone with bulk deletion operations
- add recent session restart suggestion
- add clear button and dynamic label to activity search
- add sound effects system for session lifecycle events
- make rhythm cycle length configurable
- add quick-create field, row redesign, and inline editing
- add About tab and Settings button to main window
- add session type picker to menubar and activity detail

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
- restore trailing commas in CommandConfiguration calls
- use filled SF Symbol variants in session menus
- update card titles to match app voice
- centralize rhythm duration formatting via RhythmOption
- restructure header with proportional layout
- unify quick-restart rows with shared QuickStartRow
- bump CLI help text font from footnote to callout
- extract week range formatting; add subtitle to ChartCard
- extract shared Font tokens for dashboard greeting and period header
- migrate hardcoded padding to Constants.spacing* values
- extract shared chart components from ReportsView
- extract shared StatItem and flatten today summary
- restructure session and report commands (Phase 4, #33)
- restructure activity tag commands into SALR subgroup
- simplify archive filtering to always include archived activities
- use primary color for navigation chrome selection states
- remove non-functional timebox scaffolding
- delete cancelled sessions instead of marking status

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
- scope error alerts to their originating scene
- resolve compiler warnings in app and tests
- bump Xcode to 16.3 for Swift 6.1 trailing comma support
- bump Xcode to 16.2 to fix Swift Testing segfault
- grant write permission so cli-docs bot can push
- remove trailing commas from CommandConfiguration argument lists
- add contents:read permission to milestone version issue workflow
- read MARKETING_VERSION from project.yml in beta-release.sh
- render timeline segments instead of session blocks
- show floating alert when app is inactive
- bring window to front before opening from menu bar
- pulse weekly chart active segment
- port hover fixes from reports chart to Your Week
- verify local main matches origin/main before beta build
- increase bottom bar vertical padding to clear popover corner
- resize "Launch Present" footer to body font
- use adaptive foreground color in floating alert buttons
- fix cross-midnight attribution in activity, tag, and tag-activity summaries
- apply minute rounding to tag activity summary
- fix stacked bar chart overlay blocking legend hover
- show weekly chart during first session of the week
- remove unused recentId binding in FloatingAlertView
- prepend Gatekeeper workaround to beta release notes (#63)
- checkout repo before invoking local composite action
- align alert button copy with voice & tone conventions (#49)
- apply consistent alert patterns to timebound window (#49)
- refine ResumeActivityCard and SteamingCupIcon styles
- restyle break alert resume card and end button
- prevent Swift Charts crash on session start from menu bar
- stabilize EditPillButton hover animation
- use Xh Ym format for all chart tooltips
- refine session row icons and duration format
- show segment-based today/total split for cross-midnight sessions
- disallow rhythm sessions on system activities
- clarify break-completion alert actions
- self-heal missing Break activity in getBreakActivity
- update greeting in real-time at period boundaries
- persist breakPrecedingContext across crashes
- skip system activities in weekly chart injection
- prevent crash when clicking floating alert buttons
- attribute cross-midnight sessions to correct day
- play lotus bloom animation once per app session
- replace static now-indicator with pulsing active block
- unify activity colors and sort legends across timeline and chart
- select activity on appear when navigation pending
- add descriptive prompt to CLI install auth dialog
- consolidate CLI help text into install section
- move CLI version status inline with Install button
- stabilize chart colors and prevent future session creation
- track active intervals for accurate hourly breakdown
- install xcodegen and harden workflow permissions
- include active session in Today stats
- improve activity breakdown with time ranges, paused time, state icons, and consistent empty state
- pass timer settings on quick restart; add Recent label and restart icon
- align single-session rows with hidden chevron placeholder
- add Today heading to stats GroupBox matching ChartCard style
- apply security hardening and expand design/* labels
- replace @State with computed property to prevent cancel animation replay
- stabilize list width with GeometryReader layout
- sort activities alphabetically instead of by updatedAt
- show full date in weekly chart tooltips
- centralize empty state layout into shared modifier
- top-align empty state in activities detail pane
- resolve concurrency warnings in MarkdownEditor list continuation
- suppress unused return value warning in untagActivity
- resolve Swift 6 concurrency warnings in StatusItemMenuManager
- allow vertical resizing of settings window
- replace deprecated plotAreaFrame with plotFrame
- allow resizing settings window
- constrain MarkdownEditor to 700pt max width
- apply hover background to PaletteRow
- merge two overlapping sound toggles into one
- explicitly dismiss popover when Settings is clicked
- clear stale data before reloading to prevent chart crash
- honor week start preference in monthly summaries and improve drill-down
- align weekly chart bars with x-axis labels for custom week start days
- prevent crash when switching periods by resetting chart state
- increase font sizes across detail view for better readability
- clear strikethrough when unchecking markdown checkboxes
- reduce inline edit activation to single-click
- reorder archive alert buttons to follow macOS conventions
- remove non-functional flash animation from timer completion
- align period selector to content width
- align picker, round y-axis, fix week-start crash
- show archived activities by default
- refine chart axis labels and tooltip behavior
- improve chart title prominence and spacing
- improve controls layout and date formatting
- replace raw .accentColor with theme.accent in PaletteRow
- replace force unwraps with safe optional handling
- hide decorative icons from VoiceOver
- add VoiceOver labels to activity toolbar buttons
- add accessibility labels to session control buttons
- apply theme palette to system controls and selections
- prevent infinite render loop in palette preview
- rename executable to present-cli and fix install button
- center session type picker and cap rhythm presets to 4 options
- make right-click menu actions work reliably
- top-align content across all views and improve layout consistency
- expand activity list and detail panes to full height
- eliminate timer flickering and simplify running session UI
- top-align activities list and detail views
- prevent refreshAll from overriding paused state
- replace broken sheet with direct session start
- replace URL scheme with openWindow and add quit button

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
- Merge pull request #139 from terriann/feat/0.1.0
- Merge branch 'main' into feat/0.1.0
- Merge branch 'main' of github.com:terriann/present
- Merge pull request #93 from terriann/feat/0.1.0
- Merge pull request #91 from terriann/feat/0.1.0
- Merge pull request #90 from terriann/feat/0.1.0
- Merge pull request #84 from terriann/fix/beta-script-stale-main
- Merge pull request #80 from terriann/feat/0.1.0
- Merge pull request #74 from terriann/feat/0.1.0
- Merge pull request #48 from terriann/fix/session-hourly-breakdown
- Merge remote-tracking branch 'origin/feat/app-initialization' into fix/session-hourly-breakdown
- Merge pull request #46 from terriann/feat/release-pipeline
- Merge pull request #45 from terriann/feat/dashboard-header-redesign
- Merge pull request #44 from terriann/copilot/auto-label-new-issues
- Merge branch 'feat/app-initialization' into copilot/auto-label-new-issues
- restore workflow to pre-edit state
- Merge pull request #41 from terriann/add-claude-github-actions-1771562424936
- Initial plan
- "Claude Code Review workflow"
- "Claude PR Assistant workflow"
- Add Phase 5: CI workflow, build scripts, and documentation
- Add Phase 4: cancel command, IPC tests, and CLI workflow tests
- Add Phase 3: Markdown editor, notifications, activity detail, and log filtering
- Add Phase 2 app shell: SwiftUI views, menu bar, and XcodeGen config
- Add Phase 1 foundation: PresentCore library, CLI, and tests
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
