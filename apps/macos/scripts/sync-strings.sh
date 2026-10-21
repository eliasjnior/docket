#!/usr/bin/env bash
# Merges every string the app and the kit look up into App/Resources/Localizable.xcstrings (D-18).
# xcodebuild extracts them but does not update the catalog in the source tree; this does.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Docket.xcodeproj -scheme Docket -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- SWIFT_EMIT_LOC_STRINGS=YES build -quiet
args=()
while IFS= read -r file; do
  args+=(--stringsdata "$file")
done < <(find build/Build/Intermediates.noindex -name '*.stringsdata' ! -name 'ExtractedAppShortcutsMetadata.stringsdata')
xcrun xcstringstool sync App/Resources/Localizable.xcstrings "${args[@]}"
