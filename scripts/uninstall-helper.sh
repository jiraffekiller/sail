#!/bin/sh
# Remove the privileged helper. Run as root: sudo sh scripts/uninstall-helper.sh
set -u
LABEL="com.jiraffekiller.sail.helper"
[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }
launchctl bootout "system/${LABEL}" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/${LABEL}.plist" "/Library/PrivilegedHelperTools/${LABEL}"
echo "removed ${LABEL}"
