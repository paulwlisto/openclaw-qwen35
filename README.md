# OpenClaw + Local Qwen — A Self-Hosted AI Gateway

A docker-compose stack that runs the [OpenClaw](https://github.com/openclaw/openclaw) gateway against a **local LLM** (Qwen 3.5 4B) served by either **llama.cpp-server** (recommended) or **Ollama**, with a maintained set of fork patches that make tool calling, cron scheduling, and the tool-loop circuit breaker work reliably on small local models.

The result is a private AI assistant that you talk to over Telegram (and other channels), runs entirely on your own machine, and can call tools, schedule reminders, manage tasks, and search the web — without ever sending a token to a cloud provider.

> **Status:** running daily on a single workstation with an NVIDIA RTX 2050 (4 GB VRAM). Tested with Qwen 3.5 4B Q4_K_M via llama.cpp-server and Qwen 3 14B via Ollama.

## Why this exists

[OpenClaw](https://github.com/openclaw/openclaw) is great with frontier models (Anthropic, OpenAI), but local model support has three rough edges that the upstream project hasn't fully addressed:

1. **Tools aren't sent to local models.** Upstream routes all tools as `customTools` (client-side handling), which works for cloud providers but means local models on the openai-completions API never see the tool definitions in their context. Local model = no tool calling.
2. **Small local models emit broken JSON for nested tool arguments.** Qwen 3.5 4B in particular produces malformed `cron.add` payloads ~80% of the time — mangled key notation, orphaned top-level fields, flattened-prefix flats. These all fail upstream's strict zod validation.
3. **No tool-loop circuit breaker.** A confused local model can get stuck calling the same tool with the same arguments forever, exhausting context and never producing a reply.

This repo fixes all three via four small patch groups (see `openclaw-patches/`) that are re-applied to a clean upstream `openclaw-src/` checkout at docker build time. The upstream tree stays clean — no in-tree edits to manage — so upgrading to a newer OpenClaw release is `git checkout origin/main && docker build`.

## What you get

- **Self-hosted gateway** on `http://localhost:18789` — control UI, healthchecks, multi-channel routing
- **Telegram bot** that you DM or `@`-mention in groups
- **Local Qwen model** with proper tool calling, cron scheduling, web search, file operations, and a memory system
- **Two inference backends** to choose from: llama.cpp-server (better for low VRAM, native penalty sampling, Jinja templates) or Ollama (legacy, simpler to swap models)
- **Fork patches** automatically re-applied during build, kept clean and reproducible

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Your machine (single host)                 │
│                                                                │
│  ┌─────────────┐    HTTP    ┌──────────────────┐    HTTP/JSON  │
│  │   Telegram  │  webhooks  │ openclaw-gateway │ ──────────┐   │
│  │ / Web UI /  │ ─────────► │   :18789         │           │   │
│  │  channels   │            │  (forked)        │           ▼   │
│  └─────────────┘            └──────────────────┘    ┌──────────┴──┐
│                                       │              │  inference  │
│                                       │              │  :11434     │
│                                       │              │             │
│                                       │              │  llama.cpp  │
│                                       │              │      OR     │
│                                       │              │   Ollama    │
│                                       │              └─────────────┘
│                                       ▼
│                              ┌──────────────────┐
│                              │  data/           │
│                              │  ├ config/       │  ← openclaw.json,
│                              │  ├ workspace/    │     credentials, prompts
│                              │  └ models/       │  ← GGUF weights
│                              └──────────────────┘
└────────────────────────────────────────────────────────────────┘
```

The build pipeline pulls clean upstream `openclaw-src/`, applies our `openclaw-patches/` at docker build time, and produces a single image (`openclaw-patched:latest`) used by the gateway service.

## Repository layout

```
.
├── README.md             ← you are here
├── CLAUDE.md             ← AI agent context (project overview + patch troubleshooting)
├── AGENTS.md             ← cross-tool agent pointer to CLAUDE.md
├── GEMINI.md             ← Gemini agent pointer to CLAUDE.md
├── PATCHES.md            ← high-level description of every fork patch and why it exists
├── docker-compose.yml    ← gateway + inference services with `ollama` / `llamacpp` profiles
├── .env.example          ← copy to .env and fill in your secrets
├── .dockerignore         ← scopes the project-root build context
├── .gitignore            ← excludes runtime data, secrets, agent state
│
├── openclaw-src/         ← upstream OpenClaw checkout, kept CLEAN
│                            (only Dockerfile is modified, see CLAUDE.md)
│
├── openclaw-patches/     ← THE FORK
│   ├── README.md         ← directory layout + upgrade workflow
│   ├── CLAUDE.md         ← patch troubleshooting agent guide
│   ├── apply.sh          ← idempotent patch applier (runs at docker build time)
│   ├── verify.sh         ← grep-based marker checks for landed patches
│   └── files/
│       ├── 01-sdk-tools-filter/      ← node_modules monkey-patch
│       ├── 02-qwen-compat/           ← routeToolsAsBuiltIn flag + Qwen thinking
│       ├── 03-cron-robustness/       ← cron arg recovery for small models
│       └── 04-tool-loop-detection/   ← tool-call loop circuit breaker
│
├── llama-inference/      ← thin Dockerfile wrapping llama.cpp-server-cuda + tzdata
│
├── sample-workspace/     ← starting-point workspace, copy to data/workspace/ on first run
│   ├── AGENTS.md         ← agent identity, session startup, group-chat etiquette
│   ├── TOOLS.md          ← how to call tools well, file ops, cron, task management
│   ├── BOOT.md           ← first-boot greeting
│   ├── BOOTSTRAP.md      ← one-shot identity creation guide (deleted after first run)
│   ├── SOUL.md / IDENTITY.md / USER.md   ← persona, identity, user profile templates
│   ├── HEARTBEAT.md      ← proactive check-in checklist
│   └── skills/
│       └── task-*/SKILL.md   ← 8 task-management skills (create/list/update/schedule/...)
│
└── data/                 ← runtime data (GITIGNORED)
    ├── config/           ← openclaw.json + credentials/
    ├── workspace/        ← agent's working directory (memories, sessions, plans)
    └── models/           ← downloaded GGUF model files
```

## Prerequisites

- **Docker Desktop** with the WSL2 backend (Windows/macOS) or Docker Engine (Linux)
- **NVIDIA GPU** with at least **4 GB VRAM** + recent driver + NVIDIA Container Toolkit (`nvidia-container-toolkit`)
- **Telegram account** for the chat interface (optional but recommended)
- **~10 GB disk** for the docker images, the patched build, and the GGUF model file
- **`git`** for cloning + future upstream updates

Tested on Windows 11 + Docker Desktop, also works on Linux (Ubuntu 24.04). macOS works for the build but you'll need to swap the backend for Metal-friendly inference (not covered here).

## Quick start

> 💡 **Need a co-pilot for the setup?** This repo ships with `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` context files at the project root that brief any modern AI coding agent on the project layout, the patch system, and the upgrade workflow. If you're not already using Claude Code, try **[Gemini Code Assist](https://codeassist.google.com/)** — it's **free for individuals** (the Standard tier requires only a personal Google account) and works in VS Code, JetBrains IDEs, and Android Studio. It will automatically load `GEMINI.md` when you open the repo and can walk you through the steps below, debug a failed `docker build`, regenerate a patch when upstream changes shape, or help you tune the workspace files for your environment. Other agents (Claude Code, Codex, Cursor, etc.) read `CLAUDE.md` / `AGENTS.md` and work the same way.

### 1. Clone

```sh
git clone <this-repo-url> openclaw-fork
cd openclaw-fork
```

That's it — `openclaw-src/` is vendored directly in the repo at a known-good upstream commit (`001e0c1f65c4bfdf310a5161cde25696e868af20`) with the Dockerfile build-context hook already applied. A plain clone gives you a buildable tree; skip to step 2.

> **Maintainer note — rebasing onto a newer upstream.** If you want to re-pin the vendored tree to a newer OpenClaw commit, there's an optional `sh setup.sh` helper: edit the `PINNED_COMMIT` at the top, run it, and it'll remove the existing `openclaw-src/`, re-clone upstream at that commit, and re-apply `openclaw-patches/dockerfile-hook.patch`. You still need to run a full `docker build` to confirm the other patch groups still apply, and regenerate any that fail per `openclaw-patches/CLAUDE.md`.

### 2. Configure environment

```sh
cp .env.example .env
```

Edit `.env` and fill in:
- **`TELEGRAM_BOT_TOKEN`** — get one by DMing `@BotFather` on Telegram and running `/newbot`
- **`OPENCLAW_GATEWAY_TOKEN`** — generate with `openssl rand -hex 24` (or leave blank for local-only loopback access)
- **`OPENCLAW_TZ`** — your timezone in IANA format (e.g. `Australia/Brisbane`, `America/New_York`, `UTC`)

The defaults for KV cache, flash attention, and ports are sensible — leave them unless you're tuning.

### 3. Configure the gateway

```sh
cp data/config/openclaw.json.example data/config/openclaw.json
```

Edit `data/config/openclaw.json` and set:
- **`commands.ownerAllowFrom`** — your Telegram user ID prefixed with `telegram:` (e.g. `["telegram:123456789"]`). Find your ID by DMing `@userinfobot` on Telegram. This whitelist controls who can run owner-only commands like cron and config edits.
- Anything else you want to override (model selection, compaction tuning, channels)

### 4. Bootstrap the agent workspace

The agent needs a working directory with its identity files, tools reference, and skills. Copy the starting-point workspace into `data/`:

```sh
mkdir -p data/workspace
cp -r sample-workspace/. data/workspace/
```

This places `AGENTS.md`, `TOOLS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOT.md`, `BOOTSTRAP.md`, and the full `skills/task-*/` tree into your live workspace.

What you get out of the box:

- **`AGENTS.md`** — the agent's session-startup instructions, group-chat etiquette, memory rules, and a one-line directive to read `TOOLS.md` every session
- **`TOOLS.md`** — reference for how to call tools well (file ops, `cron`, task management), with the structural rules that make small local models reliable. Always loaded at session start
- **`BOOTSTRAP.md`** — a one-shot "birth certificate" the agent reads on first run to set up its identity, then deletes
- **`skills/task-*/`** — eight on-demand skills for task management: `task-create`, `task-list`, `task-update`, `task-complete`, `task-review`, `task-schedule`, `task-schema`, `task-reminder-fired`. Each is a small `SKILL.md` the agent loads only when the user's request matches that operation. This pattern keeps the baseline context tiny.

Edit `USER.md` to describe yourself (name, timezone, working hours, what you want help with). The agent uses this for everything from greeting style to scheduling reminders in your local timezone.

### 5. Download the model

For the default llama.cpp-server backend, you need the Qwen 3.5 4B Q4_K_M GGUF:

```sh
# Verify checksum and download into data/models/
sh data/models/verify-and-download.sh
```

This places `Qwen_Qwen3.5-4B-Q4_K_M.gguf` (~2.7 GB) into `data/models/`. The file is verified against its HuggingFace LFS pointer SHA256 at download time.

### 6. Build the patched image

The build context is the **project root** (so the Dockerfile can see both `openclaw-src/` and `openclaw-patches/`):

```sh
docker build -f openclaw-src/Dockerfile -t openclaw-patched:latest .
```

You should see `apply.sh` run during the build, log lines for each patch group, and `SDK tool filter patched successfully`. The build takes 5–10 minutes on a fast machine.

### 7. Start the stack

```sh
# Start the recommended llama.cpp-server backend
docker compose --profile llamacpp up -d
```

Within ~30 seconds the gateway healthcheck should turn green:

```sh
docker compose ps
docker logs openclaw-gateway --tail 50
```

You're looking for lines like `gateway: ready (5 plugins, 16.9s)` and `agent model: llamacpp/qwen3.5-4b-q4_k_m`.

### 8. Pair Telegram

DM your bot. The first message will be rejected with a pairing code. Approve it from the CLI:

```sh
docker compose --profile cli run openclaw-cli pairing list telegram
docker compose --profile cli run openclaw-cli pairing approve telegram <CODE>
```

Now DM the bot again — you should get a friendly response from the local Qwen model.

## Switching inference backends

Two compose profiles, one container name, one network alias — they're hot-swappable but only one can run at a time:

```sh
# llama.cpp-server (recommended: native penalty sampling, proper Jinja templates)
docker compose --profile llamacpp up -d

# Ollama (legacy: simpler model swapping but has the qwen3next stall + broken penalty sampling)
docker compose --profile ollama up -d
```

After switching the backend you also need to toggle the matching provider block in `data/config/openclaw.json` (the file is JSON5, so block-comment one and uncomment the other), then restart the gateway:

```sh
docker cp data/config/openclaw.json openclaw-gateway:/home/node/.openclaw/openclaw.json
docker compose restart openclaw-gateway
```

## Web UI

Open `http://localhost:18789/openclaw` in your browser for the full control panel: channels, agent state, conversation history, plugin status, healthchecks.

## How the agent workspace works

Everything the agent reads, writes, and reasons over lives under `data/workspace/`. The starting state of that directory ships in `sample-workspace/` — copy it once during setup (step 4 above), then let the agent maintain it.

### Files at the workspace root

| File | What it does |
|---|---|
| **`AGENTS.md`** | The agent's session-startup checklist and operating doctrine. Loaded at the very beginning of every session. Tells the agent to read `SOUL.md`, `USER.md`, `TOOLS.md`, and the recent `memory/` files before doing anything else. Also covers fail-fast retry discipline, group-chat etiquette, and the heartbeat protocol. |
| **`TOOLS.md`** | How to call tools well. Covers `read`/`write`/`edit`, `cron`, the canonical JSON shape for nested tool arguments, the read-then-write fallback when `edit` fails, and a per-call checklist. **Loaded every session** because small local models forget tool-call discipline between turns. |
| **`SOUL.md`** | The agent's persona — voice, values, communication style. Edit this to tune how the agent talks to you. |
| **`IDENTITY.md`** | Who the agent thinks it is — name, backstory, role. Distinct from `SOUL.md` (personality) so you can swap one without losing the other. |
| **`USER.md`** | Who you are — name, timezone, working hours, preferences, what you want help with. The agent uses this for greeting style, scheduling reminders in your local timezone, and deciding when to stay quiet. **Edit this first** after copying the sample workspace. |
| **`HEARTBEAT.md`** | A small checklist the agent runs during periodic heartbeat polls (inbox, calendar, mentions, etc.). Keep it short to limit token burn. |
| **`BOOT.md`** / **`BOOTSTRAP.md`** | First-run greeting and one-shot identity-creation guide. The agent reads `BOOTSTRAP.md` once on first run to fill in `SOUL.md`/`IDENTITY.md`/`USER.md`, then deletes it. |

### The `skills/` directory

Skills are **on-demand** instructions the agent loads only when a specific operation is needed. They live as small `SKILL.md` files in `skills/<skill-name>/` and each has YAML frontmatter (`name`, `description`) so the runtime can present them to the agent as a discoverable catalog.

The starting workspace ships eight skills covering task management:

| Skill | When the agent loads it |
|---|---|
| `task-create` | User says "remind me to…", "add a task…", "don't let me forget…" |
| `task-list` | User asks "what's on my list", "what's pending" |
| `task-update` | User changes a priority, reschedules, adds notes, or marks blocked |
| `task-complete` | User finishes something — also handles cron cancellation + archival |
| `task-review` | Heartbeat digests or "what should I focus on" — surfaces overdue/urgent items |
| `task-schedule` | After `task-create`, attach a one-shot cron reminder to the task file |
| `task-schema` | Shared file format for `tasks/*.md` — read once per session before any other task-* operation |
| `task-reminder-fired` | A cron reminder fired — re-read the task file and message the user |

This composition pattern (small skills + a thin orchestrator agent) is what makes a 4B-parameter local model usable for real work: the agent only loads the instructions it needs for the operation in front of it, keeping the active context window small and focused.

### Memory and continuity

The agent wakes up with no memory between sessions. To stay coherent it writes to:

- **`memory/YYYY-MM-DD.md`** — raw daily notes (always loaded for today + yesterday at session start)
- **`MEMORY.md`** — curated long-term memory (only loaded in your direct main session, never in shared/group contexts, for security reasons)
- **`tasks/<slug>.md`** — durable task files with absolute timestamps and full context
- **`archive/<slug>.md`** — completed tasks (audit trail)

Periodically the agent reviews `memory/` daily files during a heartbeat and distils anything worth keeping into `MEMORY.md`.

### Customizing the workspace

After bootstrapping, edit `USER.md` to describe yourself, then let the agent get to know you. Over time it will update `SOUL.md`, `IDENTITY.md`, and `MEMORY.md` itself based on conversations. Add your own skills under `skills/` whenever you find a recurring pattern worth capturing — the runtime auto-discovers any subdirectory with a `SKILL.md` and YAML frontmatter.

Add personal environment notes (camera names, SSH hosts, voice preferences) at the bottom of `TOOLS.md` in the "Local environment notes" section. Skills are shared; that section is yours.

## Updating to a newer upstream OpenClaw

The whole point of the patch system is that upgrading is supposed to be cheap. From the project root:

```sh
git -C openclaw-src fetch origin
git -C openclaw-src checkout origin/main
docker build -f openclaw-src/Dockerfile -t openclaw-patched:latest .
docker compose --profile llamacpp up -d --force-recreate openclaw-gateway
```

If a patch fails to apply because upstream rewrote the surrounding context, the docker build halts loudly and names the offending `.patch` file. The full repair workflow lives in `openclaw-patches/CLAUDE.md` — that's the on-call playbook.

## What the patches do

See `PATCHES.md` for the full technical writeup. Quick summary:

| Group | What it fixes |
|---|---|
| **`01-sdk-tools-filter/`** | Monkey-patches the pi-coding-agent SDK so OpenClaw's custom tools survive its `allTools` whitelist |
| **`02-qwen-compat/`** | Adds the `routeToolsAsBuiltIn` model-compat flag — local models on the openai-completions API now actually receive tool definitions in the API request. Plus Qwen thinking-level controls and an Ollama `<think>` stream wrapper. |
| **`03-cron-robustness/`** | A repair pipeline (`repairMangledKeys`, `reconstructPrefixedFields`, orphan-merge) that recovers cron tool calls from small-model JSON quirks |
| **`04-tool-loop-detection/`** | Circuit breaker that aborts a run when the model gets stuck calling the same tool with identical arguments |

All four are opt-in via model-compat config flags — without them set, the build behaves identically to upstream.

## Troubleshooting

**Build fails during `apply.sh`** — see `openclaw-patches/CLAUDE.md` for the patch repair workflow. Most likely an upstream commit moved the surrounding context of one of the hunks.

**Gateway logs `compaction-diag end ... outcome=aborted`** — context is filling up faster than the compactor can flush. Tune `agents.defaults.compaction` in `openclaw.json` (lower `keepRecentTokens` or raise `reserveTokensFloor`).

**Tool calls always fail with schema validation errors** — confirm `compat.routeToolsAsBuiltIn: true` is set on your model in `openclaw.json`. Without this the patches are inert.

**Cron jobs always fail** — check the gateway logs for `cron: job created`. If you see `cron: input rejected` instead, the model is producing a JSON shape the repair pipeline doesn't recognize. File an issue with the raw `cron.add` payload from the logs.

**llama.cpp-server runs out of VRAM at startup** — the default `--fit-ctx 28672` plus q4_0 KV cache fits in 4 GB. If you have less, lower `--fit-ctx` in `docker-compose.yml`. If you have more, raise it.

**Telegram bot doesn't respond** — confirm pairing was approved (`docker compose --profile cli run openclaw-cli pairing list telegram`) and check `docker logs openclaw-gateway` for connection errors.

## How it differs from upstream OpenClaw

| | Upstream | This fork |
|---|---|---|
| Cloud providers (Anthropic, OpenAI, etc.) | ✅ first-class | ✅ unchanged |
| Local models — basic chat | ✅ works | ✅ works |
| Local models — tool calling | ⚠️ tools never sent in API request | ✅ via `routeToolsAsBuiltIn` flag |
| Local models — cron scheduling | ❌ small models break the JSON schema | ✅ via repair pipeline |
| Tool-call loop protection | ❌ none | ✅ circuit breaker aborts after threshold |
| Upgrade workflow | direct git checkout | git checkout → patches re-apply at build time |

The patches are designed to be **upstream-friendly** — all the new behavior is gated behind opt-in compat flags, so a future upstream merge would be additive. We've linked the relevant upstream PRs in `PATCHES.md` if you want to track them.

## Contributing

We are not accepting contributions at this time.

## License

The fork patches in `openclaw-patches/` and the build infrastructure in this repo are released under the MIT License.

The upstream OpenClaw code in `openclaw-src/` is licensed under the [terms set by the OpenClaw project](https://github.com/openclaw/openclaw) — refer to `openclaw-src/LICENSE` after cloning. This fork does not redistribute upstream code; you clone it directly from upstream as part of the setup.

The Qwen 3.5 model weights are governed by the [Qwen Research License](https://github.com/QwenLM/Qwen). This repo does not redistribute weights — you download them from HuggingFace via `data/models/verify-and-download.sh`.

## Credits

- [OpenClaw](https://github.com/openclaw/openclaw) — the upstream gateway and agent runtime
- [pi-coding-agent](https://github.com/mariozechner/pi-coding-agent) by Mario Zechner — the embedded coding-agent SDK that OpenClaw uses
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — the inference server backing the recommended profile
- [Qwen](https://github.com/QwenLM/Qwen) — the model that makes any of this useful at 4 GB VRAM
- [jokelord/openclaw-local-model-tool-calling-patch](https://github.com/jokelord/openclaw-local-model-tool-calling-patch) — earlier community patch that inspired this fork's approach
