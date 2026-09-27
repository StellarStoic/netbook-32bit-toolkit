#!/usr/bin/env bash
# Hermes Agent on a 32-bit x86 machine — preflight check (READ ONLY).
# Runs no installs and changes nothing. Paste the output back to Hermes/T480.
set -u
say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

say "Hermes i686 preflight — $(date)"
hr

say "[cpu / kernel]"
say "  machine      : $(uname -m)"
say "  long bit     : $(getconf LONG_BIT 2>/dev/null || echo '?')"
say "  kernel       : $(uname -r)"
say "  distro       : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo unknown)"
say "  glibc        : $(ldd --version 2>/dev/null | head -1 || echo '?')"
hr

say "[python]"
PY=""
for c in python3.13 python3 python3.12 python3.11; do
    command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }
done
if [ -z "$PY" ]; then
    say "  no python3 found on PATH"
else
    say "  interpreter  : $PY -> $(command -v "$PY")"
    "$PY" - <<'EOF'
import platform, struct, sys, sysconfig, os
print(f"  version      : {platform.python_version()}  ({sys.version_info.major}.{sys.version_info.minor})")
print(f"  bits         : {struct.calcsize('P') * 8}-bit")
ok = lambda v: "YES" if (3, 11) <= v < (3, 14) else "NO — Hermes needs >=3.11,<3.14"
print(f"  version gate : {ok(sys.version_info[:2])}")
inc = sysconfig.get_paths().get("include")
print(f"  headers      : {inc} {'(present)' if inc and os.path.isdir(inc) else '(MISSING — C extensions cannot build)'}")
try:
    import ssl, hashlib
    print(f"  ssl          : OK ({ssl.OPENSSL_VERSION})")
except Exception as e:
    print(f"  ssl          : BROKEN ({e}) — TLS deps and 'uv' will fail")
try:
    import venv
    print("  venv module  : present")
except Exception as e:
    print(f"  venv module  : MISSING ({e})")
EOF
fi
hr

say "[resources]"
free -m 2>/dev/null | awk '/Mem:/{printf "  RAM          : %s MiB total, %s MiB free\n",$2,$4}'
say "  swap         : $(free -m 2>/dev/null | awk '/Swap:/{print $2" MiB"}')"
df -h "$HOME" /usr 2>/dev/null | awk 'NR==1{next}{printf "  disk %-7s: %s free of %s on %s\n",$6,$4,$2,$6}'
hr

say "[toolchain]"
for t in gcc cc make pkg-config perl cargo rustc rustup git curl wget; do
    if command -v "$t" >/dev/null 2>&1; then say "  $t: $(command -v "$t")"; else say "  $t: MISSING"; fi
done
for h in /usr/include/zlib.h /usr/include/jpeglib.h /usr/include/openssl/ssl.h /usr/include/x86_64-linux-gnu; do
    [ -e "$h" ] && say "  header present: $h"
done
hr

say "[network: pypi + github reachable?]"
for url in https://pypi.org/simple/ https://files.pythonhosted.org/ https://github.com/ https://astral.sh/; do
    code=$(curl -s -o /dev/null -m 12 -w '%{http_code}' "$url" 2>/dev/null || echo FAIL)
    say "  $code  $url"
done
hr

cat <<'EOF'
[what Hermes needs on i686 — measured from the project's uv.lock, Sep 2026]

  Not available for linux-i686, so these must be worked around:
    * the bundled installer (pins uv for x64/arm64 only) -> install uv by hand
    * uv's managed Python (python-build-standalone ships i686 only for Windows)
      -> must use the system python3.11-3.13 above
    * Node.js (no 32-bit Linux build since 2018) -> no Ink TUI, no desktop app,
      no Playwright/Chromium browser toolset

  Core deps with no i686 wheel -> local compile required (6):
    cryptography 50.0.0        RUST (pulled by pyjwt[crypto]; only needed for
                               secrets/Bitwarden + some plugin crypto)
    firecrawl-anydoc 0.2.4     RUST (read_file .docx/.pdf extraction; self-heals
                               away — read_file degrades without it)
    pyyaml 6.0.3               C    (buildable, libyaml optional)
    pillow 12.3.0              C    (needs zlib1g-dev, libjpeg-dev)
    psutil 7.2.2               C    (buildable)
    markupsafe 3.0.3           C    (buildable)

  Also gated by the lockfile itself: nemo-relay (the NeMo Relay runtime, Rust)
  is declared ONLY for platform_machine aarch64/x86_64 on Linux, arm64 on macOS,
  AMD64/ARM64 on Windows — 32-bit x86 is not in the supported platform set.

  Optional extras (voice, messaging, matrix, ...) add 31 more source builds
  (numpy, scipy, onnxruntime, av, aiohttp, ...) — skip the extras, skip those.
EOF
hr
say "Done. Send this output back and the exact install steps follow from it."
