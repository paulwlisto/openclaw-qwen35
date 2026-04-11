---
name: task-create
description: Create a new task file when the user asks you to capture, remember, or track something actionable. Use when the user says anything like "add a task", "remind me to", "don't let me forget", or describes work they need to get done.
---

# task-create

Captures a user request as a durable task file under `tasks/<slug>.md`.

## Shared schema

Task files use a YAML frontmatter + markdown body format. Before
writing one, `read` `skills/task-schema/SKILL.md` once per session if
you haven't already — it defines every field and its rules.

## Steps

1. Extract a title from the user request. Derive a short, stable,
   hyphen-separated slug from the title. The slug is the filename
   (minus `.md`) and must match the `id` frontmatter field.
2. If the user mentioned a time, compute `dueAt` from the current
   message metadata + the user's timezone (see AGENTS.md "Current time
   and date" section). Produce ISO-8601 with an explicit offset. If
   no time was mentioned, set `dueAt: none`.
3. Choose priority from context cues:
   - `urgent`, `asap`, `before <deadline>` → `high`
   - plain request → `medium`
   - "when you get a chance" / "eventually" → `low`
   Default `medium` when unclear.
4. `write` `tasks/<slug>.md` with the full frontmatter and a body that
   answers **what, why, and what good looks like**. Err toward more
   context — the future you that acts on this may have nothing else.
5. If the user asked for a reminder at a specific time, follow the
   `task-schedule` skill after this one completes.
6. Confirm to the user what you created in one sentence: title, due
   date, reminder time if any.

## Reasoning checks before writing

- Does the slug already exist under `tasks/`? If yes, either use the
  `task-update` skill or pick a disambiguated slug.
- Is the body self-contained? Would the future you know what to do?
- Is `dueAt` strictly in the future (or the literal string `none`)?
- Does the frontmatter shape match `skills/task-schema/SKILL.md`?
