# OpenClaw Patches — Local Model Tool Calling & Thinking

These patches enable tool calling and thinking/reasoning for local models (Ollama/Qwen) in OpenClaw. Three layers of issues prevent local models from using tools and thinking. These changes fix all three via a combination of source patches, SDK patches, and configuration flags.

## Where the patches live

The patches are stored in **`openclaw-patches/`** as unified `.patch` files,
applied at docker build time by `openclaw-patches/apply.sh`. The `openclaw-src/`
checkout itself stays clean (matching upstream `001e0c1`) except for `Dockerfile`,
which is directly edited to add the `apply.sh` hook.

```
openclaw-patches/
├── README.md          ← upgrade workflow + layout reference
├── apply.sh           ← idempotent applier (runs all .patch + .sh in sorted order)
├── verify.sh          ← grep-based sanity check
└── files/
    ├── 01-sdk-tools-filter/      → SDK monkey-patch (sh script)
    ├── 02-qwen-compat/           → routeToolsAsBuiltIn flag + Qwen thinking + Ollama wrapper
    ├── 03-cron-robustness/       → cron arg recovery for small-model output
    └── 04-tool-loop-detection/   → tool-call loop circuit breaker
```

**Build invocation** (note: build context is project root, not `openclaw-src/`):

```sh
docker build -f openclaw-src/Dockerfile -t openclaw-patched:latest .
```

**Upgrade workflow**:

```sh
git -C openclaw-src fetch origin
git -C openclaw-src checkout origin/main
docker build -f openclaw-src/Dockerfile -t openclaw-patched:latest .
```

If a patch fails because upstream changed the surrounding context, the build
fails loudly with the offending `.patch` filename. See
`openclaw-patches/README.md` for the conflict-resolution workflow.

## Problem Statement

OpenClaw's embedded agent has ~21 built-in tools (file operations, bash, memory, messaging, cron, etc.). When using cloud providers (Anthropic, OpenAI), these tools are passed in the API request and the model can invoke them. When using local models via Ollama, three issues prevent tool use:

1. **OpenClaw layer**: `splitSdkTools()` routes all tools as `customTools` (client-side) instead of `builtInTools` (sent in API request). Local models never see tool definitions.
2. **SDK layer**: `pi-coding-agent`'s `createAgentSession()` filters `builtInTools` to only its own 8 built-in names (`read, bash, edit, write, grep, find, ls`), dropping all 18 OpenClaw-specific tools (cron, message, canvas, web_search, etc.).
3. **Ollama extension layer**: Thinking/reasoning is hardcoded off (`think: false`) for all Ollama models, and the SDK forces `thinkingLevel = "off"` unless `model.reasoning` is true.

## Patches

### 1. Route Tools as Built-In for Local Models

**Files modified:**
- `src/agents/pi-embedded-runner/tool-split.ts`
- `src/agents/pi-embedded-runner/run/attempt.ts`
- `src/agents/pi-embedded-runner/compact.ts`
- `src/config/zod-schema.core.ts`

**What it does:**
Adds a `routeToolsAsBuiltIn` boolean to the model compat config. When `true`, `splitSdkTools()` routes all tools as `builtInTools` (included in the API request) instead of `customTools` (handled client-side). This allows local models to see and invoke tool definitions.

**`tool-split.ts` change:**
```typescript
// Before: always customTools
return { builtInTools: [], customTools: toToolDefinitions(tools) };

// After: configurable per model
if (routeToolsAsBuiltIn) {
  return { builtInTools: tools, customTools: [] };
}
return { builtInTools: [], customTools: toToolDefinitions(tools) };
```

**`attempt.ts` and `compact.ts` change:**
```typescript
const modelCompat = params.model.compat as { routeToolsAsBuiltIn?: boolean } | undefined;
const { builtInTools, customTools } = splitSdkTools({
  tools: effectiveTools,
  sandboxEnabled: !!sandbox?.enabled,
  routeToolsAsBuiltIn: modelCompat?.routeToolsAsBuiltIn === true,
});
```

**`zod-schema.core.ts` change:**
Added `routeToolsAsBuiltIn: z.boolean().optional()` and `thinkingLevel: z.enum(["off", "low", "medium", "high"]).optional()` to the model compat schema.

### 2. Configurable streaming for Ollama Requests (critical for tool calling)

**File modified:**
- `extensions/ollama/src/stream.ts`

**What it does:**
Adds `tool_choice: "auto"` to the Ollama `/api/chat` request when tools are present. This signals to the model that tool use is available and encouraged.

```typescript
// Before (hardcoded stream: true)
stream: true,

// After (configurable via env var)
stream: process.env.OLLAMA_STREAM === "false" ? false : true,
```

Streaming must be disabled for Qwen models to return tool calls — Ollama doesn't emit `tool_calls` in stream chunks when thinking is enabled. Set `OLLAMA_STREAM=false` in `.env`.

Note: `tool_choice` is NOT supported by Ollama's native API and must not be sent.

### 3. Enable Thinking/Reasoning for Ollama Models

**File modified:**
- `extensions/ollama/src/stream.ts`

**What it does:**
The upstream code hardcodes `think: false` for all Ollama models. This patch adds a `createOllamaThinkingOnWrapper` that sets `think: true` when the configured thinking level is not "off". This enables Qwen 3's native `<think>` reasoning mode.

```typescript
// New function added
function createOllamaThinkingOnWrapper(baseFn) {
  return (model, context, options) => {
    if (model.api !== "ollama") return streamFn(model, context, options);
    return streamWithPayloadPatch(streamFn, model, context, options, (payloadRecord) => {
      payloadRecord.think = true;
    });
  };
}

// Existing wrapper logic extended
if (ctx.thinkingLevel === "off") {
  streamFn = createOllamaThinkingOffWrapper(streamFn);
} else if (ctx.thinkingLevel && ctx.thinkingLevel !== "off") {
  streamFn = createOllamaThinkingOnWrapper(streamFn);
}
```

### 4. Remove SDK allTools filter (Dockerfile sed patch)

**File patched at build time:**
- `node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js`

**What it does:**
The pi-coding-agent SDK's `createAgentSession()` filters incoming `builtInTools` to only accept tools whose names exist in its `allTools` registry (8 tools: read, bash, edit, write, grep, find, ls). This drops all 18 OpenClaw-specific tools. The `sed` patch removes this filter so all tools pass through.

```javascript
// Before (sdk.js line 127)
const initialActiveToolNames = options.tools
    ? options.tools.map((t) => t.name).filter((n) => n in allTools)
    : defaultActiveToolNames;

// After
const initialActiveToolNames = options.tools
    ? options.tools.map((t) => t.name)
    : defaultActiveToolNames;
```

**Applied in Dockerfile:**
```dockerfile
RUN sed -i 's/.filter((n) => n in allTools)//' \
    node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js
```

### 5. Enable model.reasoning via config

**No code change needed.** The model schema already supports `reasoning: boolean`. Adding `"reasoning": true` to the model definition in `openclaw.json` tells the SDK the model supports thinking, preventing the forced `thinkingLevel = "off"` at `sdk.js` line 122-124.

## Configuration

All features are opt-in via `openclaw.json`. No changes to default behaviour.

**openclaw.json:**
```json
{
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://ollama:11434",
        "api": "ollama",
        "apiKey": "ollama-local",
        "models": [
          {
            "id": "qwen3:4b",
            "name": "Qwen 3 4B",
            "reasoning": true,
            "contextWindow": 20480,
            "maxTokens": 8192,
            "compat": {
              "supportsTools": true,
              "routeToolsAsBuiltIn": true,
              "thinkingLevel": "medium",
              "thinkingFormat": "qwen"
            }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/qwen3:4b",
        "fallbacks": []
      },
      "models": {
        "ollama/qwen3:4b": {
          "streaming": false
        }
      },
      "llm": {
        "idleTimeoutSeconds": 300
      },
      "thinkingDefault": "medium"
    }
  }
}
```

**.env:**
```
OLLAMA_STREAM=false
OLLAMA_KV_CACHE_TYPE=q4_0
```

### Config Keys

| Key | Location | Purpose |
|-----|----------|---------|
| `compat.routeToolsAsBuiltIn` | Model definition | Send tools in API request instead of client-side |
| `compat.thinkingLevel` | Model definition | Declare thinking support level for model |
| `compat.thinkingFormat` | Model definition | How to parse thinking output (`"qwen"` for `<think>` tags) |
| `reasoning` | Model definition | Enables SDK thinking support (prevents forced `thinkingLevel=off`) |
| `agents.defaults.thinkingDefault` | Agent defaults | Default thinking level for all sessions |
| `agents.defaults.models.*.streaming` | Per-model config | Disable streaming (required for Qwen tool calling) |
| `OLLAMA_STREAM` | .env | Disable Ollama request streaming (critical for tool calls) |
| `OLLAMA_KV_CACHE_TYPE` | .env | KV cache quantization (`q4_0` to fit more on GPU) |

## Compatibility Notes

- **Backward compatible**: All features are opt-in. Without `routeToolsAsBuiltIn: true`, behaviour is identical to upstream.
- **Streaming must be disabled** for Qwen models when using tool calling — Ollama doesn't emit `tool_calls` in stream chunks when thinking is enabled. Set `OLLAMA_STREAM=false` in `.env`.
- **`tool_choice` is NOT supported** by Ollama's native API. Do not send it.
- **Context window**: Local models need sufficient context for the system prompt (~27k chars) plus tool schemas. 20k minimum recommended.
- **KV cache**: Use `q4_0` quantization to fit more context on GPU with limited VRAM.
- **Tested with**: Qwen 3 4B, 8B, and 14B via Ollama on NVIDIA RTX 2050 (4GB VRAM).

### 6. Cron Tool Call Repair for Small Models

**File modified:**
- `src/cron/normalize.ts`
- `src/agents/tools/cron-tool.ts`

**Background:**
Small local models (Qwen3.5 4B) produce malformed cron tool call JSON in
two distinct failure modes:

1. **Mangled key notation.** The model uses extra characters as a
   "shorthand" for nested object boundaries, emitting keys like
   `"schedule\": {"` (with literal `\"`, `:`, space, `{` baked into the
   key string). The brace count is balanced and `JSON.parse` succeeds —
   but the parsed object has semantically wrong key names (`schedule": {`
   instead of `schedule`). The model uses different "junk char" variants
   (`\":`, `':`, etc.) that all fit the same pattern.

2. **Orphaned top-level fields.** The model often closes the `job`
   object early and emits required fields (`payload`, `sessionTarget`,
   `delivery`, `enabled`) as siblings of `job` at the top level instead
   of inside it.

**What `repairMangledKeys()` does** (in `normalize.ts`):
Detects keys matching `^[A-Za-z_][A-Za-z0-9_]*` followed by a non-word
character (the model's mangled-key pattern). Renames each mangled key
to its leading word-character prefix and rebinds the value. Recurses
into nested objects so deeper mangling is also repaired. Safe for
clean keys — they don't match the regex.

**What `reconstructPrefixedFields()` does** (in `normalize.ts`):
A second small-model failure mode is flattening nested objects into
underscore-prefixed keys (e.g. `schedule_kind: "at"` instead of
`schedule: { kind: "at" }`). Maps recognised prefixed keys
(`schedule_kind`, `payload_text`, `delivery_mode`, etc.) back into
nested objects. Also handles `sessionTarget_main` → `sessionTarget: "main"`
and bare `at` field → `schedule.at`.

**What the orphan-merge does** (in `cron-tool.ts`, around line 559):
The existing flat-params recovery only fired when `params.job` was
completely missing/empty. Extended to ALSO fire when `params.job` is
partially populated and there are recoverable fields at the top level
that aren't already in `job`. Top-level fields fill gaps but never
override values already inside `params.job`. This catches the
"closed-job-early" case where the model produces a partial `job`
plus orphan top-level `payload`/`sessionTarget`/`delivery`/`enabled`.

**Pipeline order in `normalizeCronJobInput`:**
1. `coerceStringifiedObjectFields(base)` — parse stringified nested objects
2. `repairMangledKeys(base)` — clean up mangled-key notation
3. `reconstructPrefixedFields(base)` — rebuild from underscore-prefixed flats

The orphan-merge in `cron-tool.ts` runs in the cron tool's own
`execute` function before `normalizeCronJobCreate` is called.

**Why this is needed:**
Frontier models (Anthropic, OpenAI) produce well-formed cron JSON
on the first try. The Qwen3.5 4B local model emits these patterns
~80% of the time. Without the repair layers, every cron call fails
schema validation; with them, the model's intended structure is
recovered and the call succeeds.

## Related Upstream Issues

- [PR #9339](https://github.com/openclaw/openclaw/pull/9339) — Closed. Proposed `compat.openaiCompletionsTools` flag (similar approach, different implementation).
- [PR #4287](https://github.com/openclaw/openclaw/pull/4287) — Closed. Tool passing for openai-completions driver.
- [jokelord/openclaw-local-model-tool-calling-patch](https://github.com/jokelord/openclaw-local-model-tool-calling-patch) — Community patch for older version (2026.2.3), uses `supportedParameters` approach.
