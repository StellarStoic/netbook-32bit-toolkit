# What this run actually looked like (reference numbers)

From a real upgrade: Lenovo IdeaPad S10-2, Intel Atom N280 (32-bit only), 2 GB RAM, 145 GB disk,
Kali GNU/Linux Rolling (installed as 2024.1, drifted ~2.5 years behind), kernel
`6.0.0-kali3-686-pae`, glibc 2.38, systemd 255.

## The upgrade in numbers

| | value |
|---|---|
| packages installed at start | 2870 |
| upgradable | 2397 |
| packages with **no i386 candidate** | 473 |
| operations in the committed plan | 2390 upgraded, 662 newly installed, 129 to remove |
| archives to download | 3382 MB / 3408 MB (11 min at ~5 MB/s) |
| wall-clock for the whole job | ~5 h (03:16 → 06:32 bulk phase, plus two repair rounds) |
| unconfigured (`iU`) peak | 480 |
| errors in the final successful log | 0 |
| reboot | clean, back online in ~105 s |

Before → after:

| package | before | after |
|---|---|---|
| libc6 | 2.38-13 | 2.43-4 |
| systemd | 255.3-2 | 261.2-1 |
| dpkg | 1.21.9+kali1 | 1.23.7+kali1 |
| apt | 3.0.3+kali1 | 3.3.3+kali1 |
| openssh-server | 1:9.6p1-3 | 1:10.4p1-5 |
| bash | 5.2.21-2 | 5.3-3+b1 |
| python3 | 3.13.3-1 | 3.14.7-3 |
| linux-image | 6.0.0-kali3-686-pae | **unchanged** (no i386 kernel exists) |

## Timeline (the shape to expect)

1. **Keyring repair** — `apt update` was failing on a missing archive key; installed
   `kali-archive-keyring_2025.2_all.deb`.
2. **First `full-upgrade`** — 11 minutes of downloading, then aborted with two
   `Hash Sum mismatch` fetches (mirror desync). Everything downloaded stayed in the cache;
   0 packages changed.
3. **Pin one mirror + retry** — got through the download and started unpacking.
4. **Abort #2** — `python3-pyspnego` vs `python3-spnego` file conflict aborted the transaction
   with 480 packages unpacked-not-configured. The machine stayed up and reachable.
5. **Repair round 1** — `dpkg --configure -a` cut 480 → 21, then stalled on the wallpaper
   conflict because the dependent-detection counted a `Suggests`.
6. **Repair round 2** — same conflict, same stall, now with the detection fixed: 21 → 3.
7. **Targeted unblock** — purged `kali-wallpapers-2024` with `dpkg --purge --force-depends`;
   `apt-get -f install` pulled `kali-wallpapers-2026` in as the dependency. **`iU` → 0.**
8. **Bulk phase** — 1724 remaining upgrades, ~104 min of unpacking, then the configure burst:
   `rc=0`, zero errors.
9. **Reboot** — required for the new glibc/systemd; clean.

## Things that turned out to be non-issues (worth knowing before panicking)

* **A "black screen with a blinking cursor" on the target.** This is the desktop stack being
  replaced live (lightdm/X/dbus/theme packages mid-unpack). The GUI comes back after the upgrade
  plus a reboot. It does not mean the upgrade died — check progress over SSH instead of staring
  at the console.
* **The panel dialog `plugin "CPU Graph" unexpectedly left the panel, do you want to restart it`**
  — the panel reloaded itself after the reboot and a plugin didn't re-attach. Answer *Restart*;
  `xfce4-panel -r` fixes it permanently.
* **Screen locker "missing" after the upgrade.** `light-locker` cannot be reinstalled because
  `kali-desktop-xfce` declares `Conflicts: light-locker` — the modern desktop uses
  `xfce4-screensaver` instead, which stays installed. Not an i386 casualty.
* **"No Wi-Fi applet for i386".** Wrong package name. Debian's is `network-manager-applet`
  (Ubuntu-era `network-manager-gnome` has no i386 build); it is a `Depends` of
  `kali-desktop-xfce` and it keeps working.
* **`Possible missing firmware ... i915/*` during configure** — firmware for modern Intel GPUs,
  irrelevant on Pineview-era hardware.
* **`PAM (systemd-user) /usr/lib/pam.d is not supported on this system`** — a cosmetic new-libpam
  notice on systemd `--user`; harmless.
* **`perl: warning: Falling back to a fallback locale` / `locale: Cannot set LC_ALL`** during
  maintainer scripts — harmless locale noise.

## Cleanup afterwards

A stale autostart entry survives the kali-themes upgrade and logs a warning at every login:

```bash
rm ~/.config/autostart/fix-duplicated-xfce-panel-launcher.desktop
# its Exec target /usr/share/kali-themes/fix-duplicated-xfce-panel-launcher.sh no longer exists
```

Two packages were still held back at the end (`isa-support`, `mitmproxy`) with no explicit
`apt-mark hold` — consistent with phased updates; they install on a later `apt update &&
apt full-upgrade`.
