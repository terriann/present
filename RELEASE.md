# Releasing

Guide for versioning, building, and publishing Present releases.

## Table of Contents

- [Versioning](#versioning)
  - [When to Increment](#when-to-increment)
  - [Guidelines](#guidelines)
- [Bump Script](#bump-script)
  - [What It Does](#what-it-does)
- [Release Process](#release-process)
  - [1. Bump Version](#1-bump-version)
  - [2. Beta Release](#2-beta-release)
  - [3. Stable Release](#3-stable-release)
- [Distribution Scripts](#distribution-scripts)

## Versioning

Present tracks two version identifiers in `PresentApp/Info.plist`:

- **`CFBundleShortVersionString`** (currently `0.1.0`) -- The user-facing
  marketing version, following
  [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).
- **`CFBundleVersion`** (currently `1`) -- The internal build number,
  an integer that must always increment. macOS uses this to determine
  whether a build is newer. Required by the App Store and TestFlight.

### When to Increment

- **Marketing version** (`CFBundleShortVersionString`): Bump according to
  semver. MAJOR for breaking changes, MINOR for new features, PATCH for
  bug fixes.
- **Build number** (`CFBundleVersion`): Increment with every release
  build, regardless of version bump type. If v1.2.0 ships as build 5, the
  next release (even v1.2.1) must be build 6 or higher.

### Guidelines

- Never decrement the build number.
- Update both values together at release time.
- During development, the version in `Info.plist` reflects the *next*
  planned release.
- Git tags use the format `vX.Y.Z` (prefixed with `v`) and must match
  the marketing version.

## Bump Script

`Scripts/bump-version.sh` automates version updates. The working tree
must be clean before running.

```bash
./Scripts/bump-version.sh patch     # 1.0.0 -> 1.0.1
./Scripts/bump-version.sh minor     # 1.0.0 -> 1.1.0
./Scripts/bump-version.sh major     # 1.0.0 -> 2.0.0
./Scripts/bump-version.sh 1.2.3     # Set to an explicit version
```

### What It Does

1. Reads `CFBundleShortVersionString` and `CFBundleVersion` from
   `PresentApp/Info.plist`.
2. Computes the new marketing version (bump type or explicit semver).
3. Increments the build number by 1.
4. Writes both values back to `Info.plist` via `plutil`.
5. Updates `Constants.cliVersion` in
   `Sources/PresentCore/Utilities/Constants.swift`.
6. Collects commits since the last tag, groups them by conventional
   commit type, and prepends a new section to `CHANGELOG.md`.
7. Stages the changed files and creates a git commit (`chore(build):
   bump version to X.Y.Z`) plus a `vX.Y.Z` tag.

## Release Process

Releases follow three steps: bump the version, optionally publish a
beta, then publish a stable release.

### 1. Bump Version

Run the bump script to prepare the release:

```bash
./Scripts/bump-version.sh patch     # or minor / major / X.Y.Z
```

This creates a tagged commit locally. Push the branch (but not the tag
yet) if a beta is planned first.

### 2. Beta Release

Run the beta release script locally:

```bash
./Scripts/beta-release.sh           # reads version from Info.plist
./Scripts/beta-release.sh 0.2.0     # or specify a version explicitly
```

The script:

1. Checks pre-flight conditions (clean working tree, on `main`, `gh`
   CLI available).
2. Resolves the marketing version (argument or `Info.plist`).
3. Computes the next beta tag by scanning existing tags (e.g.,
   `v0.1.0-beta.1`, `v0.1.0-beta.2`).
4. Builds a versioned DMG (e.g. `Present-0.1.0-beta.1.dmg`) via
   `Scripts/build-dmg.sh`.
5. Creates a GitHub pre-release with the DMG attached via `gh release
   create`.

### 3. Stable Release

Stable releases are not yet automated. When a stable release workflow
is needed, a new one will be created.

## Distribution Scripts

Three scripts in `Scripts/` handle building and distributing the app:

- **`beta-release.sh`** -- Builds a DMG and publishes a GitHub
  pre-release with an auto-incrementing beta tag.
- **`build-dmg.sh`** -- Builds a signed DMG with an optional version
  suffix. Set `SIGNING_IDENTITY` for real code signing (defaults to
  ad-hoc).
- **`notarize.sh`** -- Submits the DMG for Apple notarization. Requires
  `APPLE_ID`, `TEAM_ID`, and `APP_PASSWORD` environment variables.
- **`install-cli.sh`** -- Builds and installs the CLI binary locally.

```bash
# Build signed DMG (set SIGNING_IDENTITY for real signing)
./Scripts/build-dmg.sh                   # produces Present.dmg
./Scripts/build-dmg.sh 0.1.0-beta.1      # produces Present-0.1.0-beta.1.dmg

# Notarize (requires Apple Developer credentials)
APPLE_ID=you@example.com TEAM_ID=XXXXX APP_PASSWORD=xxxx ./Scripts/notarize.sh

# Install CLI locally
./Scripts/install-cli.sh
```
