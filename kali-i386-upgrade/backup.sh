#!/bin/bash
# backup.sh — runs on the CONTROLLER. Captures everything you need to rebuild a small Linux
# machine before you touch its package manager: the user's home, /etc, dpkg/apt state, and a
# "before" snapshot of versions.
#
# Usage: TARGET=user@host [SSH_KEY=...] [SUDO_PASSWORD_FILE=...] [DEST=~/backups/myhost] bash backup.sh
#
# /etc needs root on the target; the archive is written through the SSH stream straight into
# the destination (no temp file on the target, no room needed there).
set -euo pipefail

: "${TARGET:?set TARGET=user@host}"
TUSER="${TARGET%%@*}"
DEST="${DEST:-$HOME/backups/${TUSER}-$(date +%Y%m%d)}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
SSH=(ssh "${SSH_OPTS[@]}" "$TARGET")
SCP=(scp "${SSH_OPTS[@]}")

mkdir -p "$DEST"/{home,meta}
echo "== destination: $DEST"

echo "== 1/4 home directory"
rsync -aH --human-readable --stats -e "ssh ${SSH_OPTS[*]}" "$TARGET:/home/$TUSER/" "$DEST/home/"

echo "== 2/4 package + system state"
"${SSH[@]}" 'dpkg --get-selections'                    > "$DEST/meta/dpkg-selections.txt"
"${SSH[@]}" 'apt-mark showmanual'                      > "$DEST/meta/apt-manual.txt"
"${SSH[@]}" 'apt list --upgradable 2>/dev/null'        > "$DEST/meta/apt-upgradable.txt"
"${SSH[@]}" 'ls /etc/apt/sources.list.d/ 2>/dev/null; cat /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null' \
                                                       > "$DEST/meta/sources.list.txt"
{
    echo "date: $(date)"; echo
    "${SSH[@]}" 'uname -a; uptime; free -m; df -h /; ls /boot'
    echo; echo "--- versions:"
    "${SSH[@]}" 'for p in libc6 systemd dpkg apt openssh-server bash python3; do printf "%-16s %s\n" "$p" "$(dpkg-query -W -f="${Version}" $p 2>/dev/null)"; done'
}                                                      > "$DEST/meta/before.txt"
wc -l "$DEST"/meta/*.txt | tail -1

echo "== 3/4 /etc + dpkg status + boot as one archive (needs sudo on the target)"
if [ -n "${SUDO_PASSWORD_FILE:-}" ]; then
    PW=$(head -1 "$SUDO_PASSWORD_FILE")
    printf '%s\n' "$PW" | "${SSH[@]}" \
        'sudo -S -p "" tar czf - /etc /var/lib/dpkg/status /boot 2>/dev/null' \
        > "$DEST/meta/etc-and-dpkg.tar.gz"
    unset PW
    gzip -t "$DEST/meta/etc-and-dpkg.tar.gz" && echo "   archive verifies ($(du -h "$DEST/meta/etc-and-dpkg.tar.gz" | cut -f1))"
else
    echo "   SKIPPED (no SUDO_PASSWORD_FILE). Run on the target:"
    echo "   sudo tar czf /tmp/etc.tgz /etc /var/lib/dpkg/status /boot   then copy it off"
fi

echo "== 4/4 summary"
du -sh "$DEST"/* | sed 's/^/   /'
echo "   home files: $(find "$DEST/home" -type f | wc -l)"
echo
echo "Restore notes:"
echo "  * config:   tar xzf meta/etc-and-dpkg.tar.gz -C /   (on a matching base install)"
echo "  * packages: dpkg --set-selections < meta/dpkg-selections.txt && apt-get dselect-upgrade"
echo "  * this is FILE-LOSS insurance, not a rollback: package versions are not pinned by it."
