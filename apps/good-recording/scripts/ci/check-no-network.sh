#!/usr/bin/env bash
# SC-006 verifier: assert zero outbound network traffic from the GoodRecording
# process during a scripted recording session.
#
# Source of truth:
#   home-spec/specs/001-good-recording/spec.md (SC-006)
#   home-spec/specs/001-good-recording/quickstart.md §6
#
# v1 status: STUB — full implementation lands in T114 (Polish phase).
#            Wire to `nettop -P -p $PID -L 1` once a recording fixture exists.

set -euo pipefail

echo "⚠️  check-no-network.sh: stub" >&2
echo "    Full implementation lands in T114 (Polish phase) and:" >&2
echo "      1. Launches GoodRecording with a deterministic 5s recording fixture" >&2
echo "      2. Captures \`nettop -P -p \$PID -L 1\` output for that PID" >&2
echo "      3. Asserts zero out-of-bundle TCP/UDP traffic" >&2
exit 0
