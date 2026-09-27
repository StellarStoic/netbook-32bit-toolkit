# hermes-i686 — can this 32-bit box run Hermes natively?

Answer: **no**, and these two scripts show why in machine-readable form rather than by assertion.
Kept here because "can this old netbook be an AI-driven machine?" is the natural follow-up to
"can it run LocalSend?" — and the honest answer is to put the agent on a 64-bit box and drive the
32-bit one over SSH (`terminal.backend: ssh`, documented in the Hermes docs under
*Tools → Terminal Backends → SSH Backend*).

## What blocks a native install (measured, September 2026)

| blocker | evidence |
|---|---|
| the official installer refuses i686 | `install.sh` pins uv for `x86_64/amd64` → x64 and `arm64/aarch64` → arm64 only, then `fail "no pinned uv build for this platform (Linux i686)"` |
| uv cannot supply a 32-bit Linux Python | `python-build-standalone` ships i686 assets **only** for Windows (`i686-pc-windows-msvc`); uv's managed Pythons therefore have no linux-i686 |
| core dependencies have no i686 wheels | from `uv.lock`: `cryptography`, `firecrawl-anydoc`, `pyyaml`, `pillow`, `psutil`, `markupsafe` all need a source build (the first two are Rust/maturin) |
| the project's own lockfile excludes 32-bit x86 | `nemo-relay` (core Rust runtime) is declared only for `platform_machine` aarch64/x86_64 (Linux), arm64 (macOS), AMD64/ARM64 (Windows) |
| no Node.js for the TUI/desktop | last 32-bit Linux Node build is **v9.11.2 (2018-06-12)**; `nodejs.org/dist/index.json` has no `linux-x86` after that |
| no browser tooling | Playwright/Chromium has no i686 Linux target |

`uv` itself *does* publish `uv-i686-unknown-linux-gnu`, and the interpreter gate
(`requires-python >=3.11,<3.14`) is satisfiable on a modern 32-bit Kali (`python3.13` exists, even
though `python3` is now 3.14) — so the blockers are the wheel/build ones plus Node, not Python.

## preflight.sh

Read-only. Run it **on the 32-bit machine**:

```bash
bash preflight.sh
```

Reports: real pointer width, Python version + version-gate verdict, headers present, ssl/venv
modules working, glibc, RAM/swap/disk, compilers (`gcc`, `cargo`, `rustc`), dev headers, and
PyPI/GitHub reachability — plus the compiled-in list of what would need building.

## lockfile_i686_report.py

Run it wherever you have a checkout of the project (it reads the project's own `uv.lock`, so it
stays honest after every update):

```bash
python3 lockfile_i686_report.py [path/to/uv.lock]
```

It classifies every locked package as *i686 wheel* / *pure python* / *needs source build*, then
splits the source-build set into "core install closure" (what a bare install pulls) and "optional
extras only" (voice, messaging, matrix, … — skip the extra, skip the build). That distinction is
the whole answer: the core set is small and mostly survivable, the extras are not.

## If you insist on trying anyway

Feasible-ish path: hand-install `uv-i686-unknown-linux-gnu`, use the distro's `python3.13`
(`uv venv --python /usr/bin/python3.13`), install the wheel-available core deps, and only then
attempt the two Rust builds with `rustup` (i686 is a supported Rust host) plus a swap file.
Expect hours of compiling on an Atom N2xx, a real chance of OOM while linking, and a CLI-only
result: no TUI, no desktop app, no browser toolset. The upstream project does not test or support
any of it.

The supported alternative is a thousand times cheaper: run Hermes on any 64-bit machine, point
`terminal.backend: ssh` at the netbook (a dedicated profile, not your default one), and the
agent's shell *is* the netbook's shell. That's how this repository's upgrade run was performed —
the agent drove the i386 machine over SSH while the netbook had no agent of its own.
