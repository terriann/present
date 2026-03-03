#!/bin/bash
set -euo pipefail

# Generate sample time-tracking data for testing.
#
# Creates 12 activities (with tags) and populates sessions across a date range
# with randomized work-day patterns for realistic test data.
#
# Weekday structure:
#   - Morning meeting (15-45 min, random: Sprint Planning / Client Meeting / Team Standup)
#   - Lunch break (~30 min timebound around noon)
#   - 3-7 additional work sessions filling 4-9 total hours
#   - Session types: ~60% work, ~25% rhythm (25/5), ~15% timebound (15/30/45 min)
#   - Random activities from all 12, with variety encouraged per day
#
# Weekend behavior:
#   - Without --weekends: ~10% chance of sessions per weekend day
#   - With --weekends: all weekend days get sessions
#   - Weekend days: 1-3 sessions, 1-3 hours total
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

# Number of defined activities (for random selection)
ACTIVITY_COUNT=${#ACTIVITIES[@]}

# ---------- Helpers ----------

usage() {
  sed -n '4,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
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

# Random integer in [min, max] inclusive
rand_range() {
  local min="$1" max="$2"
  echo $(( RANDOM % (max - min + 1) + min ))
}

# Pick a random activity index (0..ACTIVITY_COUNT-1)
rand_activity() {
  echo $(( RANDOM % ACTIVITY_COUNT ))
}

# Pick a random session type: ~60% work, ~25% rhythm, ~15% timebound
rand_session_type() {
  local roll=$(( RANDOM % 100 ))
  if (( roll < 60 )); then
    echo "work"
  elif (( roll < 85 )); then
    echo "rhythm"
  else
    echo "timebound"
  fi
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
weekend_days=0

while [[ "$current_date" < "$TO_DATE" || "$current_date" == "$TO_DATE" ]]; do
  dow=$(day_of_week "$current_date")
  is_weekend=false
  if [[ "$dow" -gt 5 ]]; then
    is_weekend=true
  fi

  # Skip weekends unless --weekends flag or ~10% random chance
  if $is_weekend && ! $WEEKENDS; then
    roll=$(( RANDOM % 10 ))
    if (( roll != 0 )); then
      current_date=$(date_add_days "$current_date" 1)
      continue
    fi
    weekend_days=$(( weekend_days + 1 ))
  fi

  day_minutes=0
  day_sessions=0

  if $is_weekend; then
    # Weekend: 1-3 sessions, 1-3 hours total
    num_sessions=$(rand_range 1 3)
    target_minutes=$(rand_range 60 180)
  else
    # Weekday: 3-7 sessions, 4-9 hours
    num_sessions=$(rand_range 3 7)
    target_hours=$(rand_range 4 9)
    target_minutes=$(( target_hours * 60 ))
  fi

  # Random start: 8-10 AM with 0-45 min jitter
  start_hour=$(rand_range 8 10)
  start_jitter=$(rand_range 0 45)
  cursor_minutes=$(( start_hour * 60 + start_jitter ))

  # --- Weekday: add a meeting in the morning and lunch around noon ---
  if ! $is_weekend; then
    # Morning meeting: pick from Sprint Planning (2), Client Meeting (8), Team Standup (9)
    meeting_activities=(2 8 9)
    meeting_idx=${meeting_activities[$(( RANDOM % 3 ))]}
    meeting_id="${ACTIVITY_ID_LIST[$meeting_idx]:-}"
    meeting_dur=$(rand_range 15 45)
    if [[ -n "$meeting_id" ]] && { [[ "$meeting_id" != "0" ]] || $DRY_RUN; }; then
      adj_hour=$(( cursor_minutes / 60 ))
      adj_min=$(( cursor_minutes % 60 ))
      started_at=$(printf "%sT%02d:%02d:00" "$current_date" "$adj_hour" "$adj_min")
      end_total=$(( cursor_minutes + meeting_dur ))
      ended_at=$(printf "%sT%02d:%02d:00" "$current_date" $(( end_total / 60 )) $(( end_total % 60 )))
      run "$CLI session add $meeting_id --started-at $started_at --ended-at $ended_at --type work -f text"
      day_minutes=$(( day_minutes + meeting_dur ))
      day_sessions=$(( day_sessions + 1 ))
      session_count=$(( session_count + 1 ))
      gap=$(rand_range 5 15)
      cursor_minutes=$(( cursor_minutes + meeting_dur + gap ))
    fi

    # Lunch: ~30 min timebound around noon (11:30-12:30 start)
    lunch_id="${ACTIVITY_ID_LIST[11]:-}"  # Rest & Recovery
    lunch_start=$(rand_range 690 750)     # 11:30 (690) to 12:30 (750)
    # Only insert lunch if cursor hasn't already passed lunch time
    if (( cursor_minutes < lunch_start )); then
      lunch_cursor=$lunch_start
    else
      lunch_cursor=$(( cursor_minutes + 5 ))
    fi
    if [[ -n "$lunch_id" ]] && { [[ "$lunch_id" != "0" ]] || $DRY_RUN; }; then
      started_at=$(printf "%sT%02d:%02d:00" "$current_date" $(( lunch_cursor / 60 )) $(( lunch_cursor % 60 )))
      end_total=$(( lunch_cursor + 30 ))
      ended_at=$(printf "%sT%02d:%02d:00" "$current_date" $(( end_total / 60 )) $(( end_total % 60 )))
      run "$CLI session add $lunch_id --started-at $started_at --ended-at $ended_at --type timebound --minutes 30 -f text"
      day_minutes=$(( day_minutes + 30 ))
      day_sessions=$(( day_sessions + 1 ))
      session_count=$(( session_count + 1 ))
      gap=$(rand_range 10 25)
      cursor_minutes=$(( lunch_cursor + 30 + gap ))
    fi
  fi

  # Distribute remaining target across random sessions with ±20% variance
  remaining_target=$(( target_minutes - day_minutes ))
  if (( remaining_target < 60 )); then remaining_target=60; fi
  base_duration=$(( remaining_target / num_sessions ))

  # Track activities used today to encourage variety
  used_activities=()

  for (( s=0; s<num_sessions; s++ )); do
    # Random activity, prefer unused ones (skip meeting/lunch activities already used)
    attempts=0
    act_idx=$(rand_activity)
    while [[ " ${used_activities[*]:-} " == *" $act_idx "* ]] && (( attempts < 5 )); do
      act_idx=$(rand_activity)
      attempts=$(( attempts + 1 ))
    done
    used_activities+=("$act_idx")

    # Get activity ID (use placeholder in dry-run mode)
    act_id="${ACTIVITY_ID_LIST[$act_idx]:-}"
    if [[ -z "$act_id" ]]; then
      continue
    fi
    if [[ "$act_id" == "0" ]] && ! $DRY_RUN; then
      continue
    fi

    # Duration with ±20% variance
    variance=$(( base_duration * 20 / 100 ))
    if (( variance < 1 )); then variance=1; fi
    min_dur=$(( base_duration - variance ))
    max_dur=$(( base_duration + variance ))
    if (( min_dur < 10 )); then min_dur=10; fi
    duration_min=$(rand_range "$min_dur" "$max_dur")

    # Last session absorbs remainder to hit target
    if (( s == num_sessions - 1 )); then
      remaining=$(( target_minutes - day_minutes ))
      if (( remaining > 10 )); then
        duration_min=$remaining
      fi
    fi

    # Session type (last session is always work to absorb remainder)
    timer_min=""
    break_min=""

    if (( s == num_sessions - 1 )); then
      stype="work"
    else
      stype=$(rand_session_type)
    fi

    if [[ "$stype" == "rhythm" ]]; then
      timer_min=25
      break_min=5
      # Rhythm sessions are always 25 min focus
      duration_min=25
    elif [[ "$stype" == "timebound" ]]; then
      # Random timer: 15, 30, or 45 min
      timer_options=(15 30 45)
      timer_min=${timer_options[$(( RANDOM % 3 ))]}
      duration_min=$timer_min
    fi

    # Compute timestamps
    adj_hour=$(( cursor_minutes / 60 ))
    adj_min=$(( cursor_minutes % 60 ))
    started_at=$(printf "%sT%02d:%02d:00" "$current_date" "$adj_hour" "$adj_min")

    end_total=$(( cursor_minutes + duration_min ))
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

    # Gap between sessions: 5-30 min
    gap=$(rand_range 5 30)
    cursor_minutes=$(( cursor_minutes + duration_min + gap ))
  done

  total_minutes=$(( total_minutes + day_minutes ))
  day_count=$(( day_count + 1 ))
  day_hours=$(echo "scale=1; $day_minutes / 60" | bc)
  day_label="$current_date ($( date -j -f "%Y-%m-%d" "$current_date" "+%A" ))"
  if $is_weekend; then
    day_label="$day_label [weekend]"
  fi
  log "$day_label: ${day_sessions} sessions, ${day_hours}h"

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
summary="  Days: $day_count | Sessions: $session_count | Total: ${total_hours}h | Avg: ${avg_hours}h/day"
if (( weekend_days > 0 )); then
  summary="$summary | Weekend days: $weekend_days"
fi
echo "$summary"
