#!/bin/bash
# watch.sh — runs on the CONTROLLER. Polls the target's status.sh, logs progress, and exits
# with a meaningful code so cron/notify integrations can act:
#   0 = upgrade finished, rc=0 (success)
#   3 = upgrade finished with a non-zero apt exit code (read the log)
#   2 = stalled: the log stopped growing for ~45 minutes
#   4 = target unreachable for ~1 hour
#
# Usage:  TARGET=kali@host [SSH_KEY=...] [SNAP=...] [INTERVAL=90] bash watch.sh
set -u

: "${TARGET:?set TARGET=user@host}"
SNAP="${SNAP:-/home/${TARGET%%@*}/upgrade-snapshot}"
INTERVAL="${INTERVAL:-90}"
POLLS="${POLLS:-500}"                     # 500 * 90s ≈ 12.5 h ceiling
PROG="${PROG:-$HOME/upgrade-progress.log}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")

log() { echo "$(date +%F' '%H:%M:%S) $*" >> "$PROG"; }
FAILS=0; STALL=0; PREV_SIZE=0

for _ in $(seq 1 "$POLLS"); do
    # || echo HELPER_MISSING: a helper that vanished (e.g. /tmp cleanup) must not be
    # confused with an unreachable host — that mistake cost 24 minutes of "no contact".
    OUT=$(ssh "${SSH_OPTS[@]}" "$TARGET" "bash '$SNAP/tools/status.sh' 2>/dev/null || echo HELPER_MISSING" 2>/dev/null)
    LINE=$(printf '%s' "$OUT" | head -1)

    case "$LINE" in
        HELPER_MISSING)
            log "HELPER_MISSING on target — $SNAP/tools/status.sh gone; re-push it (tmp reapers do this)"
            break ;;
    esac

    if [ -z "$OUT" ]; then
        FAILS=$((FAILS + 1))
        log "[no contact #$FAILS — host off-network; a detached upgrade keeps running]"
        if [ "$FAILS" -ge 40 ]; then
            log "ABORT: unreachable ~1h. Check the console; logs are in $SNAP on the target."
            exit 4
        fi
    else
        FAILS=0
        log "$LINE"
        SIZE=$(printf '%s' "$LINE" | sed -n 's/.*size=\([0-9]*\) .*/\1/p')
        RCMARK=$(printf '%s' "$LINE" | grep -o 'marker="rc=[0-9]*')
        if [ -n "$RCMARK" ]; then
            log "===== UPGRADE FINISHED ($RCMARK) ====="
            ssh "${SSH_OPTS[@]}" "$TARGET" "tail -50 \$(ls -t $SNAP/upgrade-*.log | head -1)" >> "$PROG" 2>&1
            [ "$RCMARK" = 'marker="rc=0' ] && exit 0 || exit 3
        fi
        if [ -n "$SIZE" ] && [ "$SIZE" = "$PREV_SIZE" ]; then
            STALL=$((STALL + 1))
            if [ "$STALL" -ge 30 ]; then
                log "STALL: log unchanged ($SIZE bytes) for ~45 min. Usually a packaging conflict waiting on you."
                ssh "${SSH_OPTS[@]}" "$TARGET" "grep -E '^E: |^dpkg: error' \$(ls -t $SNAP/upgrade-*.log | head -1) | tail -15" >> "$PROG" 2>&1
                exit 2
            fi
        else
            STALL=0; PREV_SIZE=$SIZE
        fi
    fi
    sleep "$INTERVAL"
done
log "watcher hit its poll ceiling — check manually"
exit 5
