#!/bin/sh
# verify.sh — sanity check that the openclaw-patches landed in a target tree
#
# Greps for known marker strings in the patched source files. Cheap smoke test
# for use after running apply.sh, before kicking off a docker build.
#
# Usage: sh verify.sh <target-source-dir>

set -eu

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "verify.sh: error — target source directory required" >&2
  echo "usage: sh verify.sh <target-source-dir>" >&2
  exit 2
fi

if [ ! -d "$TARGET" ]; then
  echo "verify.sh: error — target directory does not exist: $TARGET" >&2
  exit 2
fi

failed=0

check() {
  file="$1"
  needle="$2"
  label="$3"
  if [ ! -f "$TARGET/$file" ]; then
    echo "verify.sh: MISS  $label  ($file not found)"
    failed=$((failed + 1))
    return
  fi
  if grep -q -F -- "$needle" "$TARGET/$file"; then
    echo "verify.sh: OK    $label"
  else
    echo "verify.sh: MISS  $label  (marker not found in $file)"
    failed=$((failed + 1))
  fi
}

echo "verify.sh: checking patches in $TARGET"

# 02-qwen-compat
check "src/agents/pi-embedded-runner/tool-split.ts"     "routeToolsAsBuiltIn"        "qwen-compat: tool-split routeToolsAsBuiltIn"
check "src/agents/pi-embedded-runner/run/attempt.ts"    "routeToolsAsBuiltIn"        "qwen-compat: attempt routeToolsAsBuiltIn"
check "src/agents/pi-embedded-runner/compact.ts"        "routeToolsAsBuiltIn"        "qwen-compat: compact routeToolsAsBuiltIn"
check "src/config/zod-schema.core.ts"                   "routeToolsAsBuiltIn"        "qwen-compat: zod schema routeToolsAsBuiltIn"
check "extensions/ollama/src/stream.ts"                 "createOllamaThinkingOnWrapper" "qwen-compat: ollama thinking-on wrapper"

# 03-cron-robustness
check "src/cron/normalize.ts"                           "repairMangledKeys"          "cron-robustness: repairMangledKeys"
check "src/cron/normalize.ts"                           "reconstructPrefixedFields"  "cron-robustness: reconstructPrefixedFields"
check "src/agents/tools/cron-tool.ts"                   "CRON_RECOVERABLE_OBJECT_KEYS" "cron-robustness: orphan-merge"

# 04-tool-loop-detection
check "src/agents/pi-embedded-subscribe.types.ts"       "onToolLoopDetected"         "tool-loop: onToolLoopDetected callback type"
check "src/agents/pi-embedded-subscribe.handlers.tools.ts" "loop"                    "tool-loop: handler implementation"
check "src/agents/pi-embedded-runner/run/attempt.ts"    "onToolLoopDetected"         "tool-loop: attempt loop-abort handler"

# 01-sdk-tools-filter (verifies the SDK has been monkey-patched)
check "node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js" "options.customTools" "sdk-tools-filter: customTools whitelist"

if [ "$failed" -gt 0 ]; then
  echo "verify.sh: $failed check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
