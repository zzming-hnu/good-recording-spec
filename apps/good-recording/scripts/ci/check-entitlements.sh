#!/usr/bin/env bash
# Constitution I (本地优先与隐私保护) hard guard: reject any entitlement that
# would let the app reach the network or escape the sandbox.
#
# Source of truth:
#   home-spec/specs/001-good-recording/contracts/permissions.md
#   home-spec/.specify/memory/constitution.md (Principle I, NON-NEGOTIABLE)

set -euo pipefail

ENTITLEMENTS="$(dirname "$0")/../../Resources/GoodRecording.entitlements"

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "❌ Entitlements file missing at $ENTITLEMENTS" >&2
    exit 1
fi

FORBIDDEN_KEYS=(
    "com.apple.security.network.client"
    "com.apple.security.network.server"
    "com.apple.security.cs.disable-library-validation"
    "com.apple.security.cs.allow-unsigned-executable-memory"
)

FAIL=0

for key in "${FORBIDDEN_KEYS[@]}"; do
    if /usr/libexec/PlistBuddy -c "Print :${key}" "$ENTITLEMENTS" >/dev/null 2>&1; then
        echo "❌ Forbidden entitlement present: $key" >&2
        FAIL=1
    fi
done

# Substring match for any temporary-exception entitlement
if grep -q "com.apple.security.temporary-exception" "$ENTITLEMENTS"; then
    echo "❌ Temporary-exception entitlement present" >&2
    echo "   (constitution requires Complexity Tracking entry; halt and escalate)" >&2
    FAIL=1
fi

if [[ $FAIL -eq 0 ]]; then
    echo "✅ Entitlements lint passed (no forbidden keys)."
fi

exit $FAIL
