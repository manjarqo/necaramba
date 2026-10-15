#!/bin/bash
set -euo pipefail
root="${SRCROOT}/../.."
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
helper="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/LoginItems/NecarambaLoginHelper.app"
mkdir -p "$resources" "$helper/Contents/MacOS" "${DERIVED_FILE_DIR}/necaramba-helper"
# This resource is explicitly local-only. Always clear stale output when an
# ordinary build reuses the same bundle directory.
local_model="$resources/LocalPatternModel.json"
rm -f "$local_model"
# Independent model is explicitly enabled while quality comparison is underway.
# Always remove stale open resources when reusing the same bundle output.
rm -rf "$resources/OpenModel"
if [[ "${NECARAMBA_OPEN_MODEL:-NO}" == YES ]]; then
  /usr/bin/python3 "$root/Tools/Packaging/stage-open-model.py" "$root/Resources/OpenModel" "$resources/OpenModel"
fi
if [[ -n "${NECARAMBA_LOCAL_PATTERN_MODEL:-}" ]]; then
  [[ "${NECARAMBA_DEVELOPMENT_RULES:-NO}" == YES ]] || {
    echo 'Local pattern model requires development rules YES' >&2; exit 1;
  }
  /usr/bin/env -u SDKROOT /usr/bin/python3 - "$NECARAMBA_LOCAL_PATTERN_MODEL" "$local_model" <<'PYMODEL'
import os
import stat
import sys
import tempfile

source, destination = sys.argv[1:]
limit = 64 * 1024 * 1024
try:
    descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= limit:
            raise ValueError("Expected a regular model file no larger than 64 MiB")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError("Model grew beyond 64 MiB")
    staged = None
    try:
        with tempfile.NamedTemporaryFile(dir=os.path.dirname(destination), prefix=".local-model-", delete=False) as output:
            staged = output.name
            output.write(data)
        os.replace(staged, destination)
    finally:
        if staged is not None and os.path.exists(staged):
            os.unlink(staged)
except (OSError, ValueError) as error:
    sys.exit("Cannot stage local pattern model: " + str(error))
PYMODEL
fi
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
