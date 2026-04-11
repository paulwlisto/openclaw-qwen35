# openclaw-patches

Fork patches for our local OpenClaw build, kept **outside** of `openclaw-src/`
so that the upstream checkout can stay clean and be `git fetch`/`git checkout`-ed
to a new commit without losing our modifications.

The patches are re-applied at docker build time by `apply.sh`, which is
invoked from `openclaw-src/Dockerfile`. The build context for the
`openclaw-patched:latest` image is the **project root**
(`./`), so both `openclaw-src/` and
`openclaw-patches/` are visible to the Dockerfile.

## Layout

```
openclaw-patches/
├── README.md          ← this file
├── apply.sh           ← idempotent applier (runs all .patch and .sh files in sorted order)
├── verify.sh          ← post-apply sanity check (greps for known marker strings)
└── files/
    ├── 01-sdk-tools-filter/
    │   └── patch-sdk-tools.sh        ← node_modules monkey-patch (runs after pnpm install)
    ├── 02-qwen-compat/
    │   ├── 01-zod-schema.core.ts.patch
    │   ├── 02-tool-split.ts.patch
    │   ├── 03-compact.ts.patch
    │   ├── 04-attempt.ts.patch
    │   └── 05-ollama-stream.ts.patch
    ├── 03-cron-robustness/
    │   ├── 01-normalize.ts.patch
    │   └── 02-cron-tool.ts.patch
    └── 04-tool-loop-detection/
        ├── 01-subscribe-types.ts.patch
        ├── 02-handlers-types.ts.patch
        ├── 03-subscribe.ts.patch
        ├── 04-handlers-tools.ts.patch
        └── 06-test-fixtures.ts.patch
```

> Note: `attempt.ts` is patched once in `02-qwen-compat/04-attempt.ts.patch`.
> Its hunks span both feature groups — the `routeToolsAsBuiltIn` flag for
> tool routing and the `onToolLoopDetected` handler for the loop circuit
> breaker — but they're interleaved in the same file and can't be split
> cleanly without manual hunk surgery, so we keep them in one patch.
>
> The `Dockerfile` is **not** patched via `apply.sh`. It is directly edited
> in `openclaw-src/Dockerfile` to add the `apply.sh` hook itself
> (chicken-and-egg: the applier is invoked from the Dockerfile).

Files inside each `files/NN-feature/` directory are processed in **lexical
order**, so the numeric prefixes control application order. Within a feature
directory the order rarely matters, but the prefixes keep things deterministic.

## Feature groups

| # | Group | What it does |
|---|---|---|
| 01 | sdk-tools-filter | Monkey-patches `node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js` so its `allTools` filter also accepts names from `customTools`. Required for OpenClaw's tools to survive the SDK's tool-name validation. |
| 02 | qwen-compat | Adds the `routeToolsAsBuiltIn` model-compat flag (so local models like Qwen on llama.cpp/Ollama can see tool definitions in the API request), plus Qwen thinking-level controls and an Ollama `<think>` stream wrapper. |
| 03 | cron-robustness | `repairMangledKeys` + `reconstructPrefixedFields` + orphan-merge logic in the cron tool, recovering broken JSON structures emitted by small local models when calling `cron.add`. |
| 04 | tool-loop-detection | Circuit breaker that aborts a run when the same tool is called repeatedly with identical arguments — protects against the model getting stuck in a tool-call loop. |

## Applying the patches

The patches are applied automatically during `docker build`. The Dockerfile
copies this directory into `/tmp/openclaw-patches` and runs `apply.sh /app`
right after the source `COPY . .`.

To apply manually (e.g. when working on patches outside docker), from the
project root:

```sh
sh openclaw-patches/apply.sh ./openclaw-src
```

`apply.sh` uses `patch --forward -p0`, which is **idempotent**: running it
twice on an already-patched tree is a no-op rather than a failure.

## Upgrade workflow

When upstream OpenClaw releases a new commit and we want to rebase onto it:

```sh
# 1. Reset openclaw-src to clean upstream
git -C ./openclaw-src fetch origin
git -C ./openclaw-src checkout origin/main

# 2. Build the patched image (patches re-applied automatically)
docker build -f ./openclaw-src/Dockerfile \
  -t openclaw-patched:latest \
  .

# 3. Restart the gateway with the new image
docker compose --profile llamacpp up -d openclaw-gateway
```

If a patch fails to apply because upstream changed the surrounding context,
the docker build fails loudly with the offending `.patch` filename. To fix:

```sh
# 1. Inspect the conflict
patch --dry-run -p0 -d ./openclaw-src \
  < ./openclaw-patches/files/03-cron-robustness/01-normalize.ts.patch

# 2. Manually re-apply the change to openclaw-src/, then regenerate the patch
git -C ./openclaw-src diff --no-prefix HEAD \
  -- src/cron/normalize.ts \
  > ./openclaw-patches/files/03-cron-robustness/01-normalize.ts.patch
```

## Regenerating an existing patch

If you make additional in-tree edits in `openclaw-src/` for an existing
feature, regenerate just that file's patch with:

```sh
git -C ./openclaw-src diff --no-prefix HEAD \
  -- <path/to/file.ts> \
  > ./openclaw-patches/files/<NN-group>/<NN-name.patch>
```

Then reset openclaw-src to a clean state and rebuild to verify.
