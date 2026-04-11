# GEMINI.md

This project's instructions for AI coding agents live in `CLAUDE.md` at the
project root. The content is agent-neutral despite the filename — it explains
the fork-patch system, the upgrade workflow for the upstream `openclaw-src/`
checkout, and how to repair patches that fail against newer upstream commits.

Gemini CLI and Gemini Code Assist both support hierarchical context loading
and the `@file.md` import directive, so the line below pulls the full
instructions into your active context:

@CLAUDE.md

## If `@`-import doesn't resolve

If the import above is not picked up by your runtime (e.g. an older Gemini
build, or a non-CLI host), open `./CLAUDE.md`
manually before doing any work in this project. The patch troubleshooting
section is load-bearing — a wrong fix breaks cron, local-model tool calling,
or the tool-loop circuit breaker.
