#!/bin/zsh
#
# Create a local self-signed code signing identity for Agent Deck dev
# builds. One-time setup; idempotent on re-run.
#
# Why this exists
# ---------------
# Without a stable signing identity, `launch-dev-app.sh` ad-hoc signs
# the dev bundle with `codesign --sign -`, which produces a new cdhash
# every rebuild. macOS TCC tracks Accessibility (and other) permission
# grants for ad-hoc binaries by cdhash, so every `swift build` silently
# invalidates any grant the developer had previously approved. That
# makes iterating on features that require Accessibility permission —
# precision jump, keystroke injection, menu clicks — almost impossible
# without re-dragging the .app into System Settings → Privacy &
# Security → Accessibility every single iteration.
#
# With a real signing identity (even self-signed local), TCC tracks the
# grant by the certificate's designated requirement instead of cdhash.
# The cert doesn't change between rebuilds, so the permission persists.
#
# What this script does
# ---------------------
# 1. Generates an RSA 2048, 10-year, Code-Signing-EKU self-signed cert
#    via openssl.
# 2. Imports the cert + private key into the login keychain, with the
#    key ACL set so /usr/bin/codesign can use it non-interactively.
# 3. Adds a user-level Code Signing trust override so the identity
#    shows up as valid in `security find-identity -p codesigning -v`.
#
# The cert is scoped to the developer's login keychain, never touches
# the system keychain, and requires no sudo.
#
# What to do with it
# ------------------
# After running this once, `launch-dev-app.sh` auto-detects the
# identity and uses it. On the first run after signing, you still have
# to grant Accessibility once (System Settings → Privacy & Security
# → Accessibility → drag the .app from ~/Applications/ into the
# list). From that grant onwards, permission persists across rebuilds.
#
# To undo: `security delete-identity -Z <sha1> ~/Library/Keychains/login.keychain-db`
# where <sha1> is from `security find-identity -p codesigning -v`. Also
# `security remove-trusted-cert <cert.pem>` if you want the trust
# override gone.

set -euo pipefail

IDENTITY_NAME="Agent Deck Dev Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY_NAME\""; then
    echo "✓ Code signing identity \"$IDENTITY_NAME\" already exists and is trusted."
    echo "  launch-dev-app.sh will use it automatically."
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "✗ openssl is required but not on PATH." >&2
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

key_pem="$tmp_dir/key.pem"
cert_pem="$tmp_dir/cert.pem"
cert_p12="$tmp_dir/cert.p12"
# The p12 password is ephemeral — it exists for the duration of this
# script only, used to hand the cert + key from openssl to security and
# then discarded. It is NOT a persistent secret.
p12_password=$(openssl rand -hex 16)

echo "• Generating 10-year self-signed code signing certificate…"
openssl req -x509 -newkey rsa:2048 \
    -keyout "$key_pem" -out "$cert_pem" \
    -days 3650 -nodes \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    2>/dev/null

# `-legacy` uses the older PKCS#12 encryption format that Apple's
# `security` tool can read. Modern OpenSSL 3.x defaults to a format
# Apple hasn't adopted; without this flag the import fails with
# "MAC verification failed during PKCS12 import".
echo "• Packaging into PKCS#12 (legacy format for Apple compatibility)…"
openssl pkcs12 -export -legacy \
    -out "$cert_p12" -inkey "$key_pem" -in "$cert_pem" \
    -name "$IDENTITY_NAME" \
    -password "pass:$p12_password" \
    2>/dev/null

# `-T /usr/bin/codesign` adds codesign to the key ACL so codesign can
# use the private key non-interactively (no "allow?" prompt per build).
echo "• Importing into login keychain…"
security import "$cert_p12" \
    -k "$KEYCHAIN" \
    -P "$p12_password" \
    -T /usr/bin/codesign \
    >/dev/null

# Without this trust override the cert imports but
# `security find-identity -p codesigning -v` filters it out as
# CSSMERR_TP_NOT_TRUSTED, and codesign will refuse to use it by name.
# `-p codeSign` is a user-level trust for Code Signing only — does not
# touch system trust stores and does not require sudo.
echo "• Adding Code Signing trust override…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$cert_pem" >/dev/null

echo
echo "✓ Identity \"$IDENTITY_NAME\" created and trusted."
security find-identity -p codesigning -v "$KEYCHAIN" | grep "\"$IDENTITY_NAME\""
echo
echo "Next: run \`zsh scripts/launch-dev-app.sh\`. The bundle will now be"
echo "signed with this identity, and any Accessibility/Automation grant"
echo "you give Agent Deck Dev will persist across rebuilds."
