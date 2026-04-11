#!/bin/sh
# Patch pi-coding-agent SDK to extend allTools filter with customTools names.
# This allows OpenClaw tools routed as builtInTools to pass the SDK's
# tool name validation when they also appear in customTools.
SDK_FILE="node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js"

if [ ! -f "$SDK_FILE" ]; then
  echo "patch-sdk-tools.sh: SDK file not found at $SDK_FILE — running from wrong directory?" >&2
  exit 1
fi

node -e "
const fs = require('fs');
let code = fs.readFileSync('${SDK_FILE}', 'utf8');
const oldStr = 'options.tools.map((t) => t.name).filter((n) => n in allTools)';
const newStr = 'options.tools.map((t) => t.name).filter((n) => n in allTools || (options.customTools && options.customTools.some(ct => ct.name === n)))';
if (code.includes(newStr)) {
  console.log('SDK tool filter already patched (idempotent re-run, no-op)');
} else if (code.includes(oldStr)) {
  code = code.replace(oldStr, newStr);
  fs.writeFileSync('${SDK_FILE}', code);
  console.log('SDK tool filter patched successfully');
} else {
  console.error('SDK tool filter: neither old nor new pattern found — upstream sdk.js changed shape');
  process.exit(1);
}
"
