#!/usr/bin/env python3
"""Build selected PyPI sdists in manylinux candidate shells."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_MATRIX = ROOT / "data" / "package-matrix.json"
TAG_RE = re.compile(r'This constrains the platform tag to "([^"]+)"')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", type=pathlib.Path, default=DEFAULT_MATRIX)
    parser.add_argument("--out-dir", type=pathlib.Path, required=True)
    parser.add_argument("--packages", default="smoke")
    parser.add_argument("--targets", default="manylinux_2_28_candidate")
    parser.add_argument("--repair-mode", choices=("none", "auto", "target"), default="target")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--list", action="store_true", help="print selected package/target pairs without building")
    parser.add_argument("--skip-published", action="store_true")
    return parser.parse_args()


def load_json_url(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def wheel_platform_tags(filename: str) -> list[str]:
    stem = filename.removesuffix(".whl")
    parts = stem.rsplit("-", 3)
    if len(parts) != 4:
        return []
    return parts[3].split(".")


def requested_packages(matrix: dict, selector: str) -> list[tuple[str, dict]]:
    packages = matrix["packages"]
    if selector == "all":
        names = sorted(packages)
    else:
        requested = {part.strip() for part in selector.split(",") if part.strip()}
        names = [
            name
            for name, spec in sorted(packages.items())
            if name in requested or requested.intersection(spec.get("groups", []))
        ]

    if not names:
        raise SystemExit(f"no packages matched selector: {selector}")

    return [(name, packages[name]) for name in names]


def download_sdist(name: str, version: str, dest: pathlib.Path) -> pathlib.Path:
    metadata = load_json_url(f"https://pypi.org/pypi/{name}/{version}/json")
    sdists = [item for item in metadata["urls"] if item.get("packagetype") == "sdist"]
    if not sdists:
        raise RuntimeError(f"{name} {version} has no sdist on PyPI")

    sdist = sdists[0]
    target = dest / sdist["filename"]
    urllib.request.urlretrieve(sdist["url"], target)
    return target


def published_manylinux_platforms(name: str, version: str) -> list[str]:
    metadata = load_json_url(f"https://pypi.org/pypi/{name}/{version}/json")
    platforms: set[str] = set()
    for item in metadata["urls"]:
        filename = item.get("filename", "")
        if item.get("packagetype") != "bdist_wheel":
            continue
        if "x86_64" not in filename or "manylinux" not in filename:
            continue
        platforms.update(tag for tag in wheel_platform_tags(filename) if tag.startswith("manylinux"))
    return sorted(platforms)


def extract_sdist(archive: pathlib.Path, dest: pathlib.Path) -> pathlib.Path:
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(dest)
    else:
        with tarfile.open(archive) as tf:
            try:
                tf.extractall(dest, filter="data")
            except TypeError:
                tf.extractall(dest)

    entries = [path for path in dest.iterdir() if path.is_dir()]
    if len(entries) != 1:
        raise RuntimeError(f"expected one top-level source directory in {archive}, found {len(entries)}")
    return entries[0]


def read_auditwheel_floor(build_dir: pathlib.Path) -> str | None:
    report = build_dir / "auditwheel.txt"
    if not report.exists():
        return None
    match = TAG_RE.search(report.read_text(encoding="utf-8", errors="replace"))
    return match.group(1) if match else None


def built_wheel_platforms(build_dir: pathlib.Path) -> list[str]:
    wheel_dir = build_dir / "repaired"
    if not wheel_dir.exists():
        wheel_dir = build_dir / "dist"
    platforms: set[str] = set()
    for wheel in wheel_dir.glob("*.whl"):
        platforms.update(wheel_platform_tags(wheel.name))
    return sorted(platforms)


def run_build(
    *,
    package_name: str,
    source_dir: pathlib.Path,
    target: str,
    out_dir: pathlib.Path,
    repair_mode: str,
    extra_packages: list[str],
) -> tuple[int, float]:
    log_path = out_dir / "command.log"
    command = [
        str(ROOT / "scripts" / "build_external_package.sh"),
        "--repair-mode",
        repair_mode,
        target,
        str(source_dir),
        str(out_dir),
        *extra_packages,
    ]

    started = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log:
        log.write(f"package: {package_name}\n")
        log.write(f"command: {subprocess.list2cmdline(command)}\n\n")
        log.flush()
        completed = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=False)
    return completed.returncode, time.monotonic() - started


def main() -> int:
    args = parse_args()
    matrix = json.loads(args.matrix.read_text(encoding="utf-8"))
    package_specs = requested_packages(matrix, args.packages)
    targets = [part.strip() for part in args.targets.split(",") if part.strip()]
    if not targets:
        raise SystemExit("--targets did not name any targets")

    if args.list:
        print(json.dumps({
            "packages": [
                {"name": name, "version": spec["version"], "groups": spec.get("groups", [])}
                for name, spec in package_specs
            ],
            "targets": targets,
            "repairMode": args.repair_mode,
        }, indent=2))
        return 0

    args.out_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []

    with tempfile.TemporaryDirectory(prefix="manylinux-package-matrix-") as tmp:
        tmpdir = pathlib.Path(tmp)
        sdists = tmpdir / "sdists"
        sources = tmpdir / "sources"
        sdists.mkdir()
        sources.mkdir()

        for package_name, spec in package_specs:
            version = spec["version"]
            extra_packages = spec.get("extraPipPackages", [])
            package_source_root = sources / package_name
            package_source_root.mkdir()

            print(f"fetch {package_name}=={version}", flush=True)
            sdist = download_sdist(package_name, version, sdists)
            source_dir = extract_sdist(sdist, package_source_root)
            published = [] if args.skip_published else published_manylinux_platforms(package_name, version)

            for target in targets:
                build_dir = args.out_dir / package_name / target
                if build_dir.exists():
                    shutil.rmtree(build_dir)
                build_dir.mkdir(parents=True)

                print(f"build {package_name}=={version} target={target} repair={args.repair_mode}", flush=True)
                returncode, elapsed = run_build(
                    package_name=package_name,
                    source_dir=source_dir,
                    target=target,
                    out_dir=build_dir,
                    repair_mode=args.repair_mode,
                    extra_packages=extra_packages,
                )

                result = {
                    "package": package_name,
                    "version": version,
                    "target": target,
                    "repairMode": args.repair_mode,
                    "returncode": returncode,
                    "elapsedSeconds": round(elapsed, 3),
                    "auditwheelFloor": read_auditwheel_floor(build_dir),
                    "builtPlatformTags": built_wheel_platforms(build_dir) if returncode == 0 else [],
                    "publishedManylinuxPlatformTags": published,
                    "logs": {
                        "command": str(build_dir / "command.log"),
                        "pip": str(build_dir / "pip.log"),
                        "build": str(build_dir / "build.log"),
                        "auditwheel": str(build_dir / "auditwheel.txt"),
                        "repair": str(build_dir / "repair.log"),
                    },
                }
                results.append(result)
                print(json.dumps(result, sort_keys=True), flush=True)

                if returncode != 0 and args.fail_fast:
                    (args.out_dir / "summary.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
                    return returncode

    (args.out_dir / "summary.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    failures = [result for result in results if result["returncode"] != 0]
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
