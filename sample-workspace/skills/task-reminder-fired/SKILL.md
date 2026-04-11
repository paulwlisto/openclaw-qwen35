---
name: task-reminder-fired
description: Handle an incoming cron-delivered systemEvent that is a task reminder. Use when you see a systemEvent in the conversation that references a task file path. Re-reads the task and delivers the reminder to the user.
---

# task-reminder-fired

Process a cron-delivered reminder event for a specific task.

## Trigger

A systemEvent arrives in this session whose text contains a task file
path (e.g. "reminder: check tasks/email-foo-bar.md"). The event was
scheduled earlier by the `task-schedule` skill.

## Steps

1. Extract the task file path from the event text. The convention is
   that `task-schedule` embeds a path of the form `tasks/<slug>.md`.
2. `read` the task file at that path. Required — do not act on the
   event text alone, the task may have been updated since the
   reminder was scheduled (priority changed, body extended, status
   already moved to done, etc.).
3. If the task is already `done`:
   - Do nothing visible to the user.
   - Clean up: remove the cron job via its id if still present, and
     ensure the file is archived (see `task-complete` skill).
   - Stop here.
4. If the task is still open/in_progress/blocked: compose a reminder
   message to the user. Include:
   - Task title
   - Current priority and status
   - The body context (or a summary if long)
   - A suggested next action
5. Send the message via the `message` tool to the user's configured
   channel.
6. Optionally, if the user wants to mark it done in their reply,
   follow the `task-complete` skill next turn.

## Reasoning checks

- Did you `read` the actual task file, not just act on the event
  text? Required.
- Did you check `status`? Don't remind about done tasks.
- Are you inside quiet hours (22:00–06:00 in user's timezone)? If
  yes and this reminder was explicitly scheduled for inside that
  window by the user, proceed. If the fire time drifted into quiet
  hours by accident, still deliver — the user set it deliberately
  when they scheduled.
