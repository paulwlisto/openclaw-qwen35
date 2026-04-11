---
name: task-review
description: Proactive check-in — surface overdue, urgent, or time-sensitive tasks to the user. Use during heartbeat digests (morning, lunch, afternoon) or when the user asks "what should I focus on", "what's urgent", or "give me a status".
---

# task-review

A focused review of the current task list to surface what matters now.

## Steps

1. Run the `task-list` skill's enumeration steps: `ls tasks/`, read
   each file, parse frontmatter.
2. Filter the list:
   - **Overdue**: `status` is open or in_progress and `dueAt` is in
     the past (compared to current message metadata timestamp +
     user's timezone).
   - **Urgent**: `priority: high` and `status: open` or `in_progress`.
   - **Due-soon**: `dueAt` within the next 24 hours.
   - **Blocked with update**: `status: blocked` where the body
     indicates the blocker may be resolved.
3. Rank items: overdue first, then due-soon + high, then urgent
   without a deadline, then due-soon + medium.
4. Present the top 1–3 items in a concise message. For each: title,
   why it's urgent (overdue / due-soon / high / blocked), and one
   suggested next action.
5. Close with what you think the most important thing is right now.
   Be opinionated — the user hired you to have a view.
6. If nothing is urgent, say so briefly and stay silent until the
   next heartbeat. Do not manufacture urgency to have something to
   say.

## Reasoning checks

- Did you filter against the **current** message metadata timestamp?
  Not yesterday's, not training data.
- Are you respecting quiet hours from HEARTBEAT.md (22:00–06:00 in
  user's timezone)? If inside quiet hours, abort — do nothing.
- Have you already sent a digest today? Check
  `memory/YYYY-MM-DD.md` for a digest marker before sending, and
  record one after (prevents double-digest when heartbeats are
  frequent).
