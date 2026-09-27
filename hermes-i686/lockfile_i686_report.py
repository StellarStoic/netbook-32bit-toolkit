#!/usr/bin/env python3
"""Report which Hermes dependencies a 32-bit x86 (i686) Linux host can install
from wheels, and which would have to be compiled from source there.

Usage: python3 lockfile_i686_report.py [uv.lock]
Default lockfile: ~/.hermes/hermes-agent/uv.lock

Classification per locked package:
  i686 wheel      - a 32-bit x86 Linux wheel exists  -> no build
  pure python     - *-none-any.whl                   -> no build
  SOURCE BUILD    - no usable wheel for linux i686   -> local compile
Then the report splits those into "core" (reachable from hermes-agent's
non-optional deps) and "optional extras only" (voice, messaging, matrix, ...).
"""
import re
import sys
import tomllib
from pathlib import Path

RUST_BUILD = {"cryptography", "firecrawl-anydoc", "jiter", "tokenizers",
              "hf-xet", "pydantic-core", "uvloop", "watchfiles"}

lock = Path(sys.argv[1] if len(sys.argv) > 1 else
            Path.home() / ".hermes/hermes-agent/uv.lock")
data = tomllib.loads(lock.read_text())
pkgs = {}
for p in data.get("package", []):
    pkgs[p["name"]] = p

def verdict(p):
    urls = [w.get("url", "") for w in p.get("wheels", [])]
    if any(re.search(r"i686|i386", u) for u in urls):
        return "i686 wheel"
    if any(u.endswith("-none-any.whl") for u in urls):
        return "pure python"
    if "sdist" not in p and not urls:
        return "no files"
    return "SOURCE BUILD"

def closure(root="hermes-agent"):
    """Follow non-optional dependencies only (what a bare install pulls)."""
    seen, stack = set(), [root]
    while stack:
        name = stack.pop()
        if name in seen or name not in pkgs:
            continue
        seen.add(name)
        for dep in pkgs[name].get("dependencies", []):
            marker = dep.get("marker", "")
            if "extra ==" in marker:         # only in an optional extra
                continue
            if "win32" in marker or "darwin" in marker:   # not this platform
                continue
            stack.append(dep["name"])
    return seen

core = closure()
rows_build, rows_ok, extras_build = [], [], []
for name, p in sorted(pkgs.items()):
    if name == "hermes-agent":
        continue
    v = verdict(p)
    in_core = name in core
    if v == "SOURCE BUILD":
        (rows_build if in_core else extras_build).append((name, p.get("version", "?")))
    else:
        rows_ok.append((name, p.get("version", "?"), v))

def dump(title, rows, three=False):
    print(f"\n{title} ({len(rows)})")
    print("-" * 78)
    for r in rows:
        name, ver = r[0], r[1]
        tag = ""
        if three:
            tag = r[2]
        else:
            tag = "RUST (maturin/cargo)" if name in RUST_BUILD else "C/C++ extension"
        print(f"  {name:<28} {ver:<14} {tag}")

print(f"lockfile: {lock}  ({len(pkgs)} packages)")
print(f"core install closure: {len(core)} packages")
dump("CORE deps that must be COMPILED on i686", rows_build)
dump("Optional-extra deps that must be COMPILED on i686 (skip the extra, skip the build)", extras_build)
print(f"\nCore deps installable from wheels: {sum(1 for n,_,_ in rows_ok if n in core)}")
print(f"Total installable from wheels:     {len(rows_ok)}")
