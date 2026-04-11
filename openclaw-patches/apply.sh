#!/bin/sh
# apply.sh — apply all openclaw-patches to a target source tree
#
# Usage: sh apply.sh [--no-scripts] <target-source-dir>
#
# Walks files/*/ in lexical order. For each entry:
#   *.patch  → patch --forward -p0 -d <target>
#   *.sh     → sh <file> (cwd = <target>)   [skipped with --no-scripts]
#
# Idempotent: patch --forward exits 0 on already-applied hunks (with a
# warning), so re-running this script on a patched tree is a no-op.
#
# Exits non-zero on the first hard failure (genuine conflict, missing file,
# etc.) so the docker build halts loudly.
#
# --no-scripts skips .sh entries — useful for verification against a
# bare source tree without node_modules.

set -eu

NO_SCRIPTS=0
if [ "${1:-}" = "--no-scripts" ]; then
  NO_SCRIPTS=1
  shift
fi

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "apply.sh: error — target source directory required" >&2
  echo "usage: sh apply.sh [--no-scripts] <target-source-dir>" >&2
  exit 2
fi

if [ ! -d "$TARGET" ]; then
  echo "apply.sh: error — target directory does not exist: $TARGET" >&2
  exit 2
fi

# Resolve our own location so we can find files/ regardless of cwd.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

if [ ! -d "$FILES_DIR" ]; then
  echo "apply.sh: error — patches directory not found: $FILES_DIR" >&2
  exit 2
fi

echo "apply.sh: applying patches from $FILES_DIR to $TARGET"

# Iterate group directories in sorted order.
for group_dir in "$FILES_DIR"/*/; do
  [ -d "$group_dir" ] || continue
  group_name="$(basename "$group_dir")"
  echo "apply.sh: --- group: $group_name ---"

  # Iterate files inside the group in sorted order.
  for entry in "$group_dir"*; do
    [ -f "$entry" ] || continue
    entry_name="$(basename "$entry")"

    case "$entry_name" in
      *.patch)
        echo "apply.sh:   applying patch: $entry_name"
        # --forward: skip already-applied hunks (idempotency)
        # -p0:      patch generated with --no-prefix, no leading components to strip
        # -d:       cd to target before applying
        # --batch:  never prompt
        #
        # Disable `set -e` around patch so we can read its exit code:
        # patch returns 0 = applied, 1 = already applied (idempotent), 2+ = real failure.
        # -r /dev/null discards reject files so the source tree stays clean
        # when re-runs hit the already-applied path.
        set +e
        patch --forward --batch -p0 -r /dev/null -d "$TARGET" < "$entry"
        rc=$?
        set -e
        if [ "$rc" -eq 0 ]; then
          : # applied cleanly
        elif [ "$rc" -eq 1 ]; then
          echo "apply.sh:   (already applied)"
        else
          echo "apply.sh: ERROR — patch failed: $entry_name (exit $rc)" >&2
          exit "$rc"
        fi
        ;;
      *.sh)
        if [ "$NO_SCRIPTS" -eq 1 ]; then
          echo "apply.sh:   skipping script (--no-scripts): $entry_name"
        else
          echo "apply.sh:   running script: $entry_name"
          (cd "$TARGET" && sh "$entry")
        fi
        ;;
      *)
        echo "apply.sh:   skipping (unknown extension): $entry_name"
        ;;
    esac
  done
done

echo "apply.sh: done"
