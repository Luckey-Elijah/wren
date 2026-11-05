#!/usr/bin/env python3
"""Check a packaged Wren executable with real SDKs in a disposable store."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("executable", type=Path)
parser.add_argument("--work-dir", type=Path)
args = parser.parse_args()
if (platform.system(), platform.machine()) != ("Darwin", "arm64"):
    parser.error("this smoke check requires Apple Silicon macOS")
executable = args.executable.resolve(strict=True)
root = args.work_dir or Path(tempfile.mkdtemp(prefix="wren-macos-smoke-"))
marker = root / ".wren-release-smoke"
if not marker.exists():
    if root.exists() and any(root.iterdir()):
        parser.error("work directory must be empty or belong to this smoke check")
    root.mkdir(parents=True, exist_ok=True)
    marker.touch()
root = root.resolve()
store = root / "store"
project = root / "project"
project.mkdir(exist_ok=True)
environment = {**os.environ, "WREN_DATA_DIR": str(store),
               "WREN_FLUTTER_RELEASE": "", "DASH__SUPPRESS_ANALYTICS": "true"}
target, other = "3.47.8", "3.47.9"
results = []


def run(name, arguments, expected):
    print(f"{name}: wren {' '.join(arguments)}", flush=True)
    result = subprocess.run([str(executable), *arguments], cwd=project,
                            env=environment, capture_output=True, text=True,
                            timeout=1200)
    (root / f"{name}.stdout").write_text(result.stdout)
    (root / f"{name}.stderr").write_text(result.stderr)
    results.append({"step": name, "arguments": arguments, "status": result.returncode})
    (root / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    if result.returncode not in expected:
        raise RuntimeError(f"{name}: status {result.returncode}; see {root}")
    return result.stdout


def diagnose(name, *, full=False, expected=(0,)):
    report = json.loads(run(name, ["doctor", target, *(["--full"] if full else []),
                                   "--json"], expected))
    assert report["scope"] == {"kind": "release", "requested_release": target}
    assert [release["version"] for release in report["releases"]] == [target]
    assert report["selection"]["release"] == other
    assert report["selection"]["integrity"] is None
    return report


def snapshot(directory):
    contents = {}
    for current, directories, files in os.walk(directory, followlinks=False):
        for name in sorted(directories + files):
            path = Path(current) / name
            relative = str(path.relative_to(directory))
            if path.is_symlink():
                contents[relative] = ["link", os.readlink(path)]
            elif path.is_file():
                digest = hashlib.sha256()
                with path.open("rb") as file:
                    for block in iter(lambda: file.read(1024 * 1024), b""):
                        digest.update(block)
                contents[relative] = ["file", digest.hexdigest(), path.stat().st_mode & 0o777]
    return contents


version = run("version", ["--version"], (0,)).strip()
assert version == "wren 0.0.1", version
for release in (target, other):
    run(f"install-{release}", ["install", release], (0, 4))
    if results[-1]["status"] == 4:
        run(f"repair-{release}", ["repair", release], (0,))
        run(f"retry-install-{release}", ["install", release], (0,))
(project / "pubspec.yaml").write_text(
    f"name: wren_smoke\nenvironment:\n  flutter: ^{target}\n  sdk: ^3.13.7\n")
run("flutter-version", ["flutter", "--version"], (0,))
run("dart-version", ["dart", "--version"], (0,))
other_bin = store / f"releases/stable-{other}-darwin-arm64/bin"
before = snapshot(other_bin)
diagnose("healthy-quick")
full = diagnose("full-local-evidence", full=True, expected=(0, 4))
assert not full["has_critical_findings"], full
assert full["releases"][0]["integrity"] in ("fully_verified", "incomplete")
# A stamp is evidence of a downloaded group. Without a trusted inventory,
# the group must be incomplete, never silently treated as fully verified.
cache = store / f"releases/stable-{target}-darwin-arm64/bin/cache"
stamp = cache / "fuchsia-mac.stamp"
original_stamp = stamp.read_bytes() if stamp.exists() else None
stamp.write_text("smoke check: unverified optional group\n")
try:
    incomplete = diagnose("incomplete-full", full=True, expected=(4,))
    assert incomplete["releases"][0]["integrity"] == "incomplete", incomplete
finally:
    if original_stamp is None:
        stamp.unlink()
    else:
        stamp.write_bytes(original_stamp)
payload = cache / "pkg/sky_engine/pubspec.yaml"
original_payload = payload.read_bytes()
payload.write_bytes(original_payload + b"\n# release smoke corruption\n")
try:
    damaged = diagnose("damaged-full", full=True, expected=(1, 4))
    assert damaged["releases"][0]["integrity"] == "needs_repair", damaged
    diagnose("damaged-quick", expected=(1,))
finally:
    payload.write_bytes(original_payload)
assert snapshot(other_bin) == before, "non-target SDK payloads changed"
print(f"Passed macOS release smoke check. Evidence: {root}")
print("The isolated target retains a repair marker after the damage check.")
