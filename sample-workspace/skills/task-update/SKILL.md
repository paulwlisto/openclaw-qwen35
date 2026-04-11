---
name: task-update
description: Change a single field on an existing task, or append notes to its body. Use when the user asks to change a priority, reschedule, add context, mark in-progress, or unblock. Does not cover marking tasks done — use task-complete for that.
---

# task-update

Modify an existing task file under `tasks/*.md`.

## Steps

1. Identify the task by slug. If the user gave a title or description
   instead, `ls tasks/` and find the closest matching filename.
2. `read` the current task file to see the existing frontmatter and
   body. This is required — never edit blind.
3. For a **single-field change** (priority, status, dueAt, tags), use
   `edit` to replace the exact old frontmatter line with the new one.
   Treat the line as one unit including its leading whitespace. Do
   not rewrite the whole file.
4. For a **body addition** (notes, status update, running history),
   use read-then-write: concatenate the existing content with a new
   paragraph and `write` the result back.
5. Confirm the change to the user in one sentence.

## Reasoning checks

- Did you `read` the file before editing? Required every time.
- Is your `edit` `oldText` **exactly one line** from the file,
  including indentation and trailing characters?
- If `edit` fails with "could not find exact text", **stop retrying
  with different anchors**. Switch to read-then-write for the same
  change.
- Never use `write` to change a single field — only use `write` when
  replacing the whole file and you have just read the current state.

## Special cases

- **Marking done** — use the `task-complete` skill, not this one.
- **Rescheduling** — update `dueAt` here, then call `cron` with
  `action: "update"` and the existing `cronJobId` from frontmatter.
  Do not create a new cron job; that would leave a dangling old one.
