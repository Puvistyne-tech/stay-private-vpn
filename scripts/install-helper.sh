#!/bin/bash
# One-time setup for Stay Private. Run from the project folder:
#
#   sudo ./scripts/install-helper.sh              install or update
#   (the app's "Install helper" button runs the same script from inside "Stay Private.app")
#   sudo ./scripts/install-helper.sh --uninstall  remove the helper and its sudo rule
#   sudo ./scripts/install-helper.sh --uninstall --purge   also delete saved profiles
#
# It installs a root-owned helper and a sudo rule that lets your user run that
# one helper without a password. Nothing else gains root access.

set -euo pipefail

HELPER_DEST=/usr/local/libexec/stayvpn-helper
SUDOERS=/etc/sudoers.d/stayvpn
CONF_DIR=/etc/wireguard
HERE="$(cd "$(dirname "$0")" && pwd)"
# In the project the helper is in ../helper; inside the app bundle it sits next to this script.
SRC="$HERE/stayvpn-helper"
[ -f "$SRC" ] || SRC="$HERE/../helper/stayvpn-helper"

[ "$(id -u)" -eq 0 ] || { echo "Run this with sudo: sudo $0 $*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
    for conf in "$CONF_DIR"/sv-*.conf; do
        [ -f "$conf" ] && [ -x "$HELPER_DEST" ] || continue
        name=$(basename "$conf" .conf)
        "$HELPER_DEST" down "${name#sv-}" >/dev/null 2>&1 || true
    done
    rm -f "$HELPER_DEST" "$SUDOERS"
    if [ "${2:-}" = "--purge" ]; then
        rm -f "$CONF_DIR"/sv-*.conf
        echo "Removed the helper, its sudo rule and all saved profiles."
    else
        echo "Removed the helper and its sudo rule. Saved profiles remain in $CONF_DIR."
    fi
    exit 0
fi

# The app runs this through a macOS administrator prompt and passes the user explicitly.
USER_NAME="${SUDO_USER:-}"
if [ "${1:-}" = "--user" ]; then USER_NAME="${2:-}"; fi
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
    echo "Run this with sudo from your own account, not as root directly." >&2
    exit 1
fi
[[ "$USER_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Unexpected user name: $USER_NAME" >&2; exit 1; }
id "$USER_NAME" >/dev/null 2>&1 || { echo "No such user: $USER_NAME" >&2; exit 1; }
[ -f "$SRC" ] || { echo "Cannot find $SRC" >&2; exit 1; }

mkdir -p "$(dirname "$HELPER_DEST")" "$CONF_DIR"
chown root:wheel "$(dirname "$HELPER_DEST")"
chmod 755 "$(dirname "$HELPER_DEST")"
install -o root -g wheel -m 755 "$SRC" "$HELPER_DEST"
chown root:wheel "$CONF_DIR"
chmod 700 "$CONF_DIR"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
echo "$USER_NAME ALL=(root) NOPASSWD: $HELPER_DEST" > "$TMP"
visudo -cf "$TMP" >/dev/null || { echo "Generated sudo rule failed validation; nothing changed." >&2; exit 1; }
install -o root -g wheel -m 440 "$TMP" "$SUDOERS"

echo "Installed $HELPER_DEST"
echo "Allowed $USER_NAME to run it without a password ($SUDOERS)"
if ! PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v wg-quick >/dev/null 2>&1; then
    echo
    echo "WireGuard tools are not installed yet. Run:  brew install wireguard-tools"
fi
