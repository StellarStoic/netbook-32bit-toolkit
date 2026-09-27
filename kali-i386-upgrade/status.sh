#!/bin/bash
# status.sh — runs ON the target. One line + tail for the newest upgrade log.
SNAP="${SNAP:-$HOME/upgrade-snapshot}"
L=$(ls -t "$SNAP"/upgrade-*.log 2>/dev/null | head -1)
[ -z "$L" ] && { echo "no upgrade log in $SNAP"; exit 0; }
MARK=""
[ -f "$SNAP/UPGRADE_DONE" ] && MARK=$(cat "$SNAP/UPGRADE_DONE")
printf 'log=%s size=%s lines=%s fetched=%s unpacked=%s configured=%s removed=%s errors=%s marker="%s" load=%s availMB=%s swapMB=%s\n' \
  "$(basename "$L")" "$(stat -c %s "$L")" "$(wc -l < "$L")" \
  "$(grep -c '^Get:' "$L")" "$(grep -c '^Unpacking' "$L")" "$(grep -c '^Setting up' "$L")" \
  "$(grep -c '^Removing' "$L")" "$(grep -ciE '^E: |^dpkg: error' "$L")" \
  "$MARK" \
  "$(cut -d' ' -f1 /proc/loadavg)" \
  "$(free -m | awk '/Mem:/{print $7}')" \
  "$(free -m | awk '/Swap:/{print $3}')"
tail -2 "$L" | cut -c1-110 | sed 's/^/  | /'
