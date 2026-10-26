#!/usr/bin/env bash
# guest-put.sh LOCAL GUESTPATH: copy a file into the guest (initramfs or real root),
# checked by sha256. Each transfer listens on a fresh port: a one-shot server left
# from an interrupted transfer would otherwise hold a fixed one.
set -euo pipefail
. "$(dirname "$0")/env.sh"
D=$(dirname "$0")
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
PORT=$(( 5100 + RANDOM % 800 ))
STAGE=/data/local/tmp/ohm.put.$PORT
# busybox here has no timeout applet; the real root has coreutils' timeout.
B='B=busybox; [ -x /usr/local/lib/omarchy/busybox ] && B=/usr/local/lib/omarchy/busybox; T=; command -v timeout >/dev/null && T="timeout 900"'
want=$(sha "$1")

"$D/guest.sh" "$B; (\$T \$B tcpsvd -E -c 1 0 $PORT sh -c 'cat > $2.part && mv $2.part $2' >/dev/null 2>&1 &); sleep 0.5" 20 >/dev/null
"$HDC" -t "$HDC_TARGET" file send "$1" "$STAGE" >/dev/null
hs "netcat -w 5 -q 3 172.16.100.2 $PORT < $STAGE; rm -f $STAGE" >/dev/null
sleep 1
got=$("$D/guest.sh" "kill \$(ps | grep 'tcpsvd -E -c 1 0 $PORT' | grep -v grep | awk '{print \$1}') 2>/dev/null; sha256sum $2 | cut -d' ' -f1" 20 | tr -d '\r' | tail -1)
if [ "$got" != "$want" ]; then
    echo "guest-put: checksum mismatch for $2 (local $want, guest ${got:-none})" >&2
    exit 1
fi
echo "$want  $2"
