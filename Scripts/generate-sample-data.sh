#!/bin/bash
set -euo pipefail

# Generate sample time-tracking data for testing.
#
# Creates activities, tags, and sessions across a date range with realistic
# work-day patterns averaging ~4.5 hours per weekday.
#
# Usage:
#   ./scripts/generate-sample-data.sh                          # Current week (Mon-Fri)
#   ./scripts/generate-sample-data.sh --from 2026-02-01 --to 2026-02-28
#   ./scripts/generate-sample-data.sh --from 2026-02-10 --to 2026-02-14 --clean
#   ./scripts/generate-sample-data.sh --reset                  # Wipe ALL data, recreate activities/tags
#   ./scripts/generate-sample-data.sh --weekends               # Include Sat/Sun
#
# Options:
#   --from DATE     Start date (YYYY-MM-DD, default: Monday of current week)
#   --to DATE       End date (YYYY-MM-DD, default: Friday of current week)
#   --clean         Remove existing sessions in the date range before generating
#   --reset         Wipe ALL activities, sessions, and tags, then recreate the sample set
#   --weekends      Generate sessions on weekends too (default: weekdays only)
#   --dry-run       Print what would be generated without executing
#   -h, --help      Show this help

DB_PATH="$HOME/Library/Application Support/Present/present.sqlite"
CLI="swift run present-cli"
DRY_RUN=false
CLEAN=false
RESET=false
WEEKENDS=false
FROM_DATE=""
TO_DATE=""

# ---------- Sample data definitions ----------

# Activities: "Name|tag1,tag2"
ACTIVITIES=(
  "App Development|Engineering"
  "Code Review|Engineering"
  "Sprint Planning|Engineering,Meetings"
  "API Integration|Engineering"
  "CLI Refactor|Engineering"
  "Bug Triage|Engineering"
  "Design System|Design"
  "Documentation|Writing"
  "Client Meeting|Meetings"
  "Team Standup|Meetings"
  "Research & Learning|Growth"
  "Rest & Recovery|Personal"
)

TAG_NAMES=("Engineering" "Design" "Writing" "Meetings" "Growth" "Personal")

# Parallel array for tag IDs (populated at runtime, same index as TAG_NAMES)
TAG_IDS=()

# Parallel array for activity IDs (populated at runtime, same index as ACTIVITIES)
ACTIVITY_ID_LIST=()

# Session templates: "activity_index|start_hour|duration_minutes|type|timer_min|break_min"
# Day shapes are picked based on day-of-year to add variety

# Shape A: Heavy focus day (~5.5h / 330min)
SHAPE_A=(
  "0|09:00|150|work||"
  "1|11:45|60|work||"
  "8|13:30|60|work||"
  "7|14:45|60|work||"
)

# Shape B: Standard sprint day (~4.5h / 270min)
SHAPE_B=(
  "9|09:00|15|work||"
  "3|09:30|90|work||"
  "5|11:15|75|work||"
  "1|13:00|60|work||"
  "4|14:15|30|rhythm|25|5"
)

# Shape C: Deep work marathon (~6h / 360min)
SHAPE_C=(
  "0|09:00|25|rhythm|25|5"
  "0|09:30|25|rhythm|25|5"
  "0|10:00|25|rhythm|25|5"
  "0|10:30|25|rhythm|25|5"
  "6|11:15|90|work||"
  "10|13:00|90|work||"
  "7|14:45|80|work||"
)

# Shape D: Meeting-heavy day (~4h / 240min)
SHAPE_D=(
  "9|09:00|15|work||"
  "2|09:30|60|work||"
  "8|10:45|45|work||"
  "0|11:45|45|work||"
  "1|13:30|45|work||"
  "7|14:30|30|work||"
)

# Shape E: Light day (~3.5h / 210min)
SHAPE_E=(
  "10|09:00|45|work||"
  "3|10:00|75|work||"
  "5|13:00|45|work||"
  "0|14:00|45|work||"
)

# Shape F: Weekend casual (~2.25h, if --weekends)
SHAPE_F=(
  "11|10:00|30|work||"
  "10|11:00|60|work||"
  "6|14:00|45|work||"
)

# ---------- Helpers ----------

usage() {
  sed -n '3,/^$/s/^# \?//p' "$0"
  exit 0
}

log() { echo "  $*"; }
run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
  else
    eval "$@" 2>/dev/null || true
  fi
}

date_add_days() {
  local base="$1" days="$2"
  date -j -v+"${days}d" -f "%Y-%m-%d" "$base" "+%Y-%m-%d"
}

day_of_week() {
  # Returns 1=Mon .. 7=Sun
  date -j -f "%Y-%m-%d" "$1" "+%u"
}

# Look up a tag ID by name from parallel arrays
get_tag_id() {
  local name="$1"
  local i
  for (( i=0; i<${#TAG_NAMES[@]}; i++ )); do
    if [[ "${TAG_NAMES[$i]}" == "$name" ]]; then
      echo "${TAG_IDS[$i]:-}"
      return
    fi
  done
}

# ---------- Parse arguments ----------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)   FROM_DATE="$2"; shift 2 ;;
    --to)     TO_DATE="$2"; shift 2 ;;
    --clean)  CLEAN=true; shift ;;
    --reset)  RESET=true; shift ;;
    --weekends) WEEKENDS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Default date range: current week Mon-Fri
if [[ -z "$FROM_DATE" ]]; then
  dow=$(date "+%u")
  offset=$(( dow - 1 ))
  FROM_DATE=$(date -j -v-"${offset}d" "+%Y-%m-%d")
fi
if [[ -z "$TO_DATE" ]]; then
  dow=$(date -j -f "%Y-%m-%d" "$FROM_DATE" "+%u")
  offset=$(( 5 - dow ))
  TO_DATE=$(date_add_days "$FROM_DATE" "$offset")
fi

echo "=== Present Sample Data Generator ==="
echo "  Range: $FROM_DATE to $TO_DATE"
echo "  Clean: $CLEAN | Reset: $RESET | Weekends: $WEEKENDS | Dry run: $DRY_RUN"
echo ""

# ---------- Reset (wipe everything) ----------

if $RESET; then
  echo "--- Resetting all data ---"
  if ! $DRY_RUN; then
    if [[ ! -f "$DB_PATH" ]]; then
      echo "  No database found at $DB_PATH, skipping reset."
    else
      # Get all activity IDs and delete them (cascades to sessions)
      activity_ids=$($CLI activity list -f json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data:
    print(a['id'])
" 2>/dev/null || true)

      for aid in $activity_ids; do
        log "Deleting activity $aid..."
        $CLI activity delete "$aid" -f text 2>/dev/null || true
      done

      # Delete all tags
      tag_ids=$($CLI tag list -f json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data:
    print(t['id'])
" 2>/dev/null || true)

      for tid in $tag_ids; do
        log "Deleting tag $tid..."
        $CLI tag delete "$tid" -f text 2>/dev/null || true
      done
    fi
  else
    log "[dry-run] Would delete all activities, sessions, and tags"
  fi
  echo ""
fi

# ---------- Ensure tags exist ----------

echo "--- Ensuring sample tags ---"

for tag_name in "${TAG_NAMES[@]}"; do
  if $DRY_RUN; then
    log "[dry-run] Create tag: $tag_name"
    TAG_IDS+=("0")
  else
    existing_id=$($CLI tag list -f json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data:
    if t['name'] == '$tag_name':
        print(t['id'])
        break
" 2>/dev/null || true)

    if [[ -n "$existing_id" ]]; then
      TAG_IDS+=("$existing_id")
      log "Tag exists: $tag_name (#$existing_id)"
    else
      new_id=$($CLI tag add "$tag_name" --field id 2>/dev/null)
      TAG_IDS+=("$new_id")
      log "Created tag: $tag_name (#$new_id)"
    fi
  fi
done

# ---------- Ensure activities exist ----------

echo "--- Ensuring sample activities ---"

for entry in "${ACTIVITIES[@]}"; do
  IFS='|' read -r name tag_csv <<< "$entry"

  if $DRY_RUN; then
    log "[dry-run] Create activity: $name (tags: $tag_csv)"
    ACTIVITY_ID_LIST+=("0")
  else
    existing_id=$($CLI activity list -f json 2>/dev/null | python3 -c "
import json, sys
name = '''$name'''
data = json.load(sys.stdin)
for a in data:
    if a['title'] == name and not a.get('isArchived', False):
        print(a['id'])
        break
" 2>/dev/null || true)

    if [[ -n "$existing_id" ]]; then
      ACTIVITY_ID_LIST+=("$existing_id")
      log "Activity exists: $name (#$existing_id)"
    else
      new_id=$($CLI activity add "$name" --field id 2>/dev/null)
      ACTIVITY_ID_LIST+=("$new_id")
      log "Created activity: $name (#$new_id)"

      # Assign tags
      IFS=',' read -ra tag_names_list <<< "$tag_csv"
      for tn in "${tag_names_list[@]}"; do
        tid=$(get_tag_id "$tn")
        if [[ -n "$tid" ]]; then
          $CLI activity tag add "$new_id" "$tid" -f text 2>/dev/null || true
        fi
      done
    fi
  fi
done
echo ""

# ---------- Clean existing sessions in range ----------

if $CLEAN && ! $RESET; then
  echo "--- Cleaning sessions from $FROM_DATE to $TO_DATE ---"
  if $DRY_RUN; then
    log "[dry-run] Would delete completed sessions in range via SQLite"
  else
    if [[ -f "$DB_PATH" ]]; then
      deleted=$(sqlite3 "$DB_PATH" "
        SELECT COUNT(*) FROM session
        WHERE date(startedAt) >= '$FROM_DATE'
          AND date(startedAt) <= '$TO_DATE'
          AND state = 'completed';
      ")
      sqlite3 "$DB_PATH" "
        DELETE FROM session
        WHERE date(startedAt) >= '$FROM_DATE'
          AND date(startedAt) <= '$TO_DATE'
          AND state = 'completed';
      "
      log "Deleted $deleted completed sessions in range"
    else
      log "No database found, skipping clean"
    fi
  fi
  echo ""
fi

# ---------- Generate sessions ----------

echo "--- Generating sessions ---"

current_date="$FROM_DATE"
session_count=0
total_minutes=0
day_count=0

while [[ "$current_date" < "$TO_DATE" || "$current_date" == "$TO_DATE" ]]; do
  dow=$(day_of_week "$current_date")

  # Skip weekends unless requested
  if [[ "$dow" -gt 5 ]] && ! $WEEKENDS; then
    current_date=$(date_add_days "$current_date" 1)
    continue
  fi

  # Pick a day shape based on day-of-year for variety
  day_num=$(date -j -f "%Y-%m-%d" "$current_date" "+%j" | sed 's/^0*//')

  if [[ "$dow" -gt 5 ]]; then
    shape_ref="SHAPE_F[@]"
  else
    shapes=("SHAPE_A" "SHAPE_B" "SHAPE_C" "SHAPE_D" "SHAPE_E")
    shape_idx=$(( day_num % ${#shapes[@]} ))
    shape_ref="${shapes[$shape_idx]}[@]"
  fi

  day_minutes=0
  day_sessions=0
  shape=("${!shape_ref}")

  # Add time jitter per day (shift all sessions by 0-24 min) for realism
  jitter=$(( day_num % 4 * 8 ))

  for template in "${shape[@]}"; do
    IFS='|' read -r act_idx start_time duration_min stype timer_min break_min <<< "$template"

    # Get activity ID from the parallel array
    act_id="${ACTIVITY_ID_LIST[$act_idx]:-}"
    if [[ -z "$act_id" || "$act_id" == "0" ]]; then
      continue
    fi

    # Parse start time and add jitter
    start_hour="${start_time%%:*}"
    start_min="${start_time##*:}"
    start_total=$(( 10#$start_hour * 60 + 10#$start_min + jitter ))
    adj_hour=$(( start_total / 60 ))
    adj_min=$(( start_total % 60 ))
    started_at=$(printf "%sT%02d:%02d:00" "$current_date" "$adj_hour" "$adj_min")

    end_total=$(( start_total + duration_min ))
    end_hour=$(( end_total / 60 ))
    end_min=$(( end_total % 60 ))
    ended_at=$(printf "%sT%02d:%02d:00" "$current_date" "$end_hour" "$end_min")

    # Build command
    cmd="$CLI session add $act_id --started-at $started_at --ended-at $ended_at --type $stype"
    if [[ -n "$timer_min" ]]; then
      cmd="$cmd --minutes $timer_min"
    fi
    if [[ -n "$break_min" ]]; then
      cmd="$cmd --break-minutes $break_min"
    fi
    cmd="$cmd -f text"

    run "$cmd"

    day_minutes=$(( day_minutes + duration_min ))
    day_sessions=$(( day_sessions + 1 ))
    session_count=$(( session_count + 1 ))
  done

  total_minutes=$(( total_minutes + day_minutes ))
  day_count=$(( day_count + 1 ))
  day_hours=$(echo "scale=1; $day_minutes / 60" | bc)
  log "$current_date ($( date -j -f "%Y-%m-%d" "$current_date" "+%A" )): ${day_sessions} sessions, ${day_hours}h"

  current_date=$(date_add_days "$current_date" 1)
done

echo ""
total_hours=$(echo "scale=1; $total_minutes / 60" | bc)
if [[ "$day_count" -gt 0 ]]; then
  avg_hours=$(echo "scale=1; $total_minutes / $day_count / 60" | bc)
else
  avg_hours="0"
fi
echo "=== Done ==="
echo "  Days: $day_count | Sessions: $session_count | Total: ${total_hours}h | Avg: ${avg_hours}h/day"
