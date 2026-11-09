#!/bin/bash
# Packs the Necaramba GNOME Shell extension and, with --install, installs it
# for the current user. Without --install only the zip is produced.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UUID=necaramba@local.necaramba.app
SRC="$HERE/$UUID"
OUT="${NECARAMBA_BUILD_DIR:-$HERE/build}"

mkdir -p "$OUT"
gnome-extensions pack --force --out-dir="$OUT" \
    --extra-source=domain --extra-source=application \
    --extra-source=data --extra-source=presentation \
    "$SRC"
ZIP="$OUT/$UUID.shell-extension.zip"
echo "packed: $ZIP"

if [ "${1:-}" = "--install" ]; then
    gnome-extensions install --force "$ZIP"
    if gnome-extensions enable "$UUID" 2>/dev/null; then
        echo "installed and enabled $UUID"
    else
        echo "installed $UUID."
        echo "GNOME on Wayland discovers new extensions after the next login:"
        echo "log out, log back in, then run: gnome-extensions enable $UUID"
    fi
fi
