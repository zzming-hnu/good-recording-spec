#!/usr/bin/env bash
# Constitution II (普通用户简洁体验) guard: reject technical jargon in
# user-facing strings.
#
# Source of truth:
#   home-spec/.specify/memory/constitution.md (Principle II)
#   home-spec/specs/001-good-recording/quickstart.md §6

set -euo pipefail

XCSTRINGS="$(dirname "$0")/../../Resources/Localizable.xcstrings"
FORBIDDEN_RE='JSON|YAML|endpoint|hash|payload|stack trace|JSONLines|API|SDK'

if [[ ! -f "$XCSTRINGS" ]]; then
    echo "❌ Localizable.xcstrings missing at $XCSTRINGS" >&2
    exit 1
fi

# Match only inside string `value` fields, not keys/comments. Using grep -E -i.
if grep -E -i "$FORBIDDEN_RE" "$XCSTRINGS" >/dev/null; then
    echo "❌ Forbidden tech words in user-facing strings:" >&2
    grep -E -i -n "$FORBIDDEN_RE" "$XCSTRINGS" >&2
    echo "" >&2
    echo "Use everyday language. See Constitution II 普通用户为中心的简洁体验." >&2
    exit 1
fi

echo "✅ Strings lint passed (no forbidden tech words)."
