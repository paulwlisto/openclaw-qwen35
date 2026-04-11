---
name: task-list
description: Enumerate and present current tasks. Use when the user asks what's on their list, what's pending, what's due, for an overview, or for a status check across tasks.
---

# task-list

Produce a sorted summary of all current tasks from `tasks/*.md`.

## Steps

1. `ls` the `tasks/` directory. Capture the list of `.md` files.
2. `read` each task file. Do not skip any.
3. Parse frontmatter from each file. Build an in-memory list of
   `{id, title, priority, dueAt, status}` tuples.
4. Sort by:
   - `status` first — `open` / `in_progress` before `blocked` before `done`
   - `priority` next — `high` → `medium` → `low`
   - `dueAt` next — soonest first (treat `none` as latest)
5. Present a concise summary. Default: top 5 items, one line each:
   title · priority · dueAt (if set) · status. Expand to full list
   only on request.

## Reasoning checks

- Always `ls` first. Never guess which tasks exist from memory.
- Always `read` every file listed. A mental cache is a hallucination
  risk — the last session's knowledge of `tasks/` is stale.
- If `tasks/` is empty or missing, tell the user there are no tasks.
- Do not include files from `archive/` unless the user asked for
  history or a retrospective.
