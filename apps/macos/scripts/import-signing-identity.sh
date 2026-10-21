#!/usr/bin/env bash
# CI only: imports the signing identity from P12 / P12_PASSWORD into a throwaway keychain
# added to the search list, and prints the keychain path.
set -euo pipefail

: "${P12:?P12 is required}" "${P12_PASSWORD:?P12_PASSWORD is required}"
keychain="${RUNNER_TEMP:-/tmp}/signing.keychain-db"
password=$(openssl rand -hex 16)

security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 900 "$keychain"
security unlock-keychain -p "$password" "$keychain"
identity_file=$(mktemp)
trap 'rm -f "$identity_file"' EXIT
echo "$P12" | base64 --decode > "$identity_file"
security import "$identity_file" -f pkcs12 -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign > /dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" > /dev/null
read -r -a existing <<< "$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
security list-keychains -d user -s "$keychain" "${existing[@]}"
echo "$keychain"
