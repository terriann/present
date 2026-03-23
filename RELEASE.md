# Releasing

Guide for versioning, building, and publishing Present releases.

## Table of Contents

- [Versioning](#versioning)
  - [When to Increment](#when-to-increment)
  - [Guidelines](#guidelines)
- [Release Lifecycle](#release-lifecycle)
  - [Phase 1: Start of Milestone](#phase-1-start-of-milestone)
  - [Phase 2: Development](#phase-2-development)
  - [Phase 3: Beta Testing](#phase-3-beta-testing)
  - [Phase 4: Production Release](#phase-4-production-release)
  - [Workflow Example](#workflow-example)
- [Scripts Reference](#scripts-reference)
  - [bump-version.sh](#bump-versionsh)
  - [release.sh](#releasesh)
  - [beta-release.sh](#beta-releasesh)
  - [build-dmg.sh](#build-dmgsh)
  - [notarize.sh](#notarizesh)
  - [install-cli.sh](#install-clish)
  - [Shared Helpers](#shared-helpers)

## Versioning

Present tracks two version identifiers:

- **`CFBundleShortVersionString`** -- The user-facing marketing version,
  following [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).
  Stored in `PresentApp/Info.plist`.
- **`CFBundleVersion`** -- The internal build number, an integer that must
  always increment. macOS uses this to determine whether a build is newer.
  Stored in `PresentApp/Info.plist`.
- **`MARKETING_VERSION`** -- Build setting in `project.yml`. During
  development this carries a `-dev` suffix (e.g., `0.2.0-dev`). Release
  scripts strip the suffix automatically when resolving the version.

### When to Increment

- **Marketing version** (`CFBundleShortVersionString`): Bump according to
  semver. MAJOR for breaking changes, MINOR for new features, PATCH for
  bug fixes.
- **Build number** (`CFBundleVersion`): Increment with every release
  build, regardless of version bump type. If v1.2.0 ships as build 5, the
  next release (even v1.2.1) must be build 6 or higher.

### Guidelines

- Never decrement the build number.
- Update both values together when running the bump script.
- During development, the version in `Info.plist` and `Constants.swift`
  reflects the version being worked toward (set by `bump-version.sh` at
  the start of the milestone).
- Git tags use the format `vX.Y.Z` (prefixed with `v`) and must match
  the marketing version.

## Release Lifecycle

A release has four phases, tied to milestones. The bump happens at the
start of a milestone, not at the end.

### Phase 1: Start of Milestone

Run `bump-version.sh` to set the target version for the milestone:

```bash
./Scripts/bump-version.sh 0.3.0
git push && git push --tags
```

This creates a version commit and `v0.3.0` tag on `main`. From this
point forward, `Info.plist` and `Constants.swift` reflect `0.3.0`, and
`CHANGELOG.md` contains entries for all commits since the previous tag.

### Phase 2: Development

Development happens on feature branches merged into `main`. The
`MARKETING_VERSION` in `project.yml` reads `0.3.0-dev` during this
phase. No release scripts run here.

### Phase 3: Beta Testing

Once enough work has landed on `main` for testing, publish a beta:

```bash
./Scripts/beta-release.sh
```

This builds a DMG, auto-increments the beta number (e.g.,
`v0.3.0-beta.1`), and publishes a GitHub pre-release. Run it as many
times as needed -- each invocation increments the beta number.

### Phase 4: Production Release

When the milestone is complete and betas have been validated, publish
the production release:

```bash
./Scripts/release.sh
```

This builds a DMG, generates categorized release notes from all commits
since the last stable tag, and publishes a GitHub release marked as
latest.

### Workflow Example

```bash
# Starting v0.3.0 milestone
./Scripts/bump-version.sh 0.3.0
git push && git push --tags

# ... development happens on feature branches ...

# Beta testing
./Scripts/beta-release.sh           # publishes v0.3.0-beta.1
# ... fix bugs ...
./Scripts/beta-release.sh           # publishes v0.3.0-beta.2

# Production release
./Scripts/release.sh                # publishes v0.3.0
```

## Scripts Reference

Six scripts in `Scripts/` handle versioning, building, and distribution.
The release scripts share common logic through a helper library.

### bump-version.sh

Automates version updates at the start of a milestone. The working tree
must be clean before running.

```bash
./Scripts/bump-version.sh patch     # 1.0.0 -> 1.0.1
./Scripts/bump-version.sh minor     # 1.0.0 -> 1.1.0
./Scripts/bump-version.sh major     # 1.0.0 -> 2.0.0
./Scripts/bump-version.sh 1.2.3     # Set to an explicit version
```

What it does:

1. Reads `CFBundleShortVersionString` and `CFBundleVersion` from
   `PresentApp/Info.plist`.
2. Computes the new marketing version (bump type or explicit semver).
3. Increments the build number by 1.
4. Writes both values back to `Info.plist` via `plutil`.
5. Updates `Constants.appVersion` in
   `Sources/PresentCore/Utilities/Constants.swift`.
6. Generates changelog entries from commits since the last tag using
   shared helpers from `Scripts/lib/release-helpers.sh`, then prepends
   a new section to `CHANGELOG.md`.
7. Stages the changed files and creates a git commit
   (`chore(build): bump version to X.Y.Z`) plus a `vX.Y.Z` tag.

### release.sh

Production release script. Runs at the end of a milestone from `main`.

```bash
./Scripts/release.sh                # reads version from project.yml
./Scripts/release.sh 0.3.0          # or specify explicitly
```

What it does:

1. Runs preflight checks (clean tree, on `main`, synced with
   `origin/main`, `gh` CLI available).
2. Resolves the version from `project.yml` `MARKETING_VERSION`
   (stripping the `-dev` suffix) or from the explicit argument.
3. Validates semver format and guards against duplicate tags.
4. Finds the previous stable tag (skips beta tags) for the changelog
   range.
5. Builds a versioned DMG via `build-dmg.sh`.
6. Generates categorized release notes with scope prefixes and issue
   references.
7. Creates a GitHub release with `--latest`, attaching the DMG.

### beta-release.sh

Pre-release script for beta testing. Can run multiple times per
milestone from `main`.

```bash
./Scripts/beta-release.sh           # reads version from project.yml
./Scripts/beta-release.sh 0.3.0     # or specify explicitly
```

What it does:

1. Runs preflight checks (same as `release.sh`).
2. Resolves the marketing version from `project.yml` or the argument.
3. Computes the next beta tag by scanning existing tags (e.g.,
   `v0.3.0-beta.1`, then `v0.3.0-beta.2`).
4. Builds a versioned DMG via `build-dmg.sh`.
5. Generates changelog entries from commits since the previous beta
   (or last tag, for the first beta).
6. Creates a GitHub pre-release with the DMG attached.

### build-dmg.sh

Builds a signed DMG with an optional version suffix. Set
`SIGNING_IDENTITY` for real code signing (defaults to ad-hoc).

```bash
./Scripts/build-dmg.sh                   # produces Present.dmg
./Scripts/build-dmg.sh 0.3.0-beta.1      # produces Present-0.3.0-beta.1.dmg
```

### notarize.sh

Submits the DMG for Apple notarization. Requires `APPLE_ID`, `TEAM_ID`,
and `APP_PASSWORD` environment variables.

```bash
APPLE_ID=dev@example.com TEAM_ID=XXXXX APP_PASSWORD=xxxx \
  ./Scripts/notarize.sh
```

### install-cli.sh

Builds and installs the CLI binary locally.

```bash
./Scripts/install-cli.sh
```

### Shared Helpers

`Scripts/lib/release-helpers.sh` provides common functions used by
`release.sh`, `beta-release.sh`, and `bump-version.sh`:

- **`preflight_checks`** -- Validates clean tree, correct branch,
  remote sync, and `gh` CLI availability.
- **`resolve_version`** -- Reads `MARKETING_VERSION` from `project.yml`
  (stripping the `-dev` suffix) or accepts an explicit argument.
  Validates semver format.
- **`build_dmg`** -- Delegates to `build-dmg.sh` and verifies the
  output file exists.
- **`get_last_stable_tag`** / **`get_last_tag`** -- Tag lookup helpers
  for changelog range resolution.
- **`generate_changelog`** -- Categorized release notes with optional
  scope prefixes and issue references.
- **`generate_keepachangelog`** -- Keep a Changelog format sections
  (Added/Changed/Fixed) for `CHANGELOG.md`.
