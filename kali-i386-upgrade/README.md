# kali-i386-upgrade

Automation for pushing a stranded 32-bit Debian/Kali install through a large rolling upgrade
without babysitting it — and without losing the machine if it goes wrong.

Built for a 2.5-year jump (Kali 2024.1 → current rolling on i386: 3053 package operations,
bookworm → trixie, plus the 64-bit `time_t` transition). See `../docs/PITFALLS.md` for the
failure modes this handles and `../docs/WHAT-HAPPENED.md` for the real run's numbers.

## Files

| file | runs on | purpose |
|---|---|---|
| `backup.sh` | controller | home dir + `/etc` + dpkg/apt state + before-snapshot. **Run this first.** |
| `run-upgrade.sh` | controller | pushes the scripts and launches the upgrade as root, detached |
| `upgrade.sh` | target (root) | the actual upgrade loop: configure → fix deps → full-upgrade, with conflict recovery |
| `status.sh` | target | one-line progress + tail (what the watcher polls) |
| `dashboard.sh` | target | live read-only dashboard for a human at the machine |
| `watch.sh` | controller | polls status, logs progress, exits 0/2/3/4 on success/stall/failure/unreachable |

## Usage

```bash
export TARGET=kali@192.168.0.50
export SSH_KEY=~/.ssh/id_ed25519_target
export SUDO_PASSWORD_FILE=~/.netbook-sudo        # chmod 600, one line
export SNAP=/home/kali/upgrade-snapshot

# 1. insurance (verify it before going further)
DEST=~/backups/netbook bash backup.sh

# 2. push + launch, detached on the target
bash run-upgrade.sh

# 3. follow it (or run dashboard.sh on the target itself)
bash watch.sh
```

Put the sudo password in a file, not in your shell history or an env var you `export` in front of
other people. The scripts read it from `SUDO_PASSWORD_FILE` and pipe it to `sudo -S` on stdin.

## Why the upgrade runs detached

`setsid nohup ... upgrade.sh` — because the machine *will* lose its network mid-run. In our run
`NetworkManager` and `wpasupplicant` were upgraded live, Wi-Fi dropped, and the desktop session
restarted twice. A foreground `apt` over SSH would have been killed mid-transaction at the worst
possible moment; a detached one just keeps unpacking and you reconnect later.

## What "success" looks like

`$SNAP/UPGRADE_DONE` appears, containing `rc=0 log=<file>`. Then:

```bash
dpkg -l | awk '$1=="iU"' | wc -l     # 0  (nothing unpacked-but-unconfigured)
apt-get -s -f install | tail -1      # nothing to do
systemctl --failed                   # 0 units
sudo reboot                          # required for the new glibc/systemd
```

Reboot **only** when `iU` reaches 0. A reboot or power loss in the middle of unpacking is the one
thing that can genuinely break the machine; everything else here is recoverable.

## Expectations, honestly

* Hours, not minutes, on this class of hardware (~5 h in our run, ~104 min of that unpacking).
* The target will look dead for long stretches (load ~6 on one core, 2 GB RAM). The dashboard's
  `unpacked` counter is the only trustworthy liveness signal.
* Expect the GUI on the target to die and come back (a black screen with a blinking cursor is
  normal and not a failure).
* Expect **no kernel upgrade**: Kali dropped i386 kernels in 2024.4. Userland moves; the kernel
  does not.
* Expect a few hundred removals (old sonames during the t64 transition) — review the plan with
  `apt-get -s full-upgrade` before committing if the machine matters to you.
