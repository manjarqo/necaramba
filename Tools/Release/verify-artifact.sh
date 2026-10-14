#!/bin/bash
set -euo pipefail
app="${1:?Usage: verify-artifact.sh Final.app}"
[[ -d "$app/Contents" ]] || { echo 'Not an app bundle' >&2; exit 1; }
rules="$app/Contents/Resources/Rules"
if [[ -e "$rules/Development" || -e "$rules/DevelopmentOnly.json" ]]; then
  echo 'Development rule package cannot be released' >&2; exit 1
fi
for file in manifest.json signature.ed25519 payload.json TrustedRuleKeys.json; do
  [[ -f "$rules/Production/$file" ]] || { echo 'Production rule package is incomplete' >&2; exit 1; }
done
[[ -d "$rules/Production/Licenses" ]] || { echo 'Production licenses are missing' >&2; exit 1; }
count=0
while IFS= read -r -d '' binary; do
  file -b "$binary" | grep -q 'Mach-O' || continue
  count=$((count+1))
  archs="$(xcrun lipo -archs "$binary")"
  [[ " $archs " == *' arm64 '* && " $archs " == *' x86_64 '* ]] || { echo "Missing universal slices: $binary" >&2; exit 1; }
  for arch in arm64 x86_64; do
    xcrun vtool -arch "$arch" -show-build "$binary" | awk '/minos/{split($2,v,"."); found=1;if(v[1]>12 || (v[1]==12 && v[2]>0)) exit 1} END{if(!found)exit 1}' || { echo "Unsupported deployment target: $binary" >&2; exit 1; }
  done
  codesign --verify --strict "$binary"
done < <(find "$app" -type f -print0)
[[ "$count" -gt 0 ]] || exit 1
codesign --verify --deep --strict "$app"
info="$(codesign -dv --verbose=4 "$app" 2>&1)"
[[ "$info" == *'Authority=Developer ID Application:'* && "$info" == *'runtime'* ]] || { echo 'Developer ID hardened runtime signature required' >&2; exit 1; }
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
echo "Verified $count Mach-O files; clean quarantined host test remains separate."
