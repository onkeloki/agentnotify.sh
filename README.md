# agentnotify – Todo.md Completion Watcher

Polls a Markdown file for checkbox changes. Whenever an AI agent (or any other process) flips a checkbox from `[ ]` to `[x]`, a configurable shell command is executed. The completed task text is injected into the command via a `{TODO}` placeholder. New tasks being added are detected and can trigger a separate command. All markers are plain strings – no regex needed.

## Requirements

- macOS or Linux
- Bash ≥ 3.2 (pre-installed on every Mac)
- No external dependencies

## Installation

```bash
git clone https://github.com/onkeloki/agentnotify.sh.git
cd agentnotify.sh

# Make the script executable
chmod +x agentnotify.sh

# Optional: make it globally available
sudo ln -sf "$PWD/agentnotify.sh" /usr/local/bin/agentnotify
```

## Configuration

Copy the example config next to your `Todo.md`:

```bash
cp .agentnotify.conf.example /path/to/my/repo/.agentnotify.conf
```

### All configuration variables

| Variable | Default | Description |
|---|---|---|
| `NOTIFY_COMMAND` | `echo "[agentnotify] Done: {TODO}"` | Command to run when a task is completed |
| `NEW_TASK_COMMAND` | *(empty)* | Command to run when a new task is added (optional) |
| `POLL_INTERVAL` | `2` | Polling interval in seconds |
| `OPEN_MARKER` | `[ ]` | Plain string identifying an **open** task line |
| `DONE_MARKER` | `[x]` | Plain string identifying a **done** task line |

`{TODO}` is replaced at runtime with the task text in both `NOTIFY_COMMAND` and `NEW_TASK_COMMAND`.

### Minimal example config

```bash
POLL_INTERVAL=2

# Fired when a task is checked off
NOTIFY_COMMAND='osascript -e "display notification \"{TODO}\" with title \"\u2713 Done\""'

# Fired when a new task appears (optional)
NEW_TASK_COMMAND='osascript -e "display notification \"{TODO}\" with title \"\U0001f4cb New todo\""'
```

### Custom markers

If your AI agent uses different markers, just set the plain strings:

```bash
# Agent writes [>] for open and [DONE] for completed
OPEN_MARKER='[>]'
DONE_MARKER='[DONE]'
```

## Usage

```bash
# Config is read automatically from .agentnotify.conf next to Todo.md
agentnotify.sh /path/to/Todo.md

# Or pass the config file explicitly
agentnotify.sh /path/to/Todo.md /path/to/my.conf
```

Press `Ctrl+C` to stop the watcher cleanly.

## Supported checkbox formats

The default markers match standard Markdown task lists:

```markdown
- [ ] Open task
* [ ] Open task
  - [ ] Indented open task
- [x] Completed task  ← fires NOTIFY_COMMAND
```

Any newly added `[ ]` line fires `NEW_TASK_COMMAND` (if configured).
Markers are plain strings configured via `OPEN_MARKER` and `DONE_MARKER`.

## Example workflow

**1. Todo.md in your repo:**
```markdown
# Sprint Tasks

- [ ] Implement API endpoint
- [ ] Write unit tests
- [ ] Update documentation
```

**2. `.agentnotify.conf` in the same directory:**
```bash
POLL_INTERVAL=2
NOTIFY_COMMAND='osascript -e "display notification \"{TODO}\" with title \"Agent done\""'
NEW_TASK_COMMAND='echo "$(date): NEW: {TODO}" >> ~/todo.log'
OPEN_MARKER='[ ]'
DONE_MARKER='[x]'
```

**3. Start the watcher:**
```
$ agentnotify.sh ~/projects/myrepo/Todo.md

==================================================
  agentnotify – Todo Watcher
==================================================
[14:32:01] File:          /home/user/projects/myrepo/Todo.md
[14:32:01] Config:        /home/user/projects/myrepo/.agentnotify.conf
[14:32:01] Done command:  osascript -e "display notification ..."
[14:32:01] New command:   echo "$(date): NEW: {TODO}" >> ~/todo.log
[14:32:01] Open marker:   [ ]
[14:32:01] Done marker:   [x]
[14:32:01] Interval:      2s
[14:32:01] Open todos:    3
--------------------------------------------------
```

**4. AI agent checks off a task:**
```markdown
- [x] Implement API endpoint   ← agent set this
- [ ] Write unit tests
- [ ] Update documentation
```

**5. agentnotify detects the change:**
```
[14:35:17] ✓ Done: Implement API endpoint
[14:35:17]   → Running: osascript -e "display notification \"Implement API endpoint\" ..."
```
→ macOS notification appears.

**6. AI agent adds a new task:**
```markdown
- [x] Implement API endpoint
- [ ] Write unit tests
- [ ] Update documentation
- [ ] Deploy to staging   ← agent added this
```
```
[14:36:02] + New todo: Deploy to staging
[14:36:02]   → Running: echo "...: NEW: Deploy to staging" >> ~/todo.log
```

## Chaining multiple actions

Any shell operator can be used inside `NOTIFY_COMMAND` or `NEW_TASK_COMMAND`:

```bash
# Write a log entry AND send a notification on completion
NOTIFY_COMMAND='echo "$(date): {TODO}" >> ~/done.log && osascript -e "display notification \"{TODO}\" with title \"Done\""'

# HTTP push via ntfy.sh
NOTIFY_COMMAND='curl -s -d "{TODO}" ntfy.sh/my-channel'

# Call a custom script (task text as argument)
NOTIFY_COMMAND='/usr/local/bin/my-handler.sh "{TODO}"'

# Log new tasks to a file
NEW_TASK_COMMAND='echo "$(date): NEW: {TODO}" >> ~/todo.log'
```

## Notes

- **File disappears briefly** (e.g. during a git commit): the watcher waits and resumes on the next poll.
- **Task deleted instead of checked**: logged as a warning, no command is fired.
- **Duplicate task texts**: handled correctly – each individual checkbox fires exactly once.
- **`NEW_TASK_COMMAND` not set**: new tasks are only logged to the terminal, no command runs.
