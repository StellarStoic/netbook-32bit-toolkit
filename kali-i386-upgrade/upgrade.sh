#!/bin/bash
# upgrade.sh — runs ON the target machine, as root, detached from any SSH session.
#
# Takes a stranded i386 Debian/Kali install through a rolling upgrade, surviving:
#   * file-overwrite conflicts (Kali's missing Replaces: metadata)  -> purge stale holder
#   * flaky/half-synced mirrors                                     -> retries per round
#   * half-configured states left by an aborted apt                 -> configure/repair first
#
# Usage (as root, ideally detached — see run-upgrade.sh):
#   SNAP=/root/upgrade-snapshot bash upgrade.sh
#
# Logs every round to $SNAP/upgrade-<timestamp>.log and writes $SNAP/UPGRADE_DONE
# containing "rc=<exit-code> log=<filename>" when finished. Watch for that marker;
# rc=0 is success, anything else means a round ended with an error to read.
set -u

SNAP="${SNAP:-$HOME/upgrade-snapshot}"
mkdir -p "$SNAP"
LOG="$SNAP/upgrade-$(date +%Y%m%d-%H%M%S).log"
MARK="$SNAP/UPGRADE_DONE"
rm -f "$MARK"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l          # never prompt about service restarts
export APT_LISTCHANGES_FRONTEND=none
OPTS=(-y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
      -o Dpkg::Use-Pty=0 -o Acquire::Retries=3)
MAX_ROUNDS="${MAX_ROUNDS:-12}"

log() { echo "$*" >> "$LOG"; }

# Genuine reverse-dependents of $1 (Depends/Pre-Depends only).
# Bare `apt-cache rdepends` output is unsafe here: it includes Suggests-style
# reverse deps AND its own "Reverse Depends:" header, both of which look like
# dependents and will make you refuse to clear a conflict you must clear.
dependents() {
    apt-cache rdepends --installed "$1" 2>/dev/null \
      | grep -vE "^$1$|^Reverse Depends:|^ *\|" | tr -d ' ' | grep -v '^$' \
      | while read -r R; do
            if apt-cache depends "$R" 2>/dev/null | grep -E 'Depends:' | grep -qE "(^|[ :|])$1([ :,(]|$)"; then
                echo "$R"
            fi
        done
}

log "=== upgrade started $(date)"
log "--- before: iU=$(dpkg -l | awk '$1=="iU"' | wc -l)  upgradable=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)"

# 0. index refresh (retry: a redirector may hand you a half-synced mirror)
for i in 1 2 3; do
    apt-get update >> "$LOG" 2>&1 && break
    log "--- apt-get update attempt $i failed; retrying in 30s"
    sleep 30
done
log "--- apt-get update done ($(date))"

PREV_IU=-1; PREV_UP=-1; RC=999
for ROUND in $(seq 1 "$MAX_ROUNDS"); do
    log ""
    log "########## ROUND $ROUND  $(date)"

    # finish anything left half-configured by a previous abort
    dpkg --configure -a >> "$LOG" 2>&1
    log "--- dpkg --configure -a exit=$?"
    apt-get "${OPTS[@]}" -f install >> "$LOG" 2>&1
    log "--- apt-get -f install exit=$?"

    apt-get "${OPTS[@]}" full-upgrade >> "$LOG" 2>&1
    RC=$?
    IU=$(dpkg -l | awk '$1=="iU"' | wc -l)
    UP=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
    log "--- full-upgrade exit=$RC  (iU=$IU, upgradable=$UP)"
    [ "$RC" -eq 0 ] && break

    # file-overwrite conflicts: purge the stale holder when nothing real needs it
    CONFLICTS=$(grep -oE "trying to overwrite '[^']+', which is also in package [^ ]+" "$LOG" \
                | awk '{print $NF}' | sort -u)
    CLEARED=0
    for PKG in $CONFLICTS; do
        PKG=${PKG%%:*}
        dpkg -l "$PKG" 2>/dev/null | grep -q '^ii' || continue
        DEPS=$(dependents "$PKG")
        if [ -n "$DEPS" ]; then
            log "--- NOT purging $PKG (real dependents: $(echo "$DEPS" | tr '\n' ' '))"
            continue
        fi
        log "--- purging stale conflicting package: $PKG"
        dpkg --purge --force-depends "$PKG" >> "$LOG" 2>&1
        log "--- purge $PKG exit=$?"
        CLEARED=1
    done

    if [ "$CLEARED" -eq 0 ] && [ "$IU" -eq "$PREV_IU" ] && [ "$UP" -eq "$PREV_UP" ]; then
        log "--- no progress and no clearable conflict; stopping for manual review"
        break
    fi
    PREV_IU=$IU; PREV_UP=$UP
    sleep 10
done

# final repair passes
dpkg --configure -a >> "$LOG" 2>&1
log "--- final dpkg --configure -a exit=$?"
apt-get "${OPTS[@]}" -f install >> "$LOG" 2>&1
log "--- final apt-get -f install exit=$?"

{
    echo "=== FINISHED $(date)  last full-upgrade rc=$RC"
    for p in libc6 systemd dpkg apt openssh-server bash; do
        echo "$p $(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)"
    done
    echo "kernel: $(uname -r)   (i386 has no kernel candidate — this will not change)"
    echo "iU left: $(dpkg -l | awk '$1=="iU"' | wc -l)"
    echo "still upgradable: $(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)"
    echo "reboot required: $([ -f /var/run/reboot-required ] && echo YES || echo no)"
} >> "$LOG" 2>&1

printf 'rc=%s log=%s\n' "$RC" "$(basename "$LOG")" > "$MARK"
exit 0
