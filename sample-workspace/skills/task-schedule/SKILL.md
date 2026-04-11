---
name: task-schedule
description: Schedule a one-shot reminder for an existing task via the cron tool. Use after creating a task when the user wants a reminder at a specific time, or when updating an existing task's reminder. Requires the task file to already exist.
---

# task-schedule

Attach a one-shot cron reminder to an existing task file.

## Prerequisite

The task file must already exist under `tasks/<slug>.md`. If it
doesn't, run the `task-create` skill first.

## Steps

1. Compute the target time using the date/time discipline in AGENTS.md:
   - Take the current UTC timestamp from the message metadata
   - Convert to the user's timezone from USER.md
   - From that local moment, compute the target date and time
   - Produce ISO-8601 with the correct offset for the user's timezone
     (e.g. `+01:00`, `-05:00`, `+10:00`) or `Z` for UTC
2. Verify the computed time is **strictly in the future** and the
   weekday matches what the user asked for.
3. Call `cron` with `action: "add"`. The argument shape:

```
<tool_call>
{"name": "cron", "arguments": {"action": "add", "job": {"name": "<kebab-case-id>", "description": "<one line description>", "schedule": {"kind": "at", "at": "<ISO-8601 timestamp with offset>"}, "payload": {"kind": "systemEvent", "text": "<reminder referencing tasks/<slug>.md>"}, "sessionTarget": "main"}}}
</tool_call>
```

ALL of `name`, `description`, `schedule`, `payload`, and `sessionTarget`
are fields INSIDE the `job` object. The top level has only `action` and
`job`.

4. The `payload.text` MUST include the task file path (e.g.
   `tasks/<slug>.md`) so the future you can re-read the task on fire.
   Remember: incoming message metadata is in UTC, and your human
   thinks in their local timezone — always convert before computing
   the target instant.
5. Capture the returned `job.id` from the cron response.
6. Use the `task-update` skill to set `cronJobId: <returned id>` on
   the task file.
7. Confirm to the user: task title, scheduled time in their local
   timezone, reminder text.
