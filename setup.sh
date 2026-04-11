#!/usr/bin/env sh
# setup.sh — OPTIONAL: re-pin openclaw-src/ to a newer upstream commit.
#
# You do NOT need to run this for a normal build. openclaw-src/ is vendored
# directly in this repo at a known-good commit with the Dockerfile hook
# already applied, so a plain `git clone` + `docker build` works out of the
# box. See README.md for the quick-start path.
#
# This script is only for maintainers who want to rebase the vendored
# openclaw-src/ tree onto a newer upstream OpenClaw commit. It:
#   1. Removes the current vendored openclaw-src/
#   2. Clones upstream at PINNED_COMMIT below
#   3. Applies openclaw-patches/dockerfile-hook.patch
#   4. Leaves the new tree staged for you to review and commit
#
# After it runs, verify the patches still apply with a full `docker build`,
# then regenerate any failing patches per openclaw-patches/CLAUDE.md before
# committing. Upstream may have rewritten context lines in files touched by
# 02-qwen-compat/ or 03-cron-robustness/ — those patches may need fresh hunks.
#
# Usage:   sh setup.sh
set -eu

PINNED_COMMIT="001e0c1f65c4bfdf310a5161cde25696e868af20"
UPSTREAM_URL="https://github.com/openclaw/openclaw.git"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

HOOK_PATCH="openclaw-patches/dockerfile-hook.patch"

if [ ! -f "$HOOK_PATCH" ]; then
  echo "setup.sh: missing $HOOK_PATCH — are you running from the project root?" >&2
  exit 1
fi

if [ -d openclaw-src ]; then
  printf "setup.sh: openclaw-src/ already exists and will be REMOVED before re-cloning.\n"
  printf "setup.sh: continue? [y/N] "
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "setup.sh: aborted."; exit 1 ;;
  esac
  rm -rf openclaw-src
fi

echo "setup.sh: cloning upstream openclaw at ${PINNED_COMMIT}..."
git clone --no-checkout "$UPSTREAM_URL" openclaw-src
git -C openclaw-src checkout "$PINNED_COMMIT"
rm -rf openclaw-src/.git

echo "setup.sh: applying Dockerfile build-context hook..."
patch --forward -p1 -d openclaw-src < "$HOOK_PATCH"

echo "setup.sh: done."
echo "setup.sh: review the new openclaw-src/ tree, run a full docker build,"
echo "setup.sh: then 'git add openclaw-src' and commit when you're happy."
