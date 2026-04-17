#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  GGUF chain-of-custody verifier
# ═══════════════════════════════════════════════════════════════════
#
#  Downloads a GGUF from a HuggingFace repo and verifies its SHA256
#  against the LFS pointer metadata published by HF. Fails loudly if
#  the bytes on disk don't match what the upstream repo claims.
#
#  The LFS OID in HF's tree API IS the SHA256 of the stored blob, so
#  matching local-computed sha256 against that OID proves the file
#  came from the upstream repo without alteration in transit.
#
#  Usage:
#    ./verify-and-download.sh <hf_repo> <filename>
#
#  Example:
#    ./verify-and-download.sh bartowski/Qwen_Qwen3.5-2B-GGUF Qwen_Qwen3.5-2B-Q6_K.gguf
#
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

REPO="${1:-}"
FILE="${2:-}"

if [[ -z "$REPO" || -z "$FILE" ]]; then
  echo "usage: $0 <hf_repo> <filename>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${SCRIPT_DIR}/${FILE}"

echo "── Looking up $REPO :: $FILE ──"

# Query HF tree API for the expected LFS sha256 + size.
META=$(curl -sfL "https://huggingface.co/api/models/${REPO}/tree/main" \
  | python -c "
import json, sys
data = json.load(sys.stdin)
for f in data:
    if f.get('type') == 'file' and f.get('path') == '$FILE':
        lfs = f.get('lfs', {}) or {}
        print(lfs.get('oid', '') + ' ' + str(lfs.get('size', 0)))
        break
")

if [[ -z "$META" || "$META" == " 0" ]]; then
  echo "  ✘ file not found in repo or no LFS metadata" >&2
  exit 3
fi

EXPECTED_SHA256="${META% *}"
EXPECTED_SIZE="${META##* }"
echo "  expected sha256: $EXPECTED_SHA256"
echo "  expected size:   $EXPECTED_SIZE bytes"

# Skip download if we already have a good copy.
if [[ -f "$DEST" ]]; then
  ACTUAL_SIZE=$(stat -c %s "$DEST" 2>/dev/null || stat -f %z "$DEST")
  if [[ "$ACTUAL_SIZE" == "$EXPECTED_SIZE" ]]; then
    echo "── Existing file matches size, verifying hash ──"
    ACTUAL_SHA256=$(sha256sum "$DEST" | awk '{print $1}')
    if [[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]]; then
      echo "  ✓ sha256 matches, nothing to do"
      exit 0
    fi
    echo "  ✘ sha256 mismatch on existing file, re-downloading" >&2
  else
    echo "── Existing file has wrong size, re-downloading ──" >&2
  fi
fi

echo "── Downloading $FILE (~$((EXPECTED_SIZE / 1000000)) MB) ──"
curl -fL --progress-bar \
  -o "$DEST" \
  "https://huggingface.co/${REPO}/resolve/main/${FILE}"

echo "── Verifying sha256 ──"
ACTUAL_SHA256=$(sha256sum "$DEST" | awk '{print $1}')
echo "  computed: $ACTUAL_SHA256"
echo "  expected: $EXPECTED_SHA256"

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "  ✘ SHA256 MISMATCH — file may have been tampered with in transit" >&2
  echo "  Deleting corrupted file and aborting." >&2
  rm -f "$DEST"
  exit 4
fi

echo "  ✓ sha256 verified, chain of custody intact"
echo "── Saved: $DEST ──"
