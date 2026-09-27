#!/bin/bash
# dashboard.sh — runs ON the target, for a human sitting at the machine (or on an ssh session).
# READ-ONLY: it cannot disturb a running transaction. Ctrl-C to stop.
#
#   bash dashboard.sh              # refreshing dashboard every 5s
#   bash dashboard.sh --follow     # plain live log stream
#   bash dashboard.sh 2            # refresh every 2s
SNAP="${SNAP:-$HOME/upgrade-snapshot}"
L=$(ls -t "$SNAP"/upgrade-*.log 2>/dev/null | head -1)

if [ "${1:-}" = "--follow" ]; then
    [ -z "$L" ] && { echo "no upgrade log in $SNAP"; exit 1; }
    echo "following $L — Ctrl-C to stop"
    tail -f "$L"
    exit 0
fi

INTERVAL="${1:-5}"
while true; do
    L=$(ls -t "$SNAP"/upgrade-*.log 2>/dev/null | head -1)
    [ -z "$L" ] && { echo "no upgrade log in $SNAP"; exit 1; }
    [ -t 1 ] && clear
    echo "upgrade dashboard — $(date '+%H:%M:%S')"
    printf 'log: %s (%s)  %s\n' "$(basename "$L")" "$(du -h "$L" | cut -f1)" \
        "$([ -f "$SNAP/UPGRADE_DONE" ] && echo "[FINISHED: $(cat "$SNAP/UPGRADE_DONE")]" || echo '[running]')"
    echo
    printf '  downloaded archives : %s\n' "$(grep -c '^Get:' "$L")"
    printf '  unpacked            : %s\n' "$(grep -c '^Unpacking' "$L")"
    printf '  configured          : %s\n' "$(grep -c '^Setting up' "$L")"
    printf '  removed             : %s\n' "$(grep -c '^Removing' "$L")"
    printf '  errors in log       : %s\n' "$(grep -ciE '^E: |^dpkg: error' "$L")"
    echo
    printf '  load %s | RAM avail %s MB | swap %s MB | disk free %s\n' \
        "$(cut -d' ' -f1-3 /proc/loadavg)" "$(free -m | awk '/Mem:/{print $7}')" \
        "$(free -m | awk '/Swap:/{print $3}')" "$(df -h / | awk 'NR==2{print $4}')"
    printf '  active: %s\n' "$(pgrep -a 'apt-get|dpkg' 2>/dev/null | sed 's/.* //' | sort -u | tr '\n' ' ')"
    echo
    echo "--- last 8 log lines ---"
    tail -8 "$L" | cut -c1-115
    echo
    echo "(safe: reads files only. Do NOT run apt/dpkg yourself — the lock is held.)"
    [ -f "$SNAP/UPGRADE_DONE" ] && break
    sleep "$INTERVAL"
done
