# Project context for Claude Code, Gemini CLI/Code Assist, Codex, and other agents

## Project orientation

This is a docker-compose project that runs a **forked OpenClaw gateway** against a local LLM (Qwen 3.5 4B) served by either llama.cpp-server or Ollama. The "fork" lives as a set of `.patch` files in `openclaw-patches/` that are re-applied to a clean upstream `openclaw-src/` checkout at docker build time.

Key directories:
- `openclaw-src/` — upstream OpenClaw checkout, kept clean (matches a real upstream commit byte-for-byte, except for `Dockerfile` which has a one-line patch hook). **Do NOT modify files here in-tree** — every fork change belongs in `openclaw-patches/files/`.
- `openclaw-patches/` — fork patches + applier (`apply.sh`, `verify.sh`) + per-feature `.patch` files in `files/01-04-*/`.
- `llama-inference/` — thin Dockerfile wrapper around llama.cpp-server-cuda adding tzdata.
- `data/` — runtime data (workspace, config, models). NOT in the docker build context.
- `docker-compose.yml` — gateway + inference backend services with `ollama` / `llamacpp` profiles.
- `PATCHES.md` — high-level description of each fork patch and why it exists.

## How the fork build works

```
docker build -f openclaw-src/Dockerfile -t openclaw-patched:latest .
```

Note: build context is the **project root**, not `openclaw-src/`, so the Dockerfile can see both the upstream tree and the patches directory. The `.dockerignore` at the project root scopes the context.

The Dockerfile (in `openclaw-src/Dockerfile`) does:
1. `pnpm install` from upstream `package.json`
2. `COPY openclaw-src/ .` into `/app`
3. `COPY openclaw-patches /tmp/openclaw-patches` + `RUN sh /tmp/openclaw-patches/apply.sh /app`
4. The applier walks `files/01-sdk-tools-filter/` (sh script that monkey-patches `node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js`), then groups `02-04` (`.patch` files applied with `patch --forward -p0`)
5. Continue with the upstream `pnpm build:docker` flow

The runner gateway uses `image: openclaw-patched:latest` (not `build:`), so a swap requires `docker compose --profile llamacpp up -d --force-recreate openclaw-gateway` after a rebuild.

## What the patches do

The patches express **fork-only behavior** that cannot land upstream:

- **`01-sdk-tools-filter/`** — Monkey-patches `@mariozechner/pi-coding-agent`'s SDK to allow OpenClaw's custom tools through its `allTools` whitelist. Pure JS string-replace in `node_modules`.
- **`02-qwen-compat/`** — Adds `routeToolsAsBuiltIn` model-compat flag (for local models on the openai-completions API) + Qwen thinking-level controls + an Ollama `<think>` stream wrapper. Touches `tool-split.ts`, `attempt.ts`, `compact.ts`, `zod-schema.core.ts`, `extensions/ollama/src/stream.ts`.
- **`03-cron-robustness/`** — Repair pipeline for malformed cron tool-call JSON that small local models (Qwen 3.5 4B) emit. Adds `repairMangledKeys`, `reconstructPrefixedFields`, and an orphan-merge step. Touches `src/cron/normalize.ts` and `src/agents/tools/cron-tool.ts`.
- **`04-tool-loop-detection/`** — Circuit breaker that aborts a run when the same tool is called repeatedly with identical arguments. Touches the `pi-embedded-subscribe*` files plus an `onToolLoopDetected` handler in `attempt.ts`.

The `Dockerfile` itself is **not** patched via `apply.sh` — it's directly edited in `openclaw-src/Dockerfile` because `apply.sh` is invoked from inside it (chicken-and-egg). The Dockerfile change is one-time and resilient: it adds `COPY openclaw-patches /tmp/openclaw-patches` + `RUN sh /tmp/openclaw-patches/apply.sh /app` after `COPY openclaw-src/ .`. If upstream rewrites the Dockerfile build flow, you'll need to re-merge that hook manually.

---

# Patch failure troubleshooting

You are reading this section because either:
1. A docker build of `openclaw-patched:latest` failed during the `apply.sh` step, or
2. The user explicitly asked you to upgrade openclaw to a newer upstream commit and you want to know what's involved.

This section explains the failure modes and the fix workflow. **Read it end-to-end before touching anything** — the patches are load-bearing for cron, tool-calling on local models, and tool-loop protection. A bad fix breaks the gateway in subtle ways.

## What a patch failure looks like

Inside the docker build output you'll see something like:

```
#23 [build N/M] RUN sh /tmp/openclaw-patches/apply.sh /app && ...
#23 0.371 apply.sh: --- group: 03-cron-robustness ---
#23 0.373 apply.sh:   applying patch: 01-normalize.ts.patch
#23 0.376 1 out of 5 hunks FAILED -- saving rejects to file src/cron/normalize.ts.rej
#23 0.378 apply.sh: ERROR — patch failed: 01-normalize.ts.patch (exit 2)
ERROR: failed to build: ... exit code: 2
```

That tells you:
- Group: `03-cron-robustness`
- File: `01-normalize.ts.patch` → `src/cron/normalize.ts`
- Reason: 1 of 5 hunks couldn't find a matching context — upstream moved or rewrote the surrounding code.

`patch` exit codes:
- `0` — applied cleanly
- `1` — already-applied (idempotent re-run, treated as success by `apply.sh`)
- `2+` — actual failure (missing file, conflicting hunks, etc.)

If you see exit `1` reported as "ERROR" anywhere, suspect a regression in `apply.sh` (the previous version had a `$?` after `if !` bug — see git history).

## The fix workflow

There are two situations:

### A) The user just upgraded openclaw-src to a newer upstream commit

Symptom: build was working yesterday, today some patches fail because upstream rewrote the surrounding context.

**Step 1 — confirm the failing patch and inspect the conflict.**

```sh
patch --dry-run --forward -p0 -d ./openclaw-src \
  < ./openclaw-patches/files/03-cron-robustness/01-normalize.ts.patch
```

The dry-run reports which hunks fail and roughly where. Compare the patch's expected context against the actual upstream file:

```sh
# What the patch expects to find:
head -40 ./openclaw-patches/files/03-cron-robustness/01-normalize.ts.patch

# What's actually at that location now:
read ./openclaw-src/src/cron/normalize.ts
```

**Step 2 — re-apply the change manually.**

Look at the original patch to understand WHAT it changes. Read the patch file and trace what each hunk does. Then make the same SEMANTIC change in the new upstream source by hand. The goal is to land the same behavior — not necessarily the exact same line of text. Upstream may have renamed identifiers, moved functions, or split files, and you must adapt.

Critical: don't blindly find-and-replace. Understand what the patch is doing, then make the equivalent edit. If the patch adds a parameter to a function call, find the function call in the new code (which may have different surrounding code) and add the parameter there. If the patch adds a new function, find a sensible place for it in the new file.

For each feature group, here is what you need to preserve:

| Group | Semantic invariant |
|---|---|
| 01-sdk-tools-filter | After pnpm install, `node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js` must accept tool names from BOTH `allTools` AND `customTools` in its filter. |
| 02-qwen-compat | `splitSdkTools()` must accept a `routeToolsAsBuiltIn` boolean and route tools as built-in when true. `attempt.ts` and `compact.ts` must read `model.compat.routeToolsAsBuiltIn` and pass it through. The zod schema must accept `routeToolsAsBuiltIn` and `thinkingLevel` on `ModelCompat`. |
| 03-cron-robustness | `normalizeCronJobInput` must run `repairMangledKeys` and `reconstructPrefixedFields` over the parsed input before validation. The cron tool's `execute` must merge orphaned top-level recoverable fields (`payload`, `sessionTarget`, `delivery`, `enabled`) into a partially-populated `params.job` before calling `normalizeCronJobCreate`. |
| 04-tool-loop-detection | The pi-embedded-subscribe state machine must track per-tool call counts and fire `onToolLoopDetected` when a threshold is hit. The runner's `attempt.ts` must wire that callback into `abortRun`. |

**Step 3 — regenerate the patch from the manual fix.**

Once the source file is in the right state:

```sh
git -C ./openclaw-src diff --no-prefix HEAD \
  -- src/cron/normalize.ts \
  > ./openclaw-patches/files/03-cron-robustness/01-normalize.ts.patch
```

Always use `--no-prefix` — the apply.sh expects `-p0` patches.

**Step 4 — verify the patch round-trips.**

Stage a fresh upstream copy of the file and re-apply the new patch to it:

```sh
mkdir -p /tmp/patch-test/src/cron
git -C ./openclaw-src show HEAD:src/cron/normalize.ts \
  > /tmp/patch-test/src/cron/normalize.ts
patch --forward --batch -p0 -r /dev/null -d /tmp/patch-test \
  < ./openclaw-patches/files/03-cron-robustness/01-normalize.ts.patch
diff /tmp/patch-test/src/cron/normalize.ts \
     ./openclaw-src/src/cron/normalize.ts
```

The diff at the end should be empty.

**Step 5 — clean rebuild.**

Revert openclaw-src to clean upstream (drop the manual fix from the working tree — the patch file IS the source of truth now), then run docker build:

```sh
git -C ./openclaw-src checkout HEAD -- src/cron/normalize.ts
docker build -f ./openclaw-src/Dockerfile \
  -t openclaw-patched:latest \
  .
```

Rinse and repeat for every failing patch.

### B) The build was working but suddenly fails

Symptom: nothing changed in openclaw-src, but apply.sh is reporting errors.

Most common causes:
1. **`apply.sh` was edited and broken** — see the `set +e; cmd; rc=$?; set -e` pattern in the .patch handler. `if ! cmd` does NOT preserve `cmd`'s exit code in `$?`.
2. **A patch file was corrupted on disk** — re-extract from git history if there's a known-good ref.
3. **`patch` binary missing in the build container** — should not happen with `node:24-bookworm` but verify with `docker run --rm node:24-bookworm patch --version`.
4. **`.dockerignore` at the project root excluded `openclaw-patches/`** — verify with `docker build --no-cache --progress=plain ...` and look for the `COPY openclaw-patches /tmp/openclaw-patches` step.

## How to verify the patches landed in a built image

```sh
# Check that the SDK monkey-patch is in node_modules:
docker run --rm openclaw-patched:latest \
  grep -c "options.customTools" \
  /app/node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js
# Expected: 1
```

The source patches are compiled into `dist/` so you can't grep them in the runtime image directly — but the gateway logs are the real test:

```sh
docker logs openclaw-gateway 2>&1 | grep -i "cron\|tool-loop\|routeToolsAsBuiltIn"
```

A working build will show cron jobs being created, tool calls succeeding for the local model, and (if a loop happens) the loop detector firing.

## Hard rules

- **Never** delete a patch to "make the build pass". The patches encode load-bearing behavior. If a patch is genuinely obsolete (upstream merged the same fix), confirm by reading upstream's commit history for the relevant file, then delete the patch with a clear note in `PATCHES.md` and the commit message.
- **Never** edit `openclaw-src/` files in-tree as a permanent fix. The whole point of the patches directory is to keep the upstream checkout clean. Every fork modification belongs in a `.patch` there.
- **Never** use `--no-prefix=false` or `git diff` without `--no-prefix` to regenerate patches. The applier expects `-p0` strip level.
- **Always** test a regenerated patch by applying it to a fresh upstream copy AND running a full docker build before declaring victory.
- **Always** regenerate the patch from a working manual fix in `openclaw-src/`, then revert openclaw-src so the patch is the only source of truth.

## Files you might need to read for context

- `./PATCHES.md` — high-level description of each fork patch and why it exists
- `./openclaw-patches/README.md` — directory layout and the upgrade workflow
- `./openclaw-patches/apply.sh` — the applier itself; read it to understand exit codes and the `--no-scripts` flag
- `./openclaw-patches/verify.sh` — grep-based marker checks for each patch group
- `./openclaw-src/Dockerfile` — see the `apply.sh` invocation block (was around line 80 at last touch)
- `./.dockerignore` — project-root exclusions; if `openclaw-patches/` ever stops being copied into the build, check here

## When to escalate to the user

Stop and ask the user before:
- Deleting any `.patch` file
- Editing `openclaw-src/` files outside of a regenerate-the-patch flow
- Changing the structure of `apply.sh` or `verify.sh`
- Force-pushing or `git reset --hard` on `openclaw-src/`
- Restarting the running `openclaw-gateway` container (brief service interruption)
