#!/bin/bash
# Tests the root helper's input checks and file handling. No root needed: run as
# a normal user, the helper only operates inside a scratch folder and cannot
# touch tunnels, DNS or /etc.
#
#   ./Tests/helper-tests.sh

set -uo pipefail
cd "$(dirname "$0")/.."

[ "$(id -u)" -ne 0 ] || { echo "Run this as a normal user, not root." >&2; exit 1; }

HELPER=./helper/stayvpn-helper
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export STAYVPN_TEST_DIR="$WORK/conf"
failures=0

# check <expected exit code> <description> <command...>
check() {
    local want=$1 label=$2 out got
    shift 2
    out=$("$@" 2>&1); got=$?
    if [ "$got" = "$want" ]; then
        echo "ok    $label"
    else
        echo "FAIL  $label (exit $got, wanted $want): $out"
        failures=$((failures + 1))
    fi
}

mode_of()      { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
stored_mode()  { [ "$(mode_of "$STAYVPN_TEST_DIR/sv-proton-nl.conf")" = 600 ]; }
no_cr()        { ! grep -q $'\r' "$STAYVPN_TEST_DIR/sv-proton-nl.conf"; }
lists_exactly(){ [ "$("$HELPER" list)" = "$1" ]; }
list_empty()   { [ -z "$("$HELPER" list)" ]; }
versions_match() {
    local helper swift
    helper=$(sed -n 's/^VERSION=\([0-9][0-9]*\)$/\1/p' helper/stayvpn-helper)
    swift=$(sed -n 's/.*expectedVersion = \([0-9][0-9]*\).*/\1/p' Sources/StayVPNCore/HelperClient.swift)
    [ -n "$helper" ] && [ "$helper" = "$swift" ] && [ "$("$HELPER" version)" = "$helper" ]
}

good="$WORK/good.conf"
printf '[Interface]\r\nPrivateKey = aaa=\r\nAddress = 10.0.0.2/32\r\n\r\n[Peer]\r\nPublicKey = bbb=\r\nEndpoint = 203.0.113.7:51820\r\nAllowedIPs = 0.0.0.0/0\r\n' > "$good"

# Valid import
check 0 "imports a good config with Windows line endings" "$HELPER" import proton-nl "$good"
check 0 "stores it readable by its owner only (mode 600)" stored_mode
check 0 "strips carriage returns" no_cr
check 0 "lists the profile" lists_exactly proton-nl

# Lines that would run commands as root
for key in PostUp PreUp PostDown PreDown SaveConfig "  postUP"; do
    sed "s|^Address.*|$key = touch /tmp/pwned|" "$good" > "$WORK/hook.conf"
    check 2 "refuses a '$key' line" "$HELPER" import hooktest "$WORK/hook.conf"
done

# Profile names
for name in '../evil' 'Bad' 'a b' 'abcdefghijklm' '-a' 'a-' '' 'a/b' 'a.conf'; do
    check 2 "refuses profile name '$name'" "$HELPER" import "$name" "$good"
done

# Files that are not usable configs
echo hello > "$WORK/junk.conf"
: > "$WORK/empty.conf"
head -c 70000 /dev/zero | tr '\0' 'a' > "$WORK/huge.conf"
grep -v '^Endpoint' "$good" > "$WORK/no-endpoint.conf"
grep -v '^PrivateKey' "$good" > "$WORK/no-key.conf"
ln -s "$good" "$WORK/link.conf"
check 2 "refuses a file that is not a config" "$HELPER" import junk "$WORK/junk.conf"
check 2 "refuses an empty file" "$HELPER" import empty "$WORK/empty.conf"
check 2 "refuses an oversized file" "$HELPER" import huge "$WORK/huge.conf"
check 2 "refuses a config with no Endpoint" "$HELPER" import noend "$WORK/no-endpoint.conf"
check 2 "refuses a config with no PrivateKey" "$HELPER" import nokey "$WORK/no-key.conf"
check 2 "refuses a symlink" "$HELPER" import link "$WORK/link.conf"
check 2 "refuses a missing file" "$HELPER" import missing "$WORK/does-not-exist.conf"
check 0 "none of the refused imports left a profile behind" lists_exactly proton-nl

# Everything else
check 2 "cannot change tunnels in test mode" "$HELPER" up proton-nl
check 2 "remove of an unknown profile fails" "$HELPER" remove nope
check 0 "removes a profile" "$HELPER" remove proton-nl
check 0 "no profiles left" list_empty
check 2 "rejects an unknown command" "$HELPER" bogus
check 2 "rejects no command" "$HELPER"
check 1 "refuses to run as a normal user outside test mode" env -u STAYVPN_TEST_DIR "$HELPER" list
check 0 "helper version matches the app's expected version" versions_match

echo
if [ "$failures" -eq 0 ]; then echo "All helper tests passed."; else echo "$failures helper test(s) failed."; exit 1; fi
