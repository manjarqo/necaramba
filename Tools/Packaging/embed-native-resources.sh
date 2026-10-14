#!/bin/bash
set -euo pipefail
root="${SRCROOT}/../.."
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
helper="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/LoginItems/NecarambaLoginHelper.app"
mkdir -p "$resources" "$helper/Contents/MacOS" "${DERIVED_FILE_DIR}/necaramba-helper"
cp "$root/Resources/Sounds/correction.wav" "$resources/correction.wav"
if [[ "${NECARAMBA_DEVELOPMENT_RULES:-NO}" == YES ]]; then
  mkdir -p "$resources/Rules/Development" "$resources/Rules/Licenses"
  cp "$root/App/macos/Runner/Release/BundledRules/Development/"*.json "$resources/Rules/Development/"
  cp "$root/App/macos/Runner/Release/BundledRules/Development/signature.ed25519" "$resources/Rules/Development/"
  cp "$root/Resources/Rules/independent-v1.json" "$resources/Rules/Development/payload.json"
  cp "$root/Resources/Rules/Licenses/"*.txt "$resources/Rules/Licenses/"
else
  echo 'Production rule package and approved production configuration required' >&2
  exit 1
fi
cp "$root/App/NecarambaLoginHelper/Info.plist" "$helper/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${PRODUCT_BUNDLE_IDENTIFIER}.LoginHelper" "$helper/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable NecarambaLoginHelper' "$helper/Contents/Info.plist"
for architecture in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "${architecture}-apple-macos12.0" -sdk "$SDKROOT" "$root/App/NecarambaLoginHelper/main.swift" -o "${DERIVED_FILE_DIR}/necaramba-helper/${architecture}"
done
xcrun lipo -create "${DERIVED_FILE_DIR}/necaramba-helper/arm64" "${DERIVED_FILE_DIR}/necaramba-helper/x86_64" -output "$helper/Contents/MacOS/NecarambaLoginHelper"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == YES ]]; then
  /usr/bin/codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$helper"
fi
