---
name: task-schema
description: Shared file format for task files under tasks/*.md. Read this once per session before performing any task-* operation. Defines frontmatter fields, required values, and naming rules.
---

# task-schema

All task operations share one file format. Task files live at
`tasks/<slug>.md` with YAML frontmatter followed by a free-text body.

## Shape

```
---
id: <slug, matches the filename>
title: <short one-line title>
priority: <high | medium | low>
dueAt: <ISO-8601 with explicit timezone offset, or "none">
status: <open | in_progress | blocked | done>
tags: [<optional list of tags>]
cronJobId: <optional cron job id if a reminder is scheduled>
---
<Free-text body: full context, why it matters, links to related files,
running history of updates, anything needed to act on this task
without asking for clarification.>
```

## Field rules

- **Slug** — lowercase, hyphen-separated, short, descriptive, stable.
  Filename minus `.md` must equal the `id` field. Do not rename a task
  file once created.
- **Priority** — `high` = must happen this week. `medium` = important
  but flexible. `low` = nice to have. Default `medium`.
- **Status** — `open` (new), `in_progress` (actively working),
  `blocked` (waiting on something external — always note what in body),
  `done` (complete; follow the `task-complete` skill to archive).
- **dueAt** — ISO-8601 with an explicit offset (e.g. `+01:00`,
  `-05:00`) or `Z` for UTC. Never a bare local datetime. Use the
  literal string `none` when no time was specified.
- **cronJobId** — set only after scheduling a reminder via the
  `task-schedule` skill. Used for cancellation on completion.
