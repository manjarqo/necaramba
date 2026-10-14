#!/bin/bash
set -euo pipefail
root="${SRCROOT}/../.."
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
helper="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/LoginItems/NecarambaLoginHelper.app"
mkdir -p "$resources" "$helper/Contents/MacOS" "${DERIVED_FILE_DIR}/necaramba-helper"
validator="${DERIVED_FILE_DIR}/necaramba-validate-production-rules"
if [[ "${NECARAMBA_DEVELOPMENT_RULES:-NO}" == NO ]]; then
  xcrun swiftc -swift-version 5 \
    "$root/Sources/NecarambaCore/Types/InputTypes.swift" \
    "$root/Sources/NecarambaCore/Types/RuleTypes.swift" \
    "$root/Sources/NecarambaCore/Delivery/RuleManifest.swift" \
    "$root/Sources/NecarambaCore/Delivery/RulePackageVerifier.swift" \
    "$root/Tools/Release/ValidateProductionRulePackage.swift" \
    -o "$validator"
fi
"$root/Tools/Packaging/stage-rule-resources.sh" "$root" "$resources" \
  "${NECARAMBA_DEVELOPMENT_RULES:-NO}" "${FLUTTER_BUILD_NAME:-}" "$validator"
cp "$root/Resources/Sounds/correction.wav" "$resources/correction.wav"
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
