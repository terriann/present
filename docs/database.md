# Database Architecture

Present uses a local SQLite database managed by
[GRDB.swift](https://github.com/groue/GRDB.swift). Both the macOS app
and CLI share the same database file. All reads and writes go through
`PresentService`, the single concrete implementation of the
`PresentAPI` protocol.

> [!CAUTION]
> **The CLI is the intended interface for all data access.** Direct
> database queries should only be used as a last resort for debugging.
> If raw SQL is needed to accomplish something the CLI cannot do,
> **that is a gap in the CLI that should be fixed.** Create a GitHub
> issue to document what is missing before proceeding with direct
> database access.

## Table of Contents

- [Database File Location](#database-file-location)
- [Connecting with the SQLite CLI](#connecting-with-the-sqlite-cli)
- [Schema](#schema)
  - [activity](#activity)
  - [tag](#tag)
  - [activity\_tag](#activity_tag)
  - [session](#session)
  - [session\_segment](#session_segment)
  - [preference](#preference)
  - [grdb\_migrations](#grdb_migrations)
- [Virtual Tables (FTS5)](#virtual-tables-fts5)
  - [activity\_fts](#activity_fts)
- [Relationships](#relationships)
- [Migration History](#migration-history)
- [Data Type Conventions](#data-type-conventions)
- [Enum Values](#enum-values)
- [Debug Queries](#debug-queries)
- [Source File Reference](#source-file-reference)

## Database File Location

| File | Purpose |
| ---- | ------- |
| `~/Library/.../Present/present.sqlite` | Main database |
| `~/Library/.../Present/present.sqlite-shm` | WAL shared memory |
| `~/Library/.../Present/present.sqlite-wal` | WAL write-ahead log |

Full path: `~/Library/Application Support/Present/`

Configuration:

- **Journal mode**: WAL (Write-Ahead Logging)
- **Foreign keys**: Enabled
- **Production**: `DatabasePool` (concurrent reads)
- **Testing**: `DatabaseQueue` with in-memory SQLite

The path is resolved in `DatabaseManager.defaultDatabasePath`.

## Connecting with the SQLite CLI

```bash
sqlite3 ~/Library/Application\ Support/Present/present.sqlite
```

Useful meta-commands:

```sql
-- List all tables
.tables

-- Show CREATE for a table
.schema activity

-- Show column headers
.headers on

-- Columnar output
.mode column

-- Verify WAL mode
PRAGMA journal_mode;

-- Verify FK enforcement (1 = on)
PRAGMA foreign_keys;

-- Migration history
SELECT identifier FROM grdb_migrations ORDER BY rowid;
```

## Schema

### activity

Tracks named activities (projects, tasks, tickets) that sessions
are logged against.

```sql
CREATE TABLE "activity" (
    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "title" TEXT NOT NULL,
    "externalId" TEXT,
    "link" TEXT,
    "notes" TEXT,
    "isArchived" BOOLEAN NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL,
    "updatedAt" DATETIME NOT NULL
);
```

| Column | Type | Nullable | Notes |
| ------ | ---- | -------- | ----- |
| `id` | INTEGER | No | Auto-incremented primary key |
| `title` | TEXT | No | Display name |
| `externalId` | TEXT | Yes | External system identifier |
| `link` | TEXT | Yes | URL to external resource |
| `notes` | TEXT | Yes | Markdown notes |
| `isArchived` | BOOLEAN | No | Stored as 0/1 |
| `createdAt` | DATETIME | No | ISO8601 |
| `updatedAt` | DATETIME | No | ISO8601, updated on modification |

### tag

Labels applied to activities for categorization and filtering.

```sql
CREATE TABLE "tag" (
    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "name" TEXT NOT NULL UNIQUE,
    "createdAt" DATETIME DEFAULT '1970-01-01 00:00:00',
    "updatedAt" DATETIME DEFAULT '1970-01-01 00:00:00'
);
```

| Column | Type | Nullable | Notes |
| ------ | ---- | -------- | ----- |
| `id` | INTEGER | No | Auto-incremented primary key |
| `name` | TEXT | No | Unique tag name |
| `createdAt` | DATETIME | No | Defaults to epoch (v5 backfill) |
| `updatedAt` | DATETIME | No | Defaults to epoch (v5 backfill) |

### activity_tag

Join table linking activities to tags. Many-to-many relationship.

```sql
CREATE TABLE "activity_tag" (
    "activityId" INTEGER NOT NULL
        REFERENCES "activity"("id") ON DELETE CASCADE,
    "tagId" INTEGER NOT NULL
        REFERENCES "tag"("id") ON DELETE CASCADE,
    PRIMARY KEY ("activityId", "tagId")
);
```

| Column | Type | Nullable | Notes |
| ------ | ---- | -------- | ----- |
| `activityId` | INTEGER | No | FK to `activity.id`, cascade |
| `tagId` | INTEGER | No | FK to `tag.id`, cascade |

Composite primary key prevents duplicate tag assignments.

### session

A single time tracking session logged against an activity.

```sql
CREATE TABLE "session" (
    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "activityId" INTEGER NOT NULL
        REFERENCES "activity"("id"),
    "sessionType" TEXT NOT NULL,
    "startedAt" DATETIME NOT NULL,
    "endedAt" DATETIME,
    "durationSeconds" INTEGER,
    "timerLengthMinutes" INTEGER,
    "rhythmSessionIndex" INTEGER,
    "state" TEXT NOT NULL,
    "totalPausedSeconds" INTEGER NOT NULL DEFAULT 0,
    "lastPausedAt" DATETIME,
    "createdAt" DATETIME NOT NULL,
    "breakMinutes" INTEGER
);
```

| Column | Type | Nullable | Notes |
| ------ | ---- | -------- | ----- |
| `id` | INTEGER | No | Auto-incremented PK |
| `activityId` | INTEGER | No | FK to `activity.id` (no cascade) |
| `sessionType` | TEXT | No | See [Enum Values](#enum-values) |
| `startedAt` | DATETIME | No | When the session began |
| `endedAt` | DATETIME | Yes | Null while active |
| `durationSeconds` | INTEGER | Yes | Computed on completion |
| `timerLengthMinutes` | INTEGER | Yes | Timer for rhythm/timebound |
| `rhythmSessionIndex` | INTEGER | Yes | Pomodoro cycle position (1-4) |
| `state` | TEXT | No | See [Enum Values](#enum-values) |
| `totalPausedSeconds` | INTEGER | No | Cumulative pause duration |
| `lastPausedAt` | DATETIME | Yes | Most recent pause timestamp |
| `createdAt` | DATETIME | No | Row creation timestamp |
| `breakMinutes` | INTEGER | Yes | Break duration (rhythm only) |

> [!NOTE]
> The `activityId` foreign key does **not** cascade on delete.
> Deleting an activity that has sessions will fail with a foreign
> key violation. Activities should be archived instead of deleted.

### session_segment

Tracks each continuous active interval within a session. A new
segment is created when a session starts or resumes; the segment
is closed (`endedAt` set) when the session pauses or completes.

```sql
CREATE TABLE "session_segment" (
    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "sessionId" INTEGER NOT NULL
        REFERENCES "session"("id") ON DELETE CASCADE,
    "startedAt" DATETIME NOT NULL,
    "endedAt" DATETIME
);
```

| Column | Type | Nullable | Notes |
| ------ | ---- | -------- | ----- |
| `id` | INTEGER | No | Auto-incremented PK |
| `sessionId` | INTEGER | No | FK to `session.id`, cascade |
| `startedAt` | DATETIME | No | When this interval began |
| `endedAt` | DATETIME | Yes | Null for active segment |

Used for accurate hourly time breakdown in reports.

### preference

Key-value store for application preferences.

```sql
CREATE TABLE "preference" (
    "key" TEXT PRIMARY KEY NOT NULL,
    "value" TEXT NOT NULL
);
```

All values are stored as TEXT strings regardless of logical type.

| Key | Default | Type | Purpose |
| --- | ------- | ---- | ------- |
| `externalIdBaseUrl` | `""` | String | Base URL for links |
| `defaultRhythmMinutes` | `"25"` | Int | Pomodoro focus duration |
| `longBreakMinutes` | `"15"` | Int | Long break duration |
| `rhythmCycleLength` | `"4"` | Int | Sessions before long break |
| `notificationSound` | `"1"` | Bool | Notification sound on |
| `soundEffectsEnabled` | `"1"` | Bool | UI sound effects on |
| `includeArchivedInReports` | `"0"` | Bool | Archived in reports |
| `rhythmDurationOptions` | `"25:5,30:5,45:10"` | String | Focus:break presets |
| `defaultTimeboundMinutes` | `"25"` | Int | Timebound duration |
| `colorPalette` | `"basic"` | Enum | `basic` or `modern` |
| `weekStartDay` | `"sunday"` | Enum | `sunday` or `monday` |

Boolean values use `"1"` (true) and `"0"` (false) as strings.

### grdb_migrations

Internal GRDB migration tracking table. Do not modify directly.

```sql
CREATE TABLE "grdb_migrations" (
    "identifier" TEXT NOT NULL PRIMARY KEY
);
```

## Virtual Tables (FTS5)

### activity_fts

Full-text search index over activity titles and notes.

```sql
CREATE VIRTUAL TABLE "activity_fts" USING fts5(
    title,
    notes,
    tokenize='porter',
    content='activity',
    content_rowid='id'
);
```

- **Tokenizer**: Porter stemmer (normalizes word variants:
  run/running/runs all match "run")
- **Content sync**: Automatically synced to the `activity` table
  via GRDB-managed triggers on INSERT, UPDATE, and DELETE
- **Support tables** (auto-created, do not modify):
  `activity_fts_data`, `activity_fts_idx`,
  `activity_fts_docsize`, `activity_fts_config`

Example FTS query:

```sql
SELECT a.*
FROM activity a
JOIN activity_fts ON activity_fts.rowid = a.id
WHERE activity_fts MATCH 'deploy*';
```

## Relationships

```text
activity 1---* session 1---* session_segment
    |
    *---* tag  (through activity_tag)
```

| From | Rel | To | FK | On Delete |
| ---- | --- | -- | -- | --------- |
| activity | hasMany | session | `session.activityId` | Restricted |
| activity | hasMany | activity_tag | `activity_tag.activityId` | Cascade |
| activity | hasMany | tag | via activity_tag | Cascade |
| tag | hasMany | activity_tag | `activity_tag.tagId` | Cascade |
| tag | hasMany | activity | via activity_tag | Cascade |
| session | belongsTo | activity | `session.activityId` | Restricted |
| session | hasMany | session_segment | `segment.sessionId` | Cascade |
| segment | belongsTo | session | `segment.sessionId` | Cascade |

## Migration History

Migrations are registered in `DatabaseManager.migrate()` and run
in order. GRDB tracks applied migrations in `grdb_migrations`.

| # | Identifier | Changes |
| - | ---------- | ------- |
| 1 | `v1-create-tables` | Initial schema, default prefs |
| 2 | `v2-add-session-break-minutes` | `breakMinutes` column, option format |
| 3 | `v3-remove-timebox-fields` | Drop `plannedStart`/`plannedEnd` |
| 4 | `v4-seed-default-timebound-minutes` | Seed `defaultTimeboundMinutes` |
| 5 | `v5-add-tag-timestamps` | `createdAt`/`updatedAt` on tag |
| 6 | `v6-add-session-segment` | session_segment table, backfill |

## Data Type Conventions

| SQLite Storage | Swift Type | Serialization |
| -------------- | ---------- | ------------- |
| `INTEGER PK AUTOINCREMENT` | `Int64?` | Nil before insert |
| `TEXT` | `String` | Direct mapping |
| `TEXT` (enum) | `String` | Enum `.rawValue` |
| `DATETIME` | `Date` | ISO8601 |
| `BOOLEAN` | `Bool` | INTEGER 0 or 1 |
| `INTEGER` | `Int` | Direct mapping |

## Enum Values

These enums are stored as TEXT in the database.

**SessionType** (`session.sessionType`):

| Value | Description |
| ----- | ----------- |
| `work` | Open-ended work session, no timer |
| `rhythm` | Pomodoro-style focus/break cycle |
| `timebound` | Fixed-duration countdown timer |

**SessionState** (`session.state`):

| Value | Description |
| ----- | ----------- |
| `running` | Actively tracking time |
| `paused` | Paused (time not accumulating) |
| `completed` | Finished normally |
| `cancelled` | Discarded |

## Debug Queries

Ready-to-run SQL for common debugging scenarios.

**Find the currently active session:**

```sql
SELECT s.*, a.title AS activityTitle
FROM session s
JOIN activity a ON a.id = s.activityId
WHERE s.state IN ('running', 'paused')
ORDER BY s.startedAt DESC
LIMIT 1;
```

**List all sessions for a given activity:**

```sql
SELECT id, sessionType, state,
       startedAt, endedAt, durationSeconds
FROM session
WHERE activityId = ?
ORDER BY startedAt DESC;
```

**Show today's completed sessions with durations:**

```sql
SELECT s.id, a.title, s.sessionType,
       s.startedAt, s.endedAt,
       s.durationSeconds / 60.0 AS durationMinutes
FROM session s
JOIN activity a ON a.id = s.activityId
WHERE s.state = 'completed'
  AND date(s.startedAt) = date('now')
ORDER BY s.startedAt;
```

**Show all tags for an activity:**

```sql
SELECT t.id, t.name
FROM tag t
JOIN activity_tag at ON at.tagId = t.id
WHERE at.activityId = ?
ORDER BY t.name;
```

**Check for sessions without segments (data integrity):**

```sql
SELECT s.id, s.state, s.startedAt
FROM session s
LEFT JOIN session_segment seg ON seg.sessionId = s.id
WHERE seg.id IS NULL
  AND s.state = 'completed';
```

**Check for orphaned session segments:**

```sql
SELECT seg.*
FROM session_segment seg
LEFT JOIN session s ON s.id = seg.sessionId
WHERE s.id IS NULL;
```

**Show all preferences:**

```sql
SELECT key, value FROM preference ORDER BY key;
```

**Count sessions by state:**

```sql
SELECT state, COUNT(*) AS count
FROM session
GROUP BY state
ORDER BY count DESC;
```

**Count sessions by type:**

```sql
SELECT sessionType, COUNT(*) AS count
FROM session
GROUP BY sessionType
ORDER BY count DESC;
```

**Show open (unclosed) segments:**

```sql
SELECT seg.*, s.state AS sessionState
FROM session_segment seg
JOIN session s ON s.id = seg.sessionId
WHERE seg.endedAt IS NULL;
```

## Source File Reference

Key files for AI agents and developers navigating the codebase.

**Database layer:**

- `Sources/PresentCore/Database/DatabaseManager.swift`
  -- DB setup, migrations, pool config

**Models:**

- `Sources/PresentCore/Models/Activity.swift`
  -- Activity model and relationships
- `Sources/PresentCore/Models/Session.swift`
  -- Session model and relationships
- `Sources/PresentCore/Models/SessionSegment.swift`
  -- Segment model for intervals
- `Sources/PresentCore/Models/SessionType.swift`
  -- SessionType and SessionState enums
- `Sources/PresentCore/Models/Tag.swift`
  -- Tag model and relationships
- `Sources/PresentCore/Models/ActivityTag.swift`
  -- Join table model
- `Sources/PresentCore/Models/Preference.swift`
  -- Preference model, PreferenceKey enum

**API layer:**

- `Sources/PresentCore/API/PresentService.swift`
  -- All business logic (authoritative)
- `Sources/PresentCore/API/PresentAPI.swift`
  -- Protocol for all operations
