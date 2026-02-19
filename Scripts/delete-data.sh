#!/bin/bash
set -euo pipefail

# Delete time-tracking data with automatic backups.
#
# Before any destructive operation, snapshots the affected tables so
# the last 30 operations can be rolled back.
#
# Usage:
#   ./scripts/delete-data.sh                          # Delete all sessions from today
#   ./scripts/delete-data.sh --date 2026-02-10        # Delete all sessions from a specific date
#   ./scripts/delete-data.sh --from 2026-02-10 --to 2026-02-14  # Delete a date range
#   ./scripts/delete-data.sh --all                    # Delete ALL session data
#   ./scripts/delete-data.sh --undo                   # Roll back the last destructive operation
#   ./scripts/delete-data.sh --undo 3                 # Roll back to 3 operations ago
#   ./scripts/delete-data.sh --list-backups           # Show available backups
#
# Options:
#   --date DATE     Delete sessions on a single date (YYYY-MM-DD)
#   --from DATE     Start of date range (YYYY-MM-DD, inclusive)
#   --to DATE       End of date range (YYYY-MM-DD, inclusive)
#   --all           Delete ALL session data (all dates)
#   --undo [N]      Restore from backup N (default: 1 = most recent)
#   --list-backups  List available backup snapshots
#   --dry-run       Show what would be deleted without executing
#   --no-backup     Skip backup (not recommended)
#   -h, --help      Show this help

DB_PATH="$HOME/Library/Application Support/Present/present.sqlite"
# Resolve repo root (directory containing this script's parent)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$REPO_ROOT/.data/backups"
MAX_BACKUPS=30

DRY_RUN=false
NO_BACKUP=false
DELETE_ALL=false
UNDO=false
UNDO_N=1
LIST_BACKUPS=false
SINGLE_DATE=""
FROM_DATE=""
TO_DATE=""

# ---------- Helpers ----------

usage() {
  sed -n '3,/^$/s/^# \?//p' "$0"
  exit 0
}

log() { echo "  $*"; }

die() {
  echo "Error: $*" >&2
  exit 1
}

check_db() {
  [[ -f "$DB_PATH" ]] || die "Database not found at $DB_PATH"
}

ensure_backup_dir() {
  mkdir -p "$BACKUP_DIR"
}

# Create a backup snapshot of session-related tables.
# Stores a self-contained SQLite file that can restore the exact state.
create_backup() {
  local label="$1"
  ensure_backup_dir

  local timestamp
  timestamp=$(date "+%Y%m%d-%H%M%S")
  local backup_file="$BACKUP_DIR/${timestamp}_${label}.sql"
  local manifest_file="$BACKUP_DIR/${timestamp}_${label}.manifest"

  # Dump the tables we might alter as SQL INSERT statements
  # This captures the full state before the operation
  {
    echo "-- Backup: $label"
    echo "-- Created: $(date -u "+%Y-%m-%dT%H:%M:%SZ")"
    echo "-- Source: $DB_PATH"
    echo ""

    # Dump session table
    echo "-- Table: session"
    sqlite3 "$DB_PATH" ".dump session" | grep -E "^(CREATE|INSERT)" || true
    echo ""

    # Dump activity table
    echo "-- Table: activity"
    sqlite3 "$DB_PATH" ".dump activity" | grep -E "^(CREATE|INSERT)" || true
    echo ""

    # Dump activity_tag table
    echo "-- Table: activity_tag"
    sqlite3 "$DB_PATH" ".dump activity_tag" | grep -E "^(CREATE|INSERT)" || true
    echo ""

    # Dump tag table
    echo "-- Table: tag"
    sqlite3 "$DB_PATH" ".dump tag" | grep -E "^(CREATE|INSERT)" || true
  } > "$backup_file"

  # Write manifest with metadata
  {
    echo "timestamp=$timestamp"
    echo "label=$label"
    echo "session_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session;")"
    echo "activity_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM activity;")"
    echo "tag_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tag;")"
  } > "$manifest_file"

  log "Backup created: ${timestamp}_${label}"

  # Prune old backups beyond MAX_BACKUPS
  prune_backups
}

prune_backups() {
  ensure_backup_dir
  local count
  count=$(ls "$BACKUP_DIR"/*.manifest 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$count" -gt "$MAX_BACKUPS" ]]; then
    local to_remove=$(( count - MAX_BACKUPS ))
    ls -t "$BACKUP_DIR"/*.manifest 2>/dev/null | tail -n "$to_remove" | while read -r manifest; do
      local base="${manifest%.manifest}"
      rm -f "$base.sql" "$base.manifest"
      log "Pruned old backup: $(basename "$base")"
    done
  fi
}

list_backups() {
  ensure_backup_dir

  local manifests
  manifests=$(ls -t "$BACKUP_DIR"/*.manifest 2>/dev/null || true)

  if [[ -z "$manifests" ]]; then
    echo "No backups found."
    exit 0
  fi

  echo "=== Available Backups ==="
  echo ""
  printf "  %-4s %-20s %-30s %s\n" "#" "Timestamp" "Label" "Records (sessions/activities/tags)"
  printf "  %-4s %-20s %-30s %s\n" "---" "-------------------" "-----------------------------" "----------------------------------"

  local i=1
  echo "$manifests" | while read -r manifest; do
    local ts="" label="" sc="" ac="" tc=""
    while IFS='=' read -r key val; do
      case "$key" in
        timestamp) ts="$val" ;;
        label) label="$val" ;;
        session_count) sc="$val" ;;
        activity_count) ac="$val" ;;
        tag_count) tc="$val" ;;
      esac
    done < "$manifest"
    printf "  %-4s %-20s %-30s %s/%s/%s\n" "$i" "$ts" "$label" "$sc" "$ac" "$tc"
    i=$(( i + 1 ))
  done
  echo ""
  echo "  Use --undo N to restore backup #N (1 = most recent)"
}

restore_backup() {
  local n="$1"
  ensure_backup_dir

  local manifests
  manifests=$(ls -t "$BACKUP_DIR"/*.manifest 2>/dev/null || true)

  if [[ -z "$manifests" ]]; then
    die "No backups found."
  fi

  local target_manifest
  target_manifest=$(echo "$manifests" | sed -n "${n}p")

  if [[ -z "$target_manifest" ]]; then
    die "Backup #$n not found. Use --list-backups to see available backups."
  fi

  local sql_file="${target_manifest%.manifest}.sql"
  if [[ ! -f "$sql_file" ]]; then
    die "Backup SQL file missing: $sql_file"
  fi

  # Read manifest for display
  local ts="" label="" sc="" ac="" tc=""
  while IFS='=' read -r key val; do
    case "$key" in
      timestamp) ts="$val" ;;
      label) label="$val" ;;
      session_count) sc="$val" ;;
      activity_count) ac="$val" ;;
      tag_count) tc="$val" ;;
    esac
  done < "$target_manifest"

  echo "=== Restoring Backup ==="
  echo "  Backup: #$n ($ts)"
  echo "  Label: $label"
  echo "  State: $sc sessions, $ac activities, $tc tags"
  echo ""

  if $DRY_RUN; then
    log "[dry-run] Would restore from $sql_file"
    return
  fi

  # Back up current state before restoring (so undo of an undo is possible)
  create_backup "pre-restore"

  # Clear current data and restore
  sqlite3 "$DB_PATH" <<EOSQL
DELETE FROM session;
DELETE FROM activity_tag;
DELETE FROM activity;
DELETE FROM tag;
EOSQL

  # Filter to only INSERT statements and run them
  grep "^INSERT" "$sql_file" | sqlite3 "$DB_PATH" 2>/dev/null || true

  # Rebuild FTS index
  sqlite3 "$DB_PATH" "INSERT INTO activity_fts(activity_fts) VALUES('rebuild');" 2>/dev/null || true

  local new_sc new_ac new_tc
  new_sc=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session;")
  new_ac=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM activity;")
  new_tc=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tag;")

  echo "  Restored: $new_sc sessions, $new_ac activities, $new_tc tags"
  echo "  (Pre-restore state backed up in case you need to undo this too)"
}

# ---------- Parse arguments ----------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)    SINGLE_DATE="$2"; shift 2 ;;
    --from)    FROM_DATE="$2"; shift 2 ;;
    --to)      TO_DATE="$2"; shift 2 ;;
    --all)     DELETE_ALL=true; shift ;;
    --undo)
      UNDO=true
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        UNDO_N="$2"; shift 2
      else
        shift
      fi
      ;;
    --list-backups) LIST_BACKUPS=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --no-backup) NO_BACKUP=true; shift ;;
    -h|--help)  usage ;;
    *)          die "Unknown option: $1" ;;
  esac
done

# ---------- Handle non-delete actions first ----------

if $LIST_BACKUPS; then
  check_db
  list_backups
  exit 0
fi

if $UNDO; then
  check_db
  restore_backup "$UNDO_N"
  exit 0
fi

# ---------- Determine what to delete ----------

# Default: today
if ! $DELETE_ALL && [[ -z "$SINGLE_DATE" ]] && [[ -z "$FROM_DATE" ]]; then
  SINGLE_DATE=$(date "+%Y-%m-%d")
fi

# Single date becomes a one-day range
if [[ -n "$SINGLE_DATE" ]]; then
  FROM_DATE="$SINGLE_DATE"
  TO_DATE="$SINGLE_DATE"
fi

# Validate range
if ! $DELETE_ALL; then
  [[ -n "$FROM_DATE" ]] || die "--from is required (or use --date or --all)"
  [[ -n "$TO_DATE" ]] || TO_DATE="$FROM_DATE"
  [[ "$FROM_DATE" < "$TO_DATE" || "$FROM_DATE" == "$TO_DATE" ]] || die "--from must be before or equal to --to"
fi

check_db

# ---------- Preview what will be deleted ----------

if $DELETE_ALL; then
  label="all-sessions"
  where_clause="1=1"
  display_range="ALL dates"
else
  label="sessions-${FROM_DATE}-to-${TO_DATE}"
  where_clause="date(startedAt) >= '$FROM_DATE' AND date(startedAt) <= '$TO_DATE'"
  display_range="$FROM_DATE to $TO_DATE"
fi

session_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session WHERE $where_clause;")

echo "=== Delete Sessions ==="
echo "  Range: $display_range"
echo "  Sessions to delete: $session_count"

if [[ "$session_count" -eq 0 ]]; then
  echo ""
  echo "  Nothing to delete."
  exit 0
fi

# Show breakdown
echo ""
echo "  Breakdown:"
sqlite3 -separator '|' "$DB_PATH" "
  SELECT
    a.title,
    s.sessionType,
    COUNT(*) as count,
    ROUND(SUM(s.durationSeconds) / 3600.0, 1) as hours
  FROM session s
  JOIN activity a ON a.id = s.activityId
  WHERE $where_clause
  GROUP BY a.title, s.sessionType
  ORDER BY a.title;
" | while IFS='|' read -r title stype count hours; do
  printf "    %-25s %-8s %3s sessions  %5sh\n" "$title" "($stype)" "$count" "$hours"
done

echo ""

if $DRY_RUN; then
  echo "  [dry-run] Would delete $session_count sessions. No changes made."
  exit 0
fi

# ---------- Backup ----------

if ! $NO_BACKUP; then
  echo "--- Creating backup ---"
  create_backup "$label"
fi

# ---------- Delete ----------

echo "--- Deleting ---"
sqlite3 "$DB_PATH" "DELETE FROM session WHERE $where_clause;"

remaining=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session;")
log "Deleted $session_count sessions ($remaining remaining)"

echo ""
echo "=== Done ==="
echo "  Use --undo to restore if needed"
