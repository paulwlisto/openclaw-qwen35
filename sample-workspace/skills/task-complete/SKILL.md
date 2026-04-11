---
name: task-complete
description: Mark a task as done and clean up everything attached to it. Use when the user says they finished something, completed a task, or you've verified work is done. Handles cron cancellation and archival.
---

# task-complete

Mark a task done and clean up its cron reminder, HEARTBEAT line, and
move the file into `archive/`.

## Steps

1. Identify the target task by slug. If the user gave a title, `ls
   tasks/` and find the matching filename.
2. `read` the task file. Note the current `status` value and the
   `cronJobId` field (may be absent).
3. `edit` the frontmatter to change `status: <old>` → `status: done`.
4. If the task has a `cronJobId`, call `cron` with
   `action: "remove"` and that `jobId` to cancel any pending reminder.
   Ignore the "not found" error — it just means the job already fired
   or was removed.
5. `read` HEARTBEAT.md and check if the task slug is referenced. If
   it is, `edit` HEARTBEAT.md to remove the matching line.
6. Move the task file from `tasks/<slug>.md` to `archive/<slug>.md`.
   Since there is no move tool, compose it:
   - `read` the updated `tasks/<slug>.md`
   - `write` its content to `archive/<slug>.md`
   - `bash rm tasks/<slug>.md` to remove the original
7. Confirm to the user in one sentence: "Marked <title> done, cleaned
   up reminder and archived."

## Reasoning checks

- Did you remove the cron job BEFORE archiving the file? If not, a
  fired reminder will try to read a file at `tasks/<slug>.md` that no
  longer exists.
- Did you preserve the body of the task in the archived copy? The
  archive is the audit trail — do not strip context.
