#!/usr/bin/env bash
# Signs the app with the stable self-signed identity, so its designated requirement
# (and with it Keychain access and notification permission) survives updates.
set -euo pipefail

app="${1:?usage: codesign-app.sh <path/to/Docket.app>}"
identity="${SIGN_IDENTITY:-Docket Self-Signed Code Signing}"
keychain_args=()
if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then
  keychain_args=(--keychain "$SIGN_KEYCHAIN")
fi

codesign --force --deep --timestamp=none --sign "$identity" "${keychain_args[@]}" "$app"
codesign --verify --deep --strict "$app"
codesign --display --requirements - "$app" 2>/dev/null | grep '^designated'
