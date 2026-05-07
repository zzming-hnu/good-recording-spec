#!/usr/bin/env bash
# Constitution V (本地可观测与可恢复) guard: validate that emitted local logs
# conform to home-spec/specs/001-good-recording/contracts/logs.md schema.
#
# v1 status: STUB — full implementation lands together with T016 (Sources/Core/Logging)
#            since validating a non-existent logger is meaningless.
#            T010 ships only the script harness so CI lint job exists from day 1.

set -euo pipefail

echo "⚠️  check-logs-contract.sh: stub" >&2
echo "    Full implementation lands alongside T016 (Sources/Core/Logging)." >&2
echo "    Will:" >&2
echo "      1. Run a scripted recording to flush all event types in the catalog" >&2
echo "      2. Parse each line as JSON; assert required common fields exist" >&2
echo "      3. Assert no forbidden substrings (password|token|secret|bearer)" >&2
echo "      4. Assert log rotation: dir size cap + 30-day retention" >&2
exit 0
