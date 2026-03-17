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
# Supported checkbox formats:
#   - [ ] Open task
#   * [ ] Open task
#     [ ] Indented open task
#   - [x] Completed task
#   - [X] Completed task (uppercase X also works)
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
  POLL_INTERVAL    Polling interval in seconds (default: 2)

Example config (.agentnotify.conf):
  NOTIFY_COMMAND='osascript -e "display notification \"{TODO}\" with title \"Done\""'
  POLL_INTERVAL=2

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

NOTIFY_COMMAND="${NOTIFY_COMMAND:-echo \"[agentnotify] Done: {TODO}\"}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"

# --------------------------------------------------------------------------- #
#  Task extraction (BSD grep & sed compatible, no grep -P required)           #
# --------------------------------------------------------------------------- #

# Extracts the plain text of all open todos ([ ])
# Returns one task per line, sorted alphabetically
get_open_tasks() {
    grep -E '\[ \]' "$TODO_FILE" 2>/dev/null \
        | sed 's/.*\[ \] //' \
        | sed 's/[[:space:]]*$//' \
        | sort \
        || true
}

# Extracts the plain text of all completed todos ([x] or [X])
get_done_tasks() {
    {
        grep -E '\[x\]' "$TODO_FILE" 2>/dev/null | sed 's/.*\[x\] //'
        grep -E '\[X\]' "$TODO_FILE" 2>/dev/null | sed 's/.*\[X\] //'
    } \
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
log "File:     $TODO_FILE"
log "Config:   $CONFIG_FILE"
log "Command:  $NOTIFY_COMMAND"
log "Interval: ${POLL_INTERVAL}s"
log "Open todos: $OPEN_COUNT"
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

    # Update snapshot
    cp "$CURR_OPEN" "$PREV_OPEN"
done
