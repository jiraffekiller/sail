#!/bin/sh
# Install the privileged helper. Run as root:
#   sudo sh scripts/install-helper.sh <helper.plist> <SailHelper binary>
# launchd starts the helper on demand when the app connects to its Mach service.
set -eu
LABEL="com.jiraffekiller.sail.helper"
PLIST_SRC="${1:?path to ${LABEL}.plist}"
BIN_SRC="${2:?path to SailHelper binary}"
BIN_DST="/Library/PrivilegedHelperTools/${LABEL}"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }

mkdir -p /Library/PrivilegedHelperTools
launchctl bootout "system/${LABEL}" 2>/dev/null || true
install -o root -g wheel -m 755 "$BIN_SRC" "$BIN_DST"
install -o root -g wheel -m 644 "$PLIST_SRC" "$PLIST_DST"
launchctl bootstrap system "$PLIST_DST"
echo "installed ${LABEL}"
