#!/usr/bin/env bash
# Create a local, stable self-signed code-signing certificate for
# good-recording dev builds.
#
# Why: macOS 26 silently denies ScreenCaptureKit (and other TCC-gated
# capabilities) to ad-hoc-signed sandboxed apps. We need a stable
# code-signing identity so that:
#   1. Every xcodebuild produces a binary signed by the same identity
#   2. macOS TCC can identify the app reliably across rebuilds
#   3. The user's "allow Screen Recording" grant stays valid
#
# Idempotent: safe to re-run (will reuse existing cert if present).
#
# Requires: openssl (bundled with macOS), security (bundled with macOS),
#           sudo (only for trust step).
#
# Usage:
#   ./scripts/make-local-cert.sh

set -euo pipefail

CERT_NAME="GoodRecording Local Dev"
CERT_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo " good-recording — Local self-signed code-signing setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 0. Skip if cert already there
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✅ Certificate \"$CERT_NAME\" already in keychain. Nothing to do."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

echo "→ Step 1/5: Generating RSA private key + self-signed certificate"
cd "$TMP_DIR"

# Build x509 with code-signing extended key usage (oid 1.3.6.1.5.5.7.3.3)
cat > openssl.cnf <<EOF
[ req ]
default_bits        = 2048
default_md          = sha256
prompt              = no
distinguished_name  = dn
x509_extensions     = v3_codesign

[ dn ]
CN = $CERT_NAME
O  = good-recording (local dev)
C  = US

[ v3_codesign ]
basicConstraints      = critical, CA:FALSE
keyUsage              = critical, digitalSignature
extendedKeyUsage      = critical, codeSigning
nsCertType            = objsign
EOF

openssl req -new -x509 -newkey rsa:2048 -nodes \
    -keyout cert.key -out cert.crt -days 3650 \
    -config openssl.cnf 2>/dev/null

# NOTE: OpenSSL 3 + empty password creates a .p12 with PBES2-encrypted
# MAC that macOS `security import` cannot validate. Use a fixed non-empty
# throwaway password — it only protects the .p12 in transit between the
# two CLIs (the file is deleted at end-of-script).
P12_PASS="goodrecording"

# -legacy forces OpenSSL 3 to use the original PKCS#12 v1 ciphers (PBE
# with SHA1 + 3DES + RC2-40), which is what macOS `security` reliably
# understands. Without -legacy, OpenSSL 3 defaults to PBES2 + AES which
# macOS rejects with "MAC verification failed".
OPENSSL_LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    OPENSSL_LEGACY="-legacy"
fi

openssl pkcs12 -export $OPENSSL_LEGACY -out cert.p12 \
    -inkey cert.key -in cert.crt \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASS" 2>/dev/null

echo "  ✅ cert.p12 generated"

echo ""
echo "→ Step 2/5: Importing cert + private key into login keychain"
echo "  (Keychain Access may pop up asking you to allow access — click Always Allow)"
security import cert.p12 -k "$CERT_KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/productsign \
    2>&1 | sed 's/^/  /'

echo ""
echo "→ Step 3/5: Granting codesign permission to access the private key without prompting"
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$CERT_KEYCHAIN" 2>/dev/null || true

echo ""
echo "→ Step 4/5: Trusting the certificate as a code-signing root"
echo "  (sudo will be requested)"
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    cert.crt
echo "  ✅ Cert trusted system-wide for code signing"

echo ""
echo "→ Step 5/5: Verifying"
sleep 1
security find-identity -v -p codesigning | sed 's/^/  /'

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " ✅ Local code-signing identity ready: \"$CERT_NAME\""
echo "════════════════════════════════════════════════════════════════"
echo ""

# ─── Auto-rebuild + open with the new identity ──────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Kill any running instance so the new cdhash takes effect.
pkill -x GoodRecording 2>/dev/null || true

echo "→ Regenerating Xcode project + rebuilding with new identity"
xcodegen generate 2>&1 | tail -3 | sed 's/^/  /'

ARCH="$(uname -m)"
xcodebuild build \
    -scheme GoodRecording \
    -configuration Debug \
    -destination "platform=macOS,arch=${ARCH}" \
    -quiet 2>&1 | tail -5 | sed 's/^/  /'

APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData/GoodRecording-* -type d -name 'GoodRecording.app' -path '*/Debug/*' 2>/dev/null | head -1)"

if [[ -n "${APP_PATH:-}" && -d "$APP_PATH" ]]; then
    echo ""
    echo "→ Opening $APP_PATH"
    open "$APP_PATH"
    echo ""
    echo "✅ Done. The first click of 开始录制 will trigger the macOS"
    echo "   native Screen Recording dialog (this time it will actually"
    echo "   appear because the app is now properly signed). Grant once,"
    echo "   restart the app, and it stays granted across all future"
    echo "   rebuilds (cdhash is now stable via the same identity)."
else
    echo "⚠️  Build succeeded but couldn't locate the .app bundle. Re-run:"
    echo "   open ~/Library/Developer/Xcode/DerivedData/GoodRecording-*/Build/Products/Debug/GoodRecording.app"
fi
echo ""
