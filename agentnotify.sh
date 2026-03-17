#!/usr/bin/env bash
# =============================================================================
# agentnotify.sh – Todo.md Completion Watcher
# =============================================================================
# Polls a Markdown file for checkbox changes. Whenever a checkbox flips
# from [ ] to [x], the configured NOTIFY_COMMAND is executed with {TODO}
# replaced by the task text.
#
# Usage:
#   agentnotify.sh <todo_file> [config_file]
#
# Examples:
#   agentnotify.sh ~/projects/myrepo/Todo.md
#   agentnotify.sh ~/projects/myrepo/Todo.md ~/my.conf
#
# The open and done markers are plain strings configured via OPEN_MARKER / DONE_MARKER
# in the config file (matched with grep -F, no regex).
# Defaults:
#   OPEN_MARKER='[ ]'   matches lines containing: - [ ] Task
#   DONE_MARKER='[x]'   matches lines containing: - [x] Task
# =============================================================================

# --------------------------------------------------------------------------- #
#  Helper functions                                                            #
# --------------------------------------------------------------------------- #

usage() {
    cat <<'USAGE'

Usage: agentnotify.sh <todo_file> [config_file]

  todo_file    Path to the Markdown file containing checkboxes
  config_file  Path to the configuration file
               (default: .agentnotify.conf in the same directory as todo_file)

Configuration variables (set in the config file):
  NOTIFY_COMMAND   Shell command to run when a task is completed. {TODO} is
                   replaced with the task text.
  NEW_TASK_COMMAND Shell command to run when a new task is added. {TODO} is
                   replaced with the task text. (optional)
  POLL_INTERVAL    Polling interval in seconds (default: 2)
  OPEN_MARKER      Plain string marking an open task (default: [ ])
  DONE_MARKER      Plain string marking a completed task (default: [x])

Example config (.agentnotify.conf):
  NOTIFY_COMMAND='osascript -e "display notification \"{TODO}\" with title \"Done\""'
  POLL_INTERVAL=2
  OPEN_MARKER='[ ]'
  DONE_MARKER='[x]'

USAGE
    exit 1
}

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log_err() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2
}

# --------------------------------------------------------------------------- #
#  Arguments                                                                   #
# --------------------------------------------------------------------------- #

[[ $# -lt 1 ]] && usage

TODO_FILE="$1"

if [[ ! -f "$TODO_FILE" ]]; then
    log_err "File not found: $TODO_FILE"
    exit 1
fi

# Resolve absolute path without requiring realpath (macOS/Linux compatible)
TODO_FILE="$(cd "$(dirname "$TODO_FILE")" && pwd)/$(basename "$TODO_FILE")"
TODO_DIR="$(dirname "$TODO_FILE")"

CONFIG_FILE="${2:-$TODO_DIR/.agentnotify.conf}"

# --------------------------------------------------------------------------- #
#  Load configuration                                                          #
# --------------------------------------------------------------------------- #

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    log_err "Config file not found: $CONFIG_FILE"
    log_err "Create a config file or pass it as the second argument."
    log_err "See .agentnotify.conf.example for a template."
    echo ""
fi

POLL_INTERVAL="${POLL_INTERVAL:-2}"
OPEN_MARKER="${OPEN_MARKER:-[ ]}"
DONE_MARKER="${DONE_MARKER:-[x]}"
# Use if-blocks for defaults containing {TODO} to avoid bash brace-expansion
# mis-parsing the } in {TODO} as the closing } of ${:-...}
if [[ -z "$NOTIFY_COMMAND" ]]; then
    NOTIFY_COMMAND='echo "[agentnotify] Done: {TODO}"'
fi

# --------------------------------------------------------------------------- #
#  Task extraction (fixed-string matching, no regex)                          #
# --------------------------------------------------------------------------- #

# Extracts the plain text of all open todos
# Returns one task per line, sorted alphabetically
get_open_tasks() {
    grep -F "$OPEN_MARKER" "$TODO_FILE" 2>/dev/null \
        | while IFS= read -r line; do
            echo "${line##*"$OPEN_MARKER "}"
          done \
        | sed 's/[[:space:]]*$//' \
        | sort \
        || true
}

# Extracts the plain text of all completed todos
get_done_tasks() {
    grep -F "$DONE_MARKER" "$TODO_FILE" 2>/dev/null \
        | while IFS= read -r line; do
            echo "${line##*"$DONE_MARKER "}"
          done \
        | sed 's/[[:space:]]*$//' \
        | sort \
        || true
}

# --------------------------------------------------------------------------- #
#  Fire event                                                                  #
# --------------------------------------------------------------------------- #

fire_event() {
    local task_text="$1"
    # Replace {TODO} using bash parameter expansion – no sed, so special
    # characters in the task text are not a problem
    local cmd="${NOTIFY_COMMAND//\{TODO\}/$task_text}"

    log "✓ Done: $task_text"
    log "  → Running: $cmd"
    echo ""

    bash -c "$cmd"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_err "Command exited with code $exit_code: $cmd"
    fi
}

# --------------------------------------------------------------------------- #
#  Temp files & cleanup                                                        #
# --------------------------------------------------------------------------- #

WORK_DIR="$(mktemp -d)"
PREV_OPEN="$WORK_DIR/prev_open"
CURR_OPEN="$WORK_DIR/curr_open"
CURR_DONE="$WORK_DIR/curr_done"
NEWLY_DONE="$WORK_DIR/newly_done"
NEWLY_ADDED="$WORK_DIR/newly_added"

cleanup() {
    rm -rf "$WORK_DIR"
    echo ""
    log "Watcher stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# --------------------------------------------------------------------------- #
#  Start                                                                       #
# --------------------------------------------------------------------------- #

# Take initial snapshot of open tasks
get_open_tasks > "$PREV_OPEN"
OPEN_COUNT=$(wc -l < "$PREV_OPEN" | tr -d ' ')

echo ""
echo "=================================================="
echo "  agentnotify – Todo Watcher"
echo "=================================================="
log "File:          $TODO_FILE"
log "Config:        $CONFIG_FILE"
log "Done command:  $NOTIFY_COMMAND"
log "New command:   ${NEW_TASK_COMMAND:-(not set)}"
log "Open marker:   $OPEN_MARKER"
log "Done marker:   $DONE_MARKER"
log "Interval:      ${POLL_INTERVAL}s"
log "Open todos:    $OPEN_COUNT"
echo "--------------------------------------------------"
echo ""

# --------------------------------------------------------------------------- #
#  Polling loop                                                                #
# --------------------------------------------------------------------------- #

while true; do
    sleep "$POLL_INTERVAL"

    # File may temporarily disappear (e.g. during a git operation)
    if [[ ! -f "$TODO_FILE" ]]; then
        log_err "File gone, waiting... ($TODO_FILE)"
        continue
    fi

    # Capture current state
    get_open_tasks  > "$CURR_OPEN"
    get_done_tasks  > "$CURR_DONE"

    # Newly completed = tasks that were open before but are no longer open
    # AND appear in the done list.
    # comm -23 returns lines only in file 1 (PREV), both files must be sorted.
    comm -23 "$PREV_OPEN" "$CURR_OPEN" > "$NEWLY_DONE"

    # Newly added = tasks that are now open but were not in the previous snapshot.
    # comm -13 returns lines only in file 2 (CURR).
    comm -13 "$PREV_OPEN" "$CURR_OPEN" > "$NEWLY_ADDED"

    # For each potentially completed task, verify it actually has [x]
    while IFS= read -r task; do
        [[ -z "$task" ]] && continue
        # Confirm it is really marked [x] in the file
        # (as opposed to having been simply deleted)
        if grep -qxF "$task" "$CURR_DONE"; then
            fire_event "$task"
        else
            log "⚠ Task removed without [x]: $task"
            echo ""
        fi
    done < "$NEWLY_DONE"

    # Newly added todos
    while IFS= read -r task; do
        [[ -z "$task" ]] && continue
        log "+ New todo: $task"
        if [[ -n "$NEW_TASK_COMMAND" ]]; then
            local_cmd="${NEW_TASK_COMMAND//\{TODO\}/$task}"
            log "  → Running: $local_cmd"
            bash -c "$local_cmd"
            local exit_code=$?
            [[ $exit_code -ne 0 ]] && log_err "Command exited with code $exit_code: $local_cmd"
        fi
        echo ""
    done < "$NEWLY_ADDED"

    # Update snapshot
    cp "$CURR_OPEN" "$PREV_OPEN"
done
