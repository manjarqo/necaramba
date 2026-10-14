#!/bin/bash
set -euo pipefail
[[ $# == 5 ]] || { echo 'Usage: stage-rule-resources.sh root resources YES|NO app-version validator' >&2; exit 1; }
root="$1"
resources="$2"
mode="$3"
app_version="$4"
validator="$5"
rules="$resources/Rules"
[[ ! -L "$rules" ]] || { echo 'Rules destination cannot be a symlink' >&2; exit 1; }
mkdir -p "$rules"

case "$mode" in
  YES)
    source="$root/App/macos/Runner/Release/BundledRules/Development"
    [[ -f "$source/DevelopmentOnly.json" && -f "$source/manifest.json" && -f "$source/signature.ed25519" && -f "$source/DevelopmentTrustedRuleKeys.json" && -f "$root/Resources/Rules/independent-v1.json" ]] || {
      echo 'Development package is incomplete' >&2; exit 1;
    }
    rm -rf "$rules/Development" "$rules/Production" "$rules/Licenses"
    mkdir -p "$rules/Development" "$rules/Licenses"
    cp "$source/"*.json "$source/signature.ed25519" "$rules/Development/"
    cp "$root/Resources/Rules/independent-v1.json" "$rules/Development/payload.json"
    cp "$root/Resources/Rules/Licenses/"*.txt "$rules/Licenses/"
    ;;
  NO)
    source="${NECARAMBA_PRODUCTION_RULES_DIR:-}"
    [[ "$source" == /* && -n "${NECARAMBA_TEAM_ID:-}" && -n "${NECARAMBA_BUNDLE_ID:-}" && "${PRODUCT_BUNDLE_IDENTIFIER:-}" == "$NECARAMBA_BUNDLE_ID" ]] || {
      echo 'Owner production inputs are required' >&2; exit 1;
    }
    [[ ! -L "$source" ]] || { echo 'Production source cannot be a symlink' >&2; exit 1; }
    source="$(cd "$source" && pwd -P)"
    resolved_rules="$(cd "$rules" && pwd -P)"
    [[ "$source" != "$resolved_rules" && "$source" != "$resolved_rules/"* ]] || { echo 'Production source must be outside bundle resources' >&2; exit 1; }
    "$validator" "$source" "$app_version" "$root/App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json"
    rm -rf "$rules/Development" "$rules/Production" "$rules/Licenses"
    mkdir -p "$rules/Production"
    cp "$source/manifest.json" "$source/signature.ed25519" "$source/payload.json" "$source/TrustedRuleKeys.json" "$rules/Production/"
    cp -R "$source/Licenses" "$rules/Production/Licenses"
    ;;
  *) echo 'Unknown rule package mode' >&2; exit 1 ;;
esac
