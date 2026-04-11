---
title: "TOOLS.md Template"
summary: "Workspace template — how to use tools and compose them. Loaded on demand by the agent."
read_when:
  - Bootstrapping a workspace manually
  - The agent needs a refresher on a tool or compositional pattern
---

# TOOLS.md — How to use your tools and compose them

Reference guide for the primitive tools you have and the patterns that
turn them into higher-level capabilities (task management, reminders,
follow-ups). Loaded on demand — read it when you need a refresher on a
tool or a compositional pattern. Details live here so AGENTS.md can stay
short.

All structural guidance below is **shape-only**. Fill in real values from
the current user message metadata, USER.md, and the task at hand. Do not
copy literal field values from this file — they are placeholders.

---

## How to call tools well

A small reasoning discipline that makes tool calls far more likely to
succeed on the first attempt:

1. **State the intent before the call.** In a brief internal step, name
   the goal ("I need to append a line to HEARTBEAT.md"), the tool you
   will use, and why it is the right tool. This catches wrong-tool errors
   before they happen.
2. **Match the schema exactly.** Send only fields the tool expects. Nested
   objects must be real JSON objects, never strings. Required fields are
   required; optional fields should be omitted unless you have a value.
3. **Every argument is an object, not a stringified blob.** If you find
   yourself writing `"{...}"` as the value of a field, you are wrong.
   Unwrap it into a proper nested object.
4. **Read error responses.** When a call fails, the error tells you which
   field was wrong. Adjust **one** thing and retry. Do not retry the
   exact same shape. Do not invent new wrong shapes.
5. **Stop after two failed attempts.** If the same tool has failed twice
   in a row on the same intent, stop calling it. Summarise the failure
   for your human in plain language and ask for clarification or a
   different approach. Spinning in a retry loop is never the answer.
6. **For multi-step work, plan before executing.** If a task needs 3+
   tool calls, describe the plan in one short paragraph first, then
   execute it step by step.

---

## File tools

### `read`

Load a file's contents so you can reason about or modify it. The `path`
argument is the absolute workspace path to the file. Always read before
editing — do not edit blind.

### `write`

Write the **entire** contents of a file. Takes two required arguments:
`path` (the absolute workspace path) and `content` (the full file
contents to write). **You MUST include `path` on every call** — without
it the tool fails. It sits at the **top level alongside `content`**,
never inside the content array. Destructive: overwrites anything already
there. Only safe when:

- creating a brand-new file, or
- you already read the existing content and are writing back a value that
  contains the old content **plus** your changes.

Never use `write` with partial content on an existing file. You will
destroy whatever was there before.

**Common mistake:** Forgetting that `path` is a top-level field, not
nested inside `content`. This causes "Missing required parameter: path
alias" errors.

### `edit`

Replace an **exact** substring inside a file. Required arguments: `path`
(absolute workspace path) and an `edits` array containing one or more
replacements. **You MUST include `path` on every call** — it sits at the
**top level alongside `edits`**, never inside the edits array.

```json
{
  "path": "/absolute/path/to/file.md",
  "edits": [
    { "oldText": "<exact text to find>", "newText": "<replacement>" }
  ]
}
```

Every whitespace character and newline in `oldText` must match literally
— this is not a fuzzy or regex match. Use multiple entries in the
`edits` array to make several replacements in one call.

**Common mistake:** Forgetting that `path` is a top-level field, not
nested inside `edits`. This causes "Missing required parameter: path
alias" errors.

**Failure recovery.** If `edit` reports "Could not find the exact text",
**do not retry with a different anchor string**. Switch strategies:

1. `read` the file to see its current contents.
2. Compute the new content as `<old content> + <your change>` or a
   surgical modification of the old content.
3. `write` the result back.

This read-then-write fallback is slower but cannot fail on whitespace.

### Appending to a file

There is no `append` tool. To append, do read-then-write:

1. `read` the file.
2. Concatenate the existing content with your new content.
3. `write` the concatenation back.

Never skip the read. Never write only the new content to an existing
file.

---

## `cron` — scheduling

Schedule jobs against the gateway cron scheduler. Owner-only tool.

### Actions

- `status`, `list`, `add`, `update`, `remove`, `run`, `runs`, `wake`

**The #1 mistake: flattening nested objects.** `schedule` and `payload`
are nested objects, not prefixes. There is **no** `payloadKind`,
`scheduleKind`, or top-level `at` field. If you emit those, every call
fails and no amount of retrying will fix it — you have to restructure.

### `cron.add` — the canonical shape

```json
{
  "action": "add",
  "job": {
    "name": "<kebab-case-identifier>",
    "description": "<one line description>",
    "schedule": { "kind": "at", "at": "<ISO-8601 timestamp with offset>" },
    "payload": { "kind": "systemEvent", "text": "<reminder text>" },
    "sessionTarget": "main"
  }
}
```

The top level has exactly two keys: `action` and `job`. ALL other fields
(`name`, `description`, `schedule`, `payload`, `sessionTarget`) live
INSIDE the `job` object as siblings of each other.

### Messaging the user from cron

Cron does **not** send messages directly. It wakes an agent, and the
agent decides whether to call `message`. The default and most common
case: `payload.kind = "systemEvent"`, `payload.text = "<wake-up text>"`,
`sessionTarget = "main"`. This injects a system-event turn into your
main session, and you (the main agent) wake up with the event as
context and decide what to do next — typically call `message` to DM the
human. Best for reminders, digests, and any prompt where your
conversation context should stay intact.

### `schedule.kind` — three variants

The `schedule` object's `kind` field selects the scheduling mode:

- `at` — one-shot at a specific time. Provide `schedule.at` as an
  ISO-8601 timestamp with explicit offset.
- `cron` — recurring on a cron expression. Provide `schedule.expr` (a
  standard 5-field cron expression) and optionally `schedule.tz` (an
  IANA timezone like `Europe/London` or `America/New_York` — use the
  one configured for your human in USER.md).
- `every` — recurring on a fixed interval. Provide `schedule.everyMs`
  as the interval in milliseconds.

Hard rules:
- `name` is **required** (short stable identifier, kebab-case).
- `payload`, `schedule`, and `sessionTarget` are **all required** AND
  are fields INSIDE `job`. Never put them at the top level.
- `schedule` and `payload` are nested objects with their OWN `kind`
  field plus the matching value field. They are never strings or empty
  objects.
- Timestamps in `schedule.at` MUST carry an explicit offset (e.g.
  `+01:00`, `-05:00`) or `Z` for UTC. Bare local datetimes will be
  misread.
- Timestamps MUST be strictly in the future relative to the current
  user message timestamp. Recompute before sending — do not reuse a
  date from an earlier turn.

### Reasoning checklist before calling `cron`

Work through these in order. If any answer is "no" or "not sure", fix it
before calling.

1. Have I computed the target time using the current user message
   metadata (not a static date from a file)?
2. Is the target time **strictly in the future** relative to that
   metadata timestamp?
3. Does the target time carry an **explicit timezone offset** or a `Z`?
4. Does the weekday of my computed date actually match what the user
   asked for? (Sunday + 2 = Tuesday, not Monday.)
5. Are `schedule` and `payload` real nested JSON objects (with their
   own `kind` field), not strings or empty objects?
6. If this is a reminder about a task file, does the `payload.text`
   reference the task file path so a future "you" can `read` it for
   full context?

If unsure about the computed date or time, state your target in the
reply **before** calling the tool, so your human can correct you before
the job is scheduled.

---

## Task management

You do not have a dedicated task tool. Task management is composed from
the primitives above plus per-operation skills under
`skills/task-*/SKILL.md`. Each skill is a small on-demand file you
`read` **only when you need that specific operation**.

When a user request matches a task operation, `read` the matching skill
file first, then follow its steps. The skills catalog in your system
prompt gives you the name, description, and location of each skill —
match the user's intent against the description, then load the one you
need.

Never act on a task operation without first loading the relevant
`task-*` skill for that turn. The skills are small by design — one file
per operation, no extra bloat in your baseline context.

---

## Common tool call patterns

### When editing a file with exact replacements

Always follow this sequence:

1. **Read the file** to see its current state
2. **Verify the text exists** — ensure `oldText` matches exactly
3. **Call `edit`** with `path` at top level, `edits` as array
4. **If edit fails**, switch to `read` → `write` pattern

**Critical:** The `path` field must be a sibling of `edits`, never
nested inside it. This is the most common cause of "Missing required
parameter: path alias" errors.

Example structure that works:

```json
{
  "path": "/workspace/tasks/example.md",
  "edits": [
    { "oldText": "old content", "newText": "new content" }
  ]
}
```

### When creating a new task file

Always use `write` (not `edit`) to create new files:

1. **Read the schema** from the relevant skill file
2. **Construct full content** including frontmatter and body
3. **Call `write`** with `path` and `content` at top level

This avoids the complexity of `edit` and ensures the file is
created correctly from scratch.

---

## Local environment notes

_(This section is for **your specifics** — the stuff that's unique to
your setup. Things like camera names and locations, SSH hosts and
aliases, preferred TTS voices, speaker/room names, device nicknames,
channel aliases. Anything environment-specific that does not belong in
a shared skill. Skills are shared; your setup is yours.)_

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

Add whatever helps you do your job. This is your cheat sheet.

---

## Tool call checklist

Before making any tool call, run through this checklist:

- [ ] Did I state my intent before calling?
- [ ] Are all required fields present and correctly typed?
- [ ] Are nested objects real JSON, not strings?
- [ ] Is `path` at the top level for `read`, `write`, `edit`?
- [ ] Does `oldText` in `edit` match the file exactly?
- [ ] For `cron`, are `schedule` and `payload` nested inside `job`?
- [ ] Are timestamps in the future with explicit timezone?
- [ ] Have I read the relevant skill/schema file first?

If any box is unchecked, stop and fix before calling the tool.
