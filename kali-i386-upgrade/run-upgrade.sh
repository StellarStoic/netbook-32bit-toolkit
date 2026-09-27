#!/bin/bash
# run-upgrade.sh — runs on the CONTROLLER machine. Pushes upgrade.sh + status.sh to the
# target and launches the upgrade as root, detached, so an SSH or Wi-Fi drop cannot kill apt.
#
# Required:
#   TARGET=user@host                 e.g. TARGET=kali@192.168.0.50
# Optional:
#   SSH_KEY=~/.ssh/id_ed25519_target      (key-based login, no password prompts)
#   SUDO_PASSWORD_FILE=~/.netbook-sudo    (single line: the target's sudo password)
#   SNAP=/home/<user>/upgrade-snapshot    (where logs and the DONE marker live on the target)
#
# Example:
#   TARGET=kali@192.168.0.50 SSH_KEY=~/.ssh/id_ed25519_target \
#   SUDO_PASSWORD_FILE=~/.netbook-sudo bash run-upgrade.sh
set -euo pipefail

: "${TARGET:?set TARGET=user@host}"
SNAP="${SNAP:-/home/${TARGET%%@*}/upgrade-snapshot}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
SSH=(ssh "${SSH_OPTS[@]}" "$TARGET")
SCP=(scp "${SSH_OPTS[@]}")

here=$(cd "$(dirname "$0")" && pwd)

echo "== pushing helpers to $TARGET:$SNAP/tools/"
"${SSH[@]}" "mkdir -p '$SNAP/tools'"
"${SCP[@]}" "$here/upgrade.sh" "$here/status.sh" "$TARGET:$SNAP/tools/"
"${SSH[@]}" "chmod +x '$SNAP/tools/'*.sh && bash -n '$SNAP/tools/upgrade.sh' && echo '  syntax OK'"

if [ -n "${SUDO_PASSWORD_FILE:-}" ]; then
    [ -r "$SUDO_PASSWORD_FILE" ] || { echo "cannot read $SUDO_PASSWORD_FILE" >&2; exit 1; }
    PW=$(head -1 "$SUDO_PASSWORD_FILE")
    echo "== launching detached upgrade (sudo password from $SUDO_PASSWORD_FILE)"
    # NB: the password goes in on stdin and `bash` gets the script from a FILE on the target.
    # Never combine a password pipe with `bash -s` + heredoc — the heredoc wins stdin and
    # sudo reads your script as the password (three "Sorry, try again." and no clue why).
    printf '%s\n' "$PW" | "${SSH[@]}" \
        "sudo -S -p '' setsid nohup env SNAP='$SNAP' bash '$SNAP/tools/upgrade.sh' > /dev/null 2>&1 & echo launched"
    unset PW
else
    echo "== no SUDO_PASSWORD_FILE set: run this yourself on the target:"
    echo "   sudo SNAP=$SNAP setsid nohup bash $SNAP/tools/upgrade.sh >/dev/null 2>&1 &"
fi

sleep 25
echo
echo "== first status =="
"${SSH[@]}" "bash '$SNAP/tools/status.sh'" || true
echo
echo "== follow it with:  TARGET=$TARGET SNAP=$SNAP bash $(dirname "$0")/watch.sh"
echo "== the machine may look dead for minutes at a time. That is normal: it is unpacking"
echo "   thousands of packages on a very small CPU. Do not reboot until UPGRADE_DONE appears."
