# PITFALLS — what actually went wrong, and what will bite you

Every item here is from a real run on a real machine (Kali rolling i386, Atom N280, 2 GB RAM),
with the exact symptom you will see. Read this before running `kali-i386-upgrade/`.

---

## 1. `apt update` fails with "Missing key ... needed to verify signature"

```
Err:1 http://.../kali kali-rolling InRelease
  Sub-process /usr/bin/sqv returned an error code (1), error message is:
  Missing key 827C8569F2518CC677FECA1AED65462EC8D5E4C5, ...
Warning: The repository is not updated and the previous index files will be used
```

apt then resolves against its **stale cached index**, which is why the next command can fail with
404s for files that "should" exist. The fix is the current archive key, which is still shipped as
an `arch:all` package (so the i386 pruning below doesn't affect it):

```bash
cd /tmp
wget -q https://http.kali.org/kali/pool/main/k/kali-archive-keyring/kali-archive-keyring_2025.2_all.deb
sha256sum kali-archive-keyring_2025.2_all.deb   # 9250b08fa00602d44a9df7e31cbac97fcf0b47a0ed4c81eb3e73c19a1cbc8cf0
sudo dpkg -i kali-archive-keyring_2025.2_all.deb
sudo apt update
```

Verify the keyring really carries that fingerprint before trusting it:
`gpg --show-keys --with-colons /usr/share/keyrings/kali-archive-keyring.gpg | awk -F: '/^fpr/{print $10}'`

---

## 2. A full-upgrade aborts *entirely* on one bad archive: "Hash Sum mismatch"

```
E: Failed to fetch http://kali.download/kali/pool/main/l/llvm-toolchain-21/libclang1-21_21.1.8-10_i386.deb  Hash Sum mismatch
E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
```

With 3379 MB downloaded and ~700 packages unpacked, apt still threw the whole transaction away:
**apt will not unpack anything if a single archive fails verification.** Nothing was changed on
the system (0 upgraded / 0 configured), which is the only consolation.

Cause in our case: `http.kali.org` is a redirector that fans out across mirrors mid-sync, so the
index (mirror A) and the pool file (mirror B) disagreed. Proof and fix:

```bash
# which mirrors actually agree with the index hash?
for m in http://kali.download/kali http://kali.mirror.garr.it/kali http://mirror.karneval.cz/pub/linux/kali; do
  curl -sL -o /tmp/f.deb "$m/pool/main/l/llvm-toolchain-21/libclang1-21_21.1.8-10_i386.deb"
  printf '%-40s %s\n' "$(echo "$m" | cut -d/ -f3)" "$(sha256sum /tmp/f.deb | cut -c1-20)"
done
# then pin sources.list to one verified-good mirror and apt update
```

Watch out: a genuinely broken mirror serves an HTML error page, and `curl` without `-f` exits 0,
so you hash the error page. Two different packages yielding the *same* hash is the tell.

Also note `mirror1.sox.rs` was serving 404 error pages for files its index still advertised —
a redirector will happily hand you that mirror.

Retrying without pinning works often (the redirector picks a different mirror), which is why the
upgrade script loops — but pinning one good mirror is deterministic and faster.

---

## 3. Kali's `Replaces:` gaps — dpkg refuses to overwrite, and apt aborts again

Two of these appeared in one upgrade. Both look like this:

```
dpkg: error processing archive .../46-python3-pyspnego_0.10.2-4_all.deb (--unpack):
 trying to overwrite '/usr/bin/pyspnego-parse', which is also in package python3-spnego 0.1.5-0kali1
```

```
dpkg: error processing archive /var/cache/apt/archives/kali-wallpapers-2026_2026.1.0_all.deb (--unpack):
 trying to overwrite '/usr/share/backgrounds/kali/login.svg', which is also in package kali-wallpapers-2024 2024.1.1
```

A stale Kali-only package and its upstream replacement both claim the same file, and the new
package's metadata lacks the `Replaces:`/`Breaks:` that would authorise the takeover.

Fix — purge the **stale** package, but first check nothing genuinely depends on it:

```bash
# Depends/Pre-Depends only. DO NOT trust bare apt-cache rdepends output: it lists
# Suggests-style reverse-deps and apt-cache's own "Reverse Depends:" header line as if
# they were dependents (this bug stalled two repair rounds).
apt-cache rdepends --installed python3-spnego | grep -vE '^python3-spnego$|^Reverse Depends:|^ *\|' | tr -d ' '
dpkg --purge --force-depends python3-spnego      # force-depends: apt refuses "remove" while deps are unmet
apt-get -y -f install                            # let apt repair the graph afterwards
```

For the wallpapers case the "dependent" was `kali-themes-common`, whose actual dependency is
`Depends: kali-wallpapers-2026` — so removing the 2024 package was correct and the new one got
pulled in as the dependency. If you check only `rdepends` you will refuse to fix it.

`--force-overwrite` also "works" but leaves two packages claiming one file; prefer the purge.

---

## 4. Never run `apt autoremove` on these machines

After the upgrade apt offered to remove **356 packages**, including:

```
kali-linux-firmware  firmware-iwlwifi  firmware-realtek  firmware-atheros
firmware-brcm80211   firmware-libertas firmware-zd1211   firmware-ti-connectivity
firmware-sof-signed  bluez-firmware   ...
```

Those are your Wi-Fi and Bluetooth radio firmware. Removing them can leave a laptop with **no
wireless after the next boot** — the firmware is loaded from disk at device init, and the card
simply won't come up. Also in that list: `gcc-14-base`, `libgcc-14-dev`, `crackmapexec`,
`cython3`, `firmware-*`, and a pile of libraries some installed tool still links against.

If you want space back, prune selectively and read the plan first:

```bash
apt-get -s autoremove | grep -E '^Remv' | awk '{print $2}' | sort | head -50
```

---

## 5. `/tmp` helpers vanish mid-upgrade

A status helper left in `/tmp` on the target disappeared during the upgrade (the new
`systemd`'s tmpfiles handling is the prime suspect; not proven). If your watcher runs a script
from the target's `/tmp`, it will start reporting "host unreachable" about a machine that is
perfectly reachable. Put helper scripts under the target user's home (e.g.
`~/upgrade-snapshot/tools/`) and make the remote command fail loudly:

```bash
ssh "$T" 'bash ~/upgrade-snapshot/tools/status.sh || echo HELPER_MISSING'
```

---

## 6. `sudo -S` plus a heredoc silently eats your password

```bash
# BROKEN: the heredoc wins stdin, so sudo reads the script text as the password
printf '%s\n' "$PW" | ssh "$T" 'sudo -S -p "" bash -s' <<'EOF'
...script...
EOF
# → "Sorry, try again." x3 → "sudo: 3 incorrect password attempts"
```

`sudo -S` reads the password from stdin, and `bash -s` wants the script from stdin: they cannot
share it, and the heredoc silently overrides the pipe. Either pipe the password to a script that
already exists on the target (`sudo -S bash /path/script.sh`), or use `sudo -S bash -c '...'`.
This failure looks exactly like "the password changed", which sends you chasing PAM for no reason.

Related: right after an upgrade replaces `libpam`/`sudo`, sudo can reject a **correct** password
with `pam_unix(sudo:auth): authentication failure` while the PAM stack settles. Re-test before
believing the credential is wrong.

---

## 7. Half-upgraded is not the same as broken — but do not reboot into it blind

After the aborts, the machine had `libc6 2.43` + `systemd 261` installed alongside the old
`dpkg`/`apt`/`openssh`, with 480 packages unpacked-but-unconfigured (`iU` state). It stayed
usable, bootable and SSH-reachable the whole time. The invariants to check, always:

```bash
dpkg -l | awk '$1=="iU"' | wc -l            # unpacked, not configured — should reach 0
dpkg --audit                                # needs root
apt-get -s -f install | tail -1             # should say nothing to do
dpkg-query -W -f='${Status} ${Version}\n' libc6 systemd dpkg apt openssh-server
```

Repair order that worked: `dpkg --configure -a` → `apt-get -y -f install` → retry `full-upgrade`
→ repeat, clearing overwrite conflicts between rounds. Only reboot once `iU = 0`.

The one thing that *is* fatal in that state: a reboot in the middle of an unpack, or power loss.
Run the upgrade detached (`setsid nohup`) so an SSH/Wi-Fi drop can't kill apt, and keep the
machine on mains power.

---

## 8. 32-bit-specific realities you cannot engineer around

* **No i386 kernel, ever again.** Kali dropped i386 kernels/images in 2024.4 and Debian stopped
  building i386 kernel packages in October 2024. `linux-image-686` has no candidate: the kernel
  stays whatever it was (ours: 6.0.0-kali3-686-pae). A full-upgrade is userland-only.
* **A slice of your packages is frozen forever.** 473 of 2870 installed packages had no i386
  candidate at all (`clang-13/14`, `cmake-data`, `freerdp2-x11`, `imagemagick-6-common`,
  `curlftpfs`, …) — they will never update, upgrade or not.
* **Packages disappear from the pool without notice.** `openssh-server_1:10.0p1-5_i386.deb` was
  advertised by a cached index and already gone from the pool (superseded by `10.5p1-1`). Always
  `apt update` against a mirror you trust before concluding "the file is missing".
* **The t64 (64-bit `time_t`) transition is messiest exactly here.** On i386 the whole
  `libfoo` → `libfoot64` rename churn lands at once; expect a long unpack phase and several
  hundred removals (`129` in our run, mostly old sonames).
