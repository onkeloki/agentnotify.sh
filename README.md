# agentnotify – Todo.md Completion Watcher

Polls a Markdown file for checkbox changes. Whenever an AI agent (or any other process) flips a checkbox from `[ ]` to `[x]`, a configurable shell command is executed. The completed task text is injected into the command via a `{TODO}` placeholder.

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

Open `.agentnotify.conf` and enable the desired `NOTIFY_COMMAND`:

```bash
# Polling interval in seconds
POLL_INTERVAL=2

# macOS system notification
NOTIFY_COMMAND='osascript -e "display notification \"{TODO}\" with title \"✓ Done\""'
```

`{TODO}` is replaced at runtime with the text after `[x]`.

## Usage

```bash
# Config is read automatically from .agentnotify.conf next to Todo.md
agentnotify.sh /path/to/Todo.md

# Or pass the config file explicitly
agentnotify.sh /path/to/Todo.md /path/to/my.conf
```

Press `Ctrl+C` to stop the watcher cleanly.

## Supported checkbox formats

```markdown
- [ ] Open task
* [ ] Open task
  - [ ] Indented open task
- [x] Completed task  ← fires event
- [X] Completed task  ← fires event (uppercase X also works)
```

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
```

**3. Start the watcher:**
```
$ agentnotify.sh ~/projects/myrepo/Todo.md

==================================================
  agentnotify – Todo Watcher
==================================================
[14:32:01] File:     /home/user/projects/myrepo/Todo.md
[14:32:01] Config:   /home/user/projects/myrepo/.agentnotify.conf
[14:32:01] Command:  osascript -e "display notification ..."
[14:32:01] Interval: 2s
[14:32:01] Open todos: 3
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

## Chaining multiple actions

Any shell operator can be used inside `NOTIFY_COMMAND`:

```bash
# Write a log entry AND send a notification
NOTIFY_COMMAND='echo "$(date): {TODO}" >> ~/done.log && osascript -e "display notification \"{TODO}\" with title \"Done\""'

# HTTP push via ntfy.sh
NOTIFY_COMMAND='curl -s -d "{TODO}" ntfy.sh/my-channel'

# Call a custom script (task text as argument)
NOTIFY_COMMAND='/usr/local/bin/my-handler.sh "{TODO}"'
```

## Notes

- **File disappears briefly** (e.g. during a git commit): the watcher waits and resumes on the next poll.
- **Task deleted instead of checked**: logged as a warning, no command is fired.
- **Duplicate task texts**: handled correctly – each individual checkbox fires exactly once.
