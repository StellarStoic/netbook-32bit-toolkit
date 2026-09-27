# 32-bit netbook toolkit (Kali i386)

Tooling built for one machine: a **Lenovo IdeaPad S10-2** — Intel Atom N280, 2 GB RAM, 32-bit
only — running Kali i386. It exists because keeping a 32-bit-only box usable in 2026 takes
deliberate work, and most of that work is reusable on any ageing i386 laptop.

## What's here

* **`kali-i386-upgrade/`** — automation that took this box through a ~2.5-year Debian
  bookworm → trixie upgrade including the 64-bit `time_t` (t64) transition: roughly 3,000 package
  operations, run **detached** from SSH so a NetworkManager restart cannot kill apt mid-transaction,
  with mirror-desync and stale-package recovery, plus `status`/`dashboard`/`watch` helpers for
  following a long run from another machine.
* **`hermes-i686/`** — a read-only preflight (`preflight.sh`) and a `uv.lock` analyser
  (`lockfile_i686_report.py`) answering "can this box run
  [Hermes Agent](https://hermes-agent.nousresearch.com/docs) natively?". Short answer: no, and the
  analyser names every dependency that says so, per package, with the i686 wheel availability.
* **`docs/PITFALLS.md`** — the distilled failure catalogue from the real upgrade run. The most
  useful file here if you own an ageing 32-bit machine.
* **`docs/WHAT-HAPPENED.md`** — the narrative version: what broke, in what order, and why.

## Requirements

* SSH access to the target machine, with sudo. The scripts read the password from a file you
  control rather than taking it as an argument — see `kali-i386-upgrade/README.md`.
* A 64-bit machine for anything that needs building. Do not compile on the target.

## Read this before pointing any of it at a real machine

`docs/PITFALLS.md` covers what actually went wrong on a real run: two Kali packaging bugs, a mirror
desync mid-upgrade, a helper script that vanished from `/tmp`, and an `apt autoremove` that would
have removed the Wi-Fi firmware. The upgrade scripts back up first and refuse to guess.

## The LocalSend piece lives in its own repo

The 32-bit LocalSend client built for this same machine — with the multicast/VPN/ufw debugging that
came out of it — is at **<https://github.com/StellarStoic/localsend-cli-i386>**.

## License

MIT for the scripts in this repository (see `LICENSE`). Upstream projects keep their own licenses;
nothing from them is vendored here.
