#!/usr/bin/env bash
# Constitution III (独立可测与渐进交付) hard guard: reject any cross-Feature
# `import US{N}_*` to keep user stories independently disable-able.
#
# Source of truth:
#   home-spec/.specify/memory/constitution.md (Principle III, NON-NEGOTIABLE)
#   home-spec/specs/001-good-recording/plan.md (Project Structure)
#
# Wired as a Run Script Phase on the GoodRecording target so violations
# fail the build before linking.

set -euo pipefail

cd "$(dirname "$0")/../.."

FAIL=0

# Use find for portability with macOS system bash (3.2). Skips silently when
# Sources/Features doesn't exist yet (Phase 1 skeleton state).
if [[ -d Sources/Features ]]; then
    while IFS= read -r f; do
        this_us="$(printf '%s' "$f" | sed -E 's|^Sources/Features/(US[0-9]+)-.*$|\1|')"
        while IFS= read -r line; do
            other_us="$(printf '%s' "$line" | sed -nE 's|^[[:space:]]*import[[:space:]]+(US[0-9]+)_.*$|\1|p')"
            if [[ -n "$other_us" && "$other_us" != "$this_us" ]]; then
                echo "❌ Cross-feature import in $f:" >&2
                echo "     $line" >&2
                echo "   ($this_us is not allowed to import $other_us — Constitution III)" >&2
                FAIL=1
            fi
        done < <(grep -E '^[[:space:]]*import[[:space:]]+US[0-9]+_' "$f" 2>/dev/null || true)
    done < <(find Sources/Features -type f -name '*.swift' 2>/dev/null)
fi

if [[ $FAIL -eq 0 ]]; then
    echo "✅ Cross-feature import lint passed."
fi

exit $FAIL
