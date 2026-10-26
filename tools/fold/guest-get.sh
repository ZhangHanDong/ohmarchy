#!/usr/bin/env bash
# guest-get.sh GUESTPATH LOCAL: copy a file out of the guest (initramfs or real
# root), checked by sha256. Each transfer listens on a fresh port (see
# guest-put.sh).
set -euo pipefail
. "$(dirname "$0")/env.sh"
D=$(dirname "$0")
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
PORT=$(( 5100 + RANDOM % 800 ))
STAGE=/data/local/tmp/ohm.get.$PORT
# busybox here has no timeout applet; the real root has coreutils' timeout.
B='B=busybox; [ -x /usr/local/lib/omarchy/busybox ] && B=/usr/local/lib/omarchy/busybox; T=; command -v timeout >/dev/null && T="timeout 900"'

want=$("$D/guest.sh" "$B; (\$T \$B tcpsvd -E -c 1 0 $PORT sh -c 'cat $1' >/dev/null 2>&1 &); sleep 0.5; sha256sum $1 | cut -d' ' -f1" 20 | tr -d '\r' | tail -1)
hs "netcat -w 5 -q 3 172.16.100.2 $PORT > $STAGE < /dev/null" >/dev/null
"$HDC" -t "$HDC_TARGET" file recv "$STAGE" "$2" >/dev/null
hs "rm -f $STAGE" >/dev/null
"$D/guest.sh" "kill \$(ps | grep 'tcpsvd -E -c 1 0 $PORT' | grep -v grep | awk '{print \$1}') 2>/dev/null; true" 10 >/dev/null
got=$(sha "$2")
if [ "$got" != "$want" ]; then
    echo "guest-get: checksum mismatch for $2 (guest ${want:-none}, local $got)" >&2
    exit 1
fi
echo "$got  $2"
