#!/usr/bin/env python3

import argparse
import json
import os
import pathlib
import re
import subprocess
from typing import Dict, Iterable, List, Set


VERSION_RE = re.compile(r"\bName:\s+([A-Z0-9]+)_([^\s]+)")
IGNORED_VERSION_PATTERNS = {
    "GLIBC": ("PRIVATE", "ABI_"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit a conformance report for a Nix-native manylinux build env."
    )
    parser.add_argument("--target-json", required=True)
    parser.add_argument("--runtime-lib-dir", required=True)
    parser.add_argument("--cc", required=True)
    parser.add_argument("--readelf", required=True)
    parser.add_argument("--libc", required=True)
    parser.add_argument("--libstdcxx", required=True)
    parser.add_argument("--libatomic", required=True)
    parser.add_argument("--zlib", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def load_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def run(*cmd: str) -> str:
    return subprocess.check_output(cmd, text=True)


def parse_version_defs(readelf: str, library: str) -> Dict[str, Set[str]]:
    if not os.path.exists(library):
        return {}
    output = run(readelf, "-W", "--version-info", library)
    versions: Dict[str, Set[str]] = {}
    for family, version in VERSION_RE.findall(output):
        versions.setdefault(family, set()).add(version)
    return versions


def parse_numeric_version(version: str) -> List[int]:
    numbers = re.findall(r"\d+", version)
    return [int(n) for n in numbers]


def compare_versions(left: str, right: str) -> int:
    left_parts = parse_numeric_version(left)
    right_parts = parse_numeric_version(right)
    max_len = max(len(left_parts), len(right_parts))
    left_parts.extend([0] * (max_len - len(left_parts)))
    right_parts.extend([0] * (max_len - len(right_parts)))
    if left_parts < right_parts:
        return -1
    if left_parts > right_parts:
        return 1
    return 0


def parse_gcc_version(cc: str) -> str:
    return run(cc, "-dumpfullversion", "-dumpversion").strip()


def parse_toolchain_major(toolchain: str) -> int | None:
    match = re.search(r"GCC\s+(\d+)", toolchain)
    return int(match.group(1)) if match else None


def collect_runtime_libs(runtime_lib_dir: str) -> List[str]:
    lib_dir = pathlib.Path(runtime_lib_dir)
    libs = []
    for entry in sorted(lib_dir.iterdir()):
        if entry.is_symlink() or entry.is_file():
            libs.append(entry.name)
    return libs


def missing_and_extra(
    actual: Iterable[str], expected: Iterable[str]
) -> tuple[List[str], List[str]]:
    actual_set = set(actual)
    expected_set = set(expected)
    return sorted(expected_set - actual_set), sorted(actual_set - expected_set)


def exported_version_findings(
    expected: Dict[str, List[str]],
    actual_by_family: Dict[str, Set[str]],
) -> Dict[str, dict]:
    findings: Dict[str, dict] = {}
    for family, allowed_versions in expected.items():
        allowed = set(allowed_versions)
        actual = actual_by_family.get(family, set())
        ignored_patterns = IGNORED_VERSION_PATTERNS.get(family, ())
        ignored = sorted(
            version
            for version in actual
            if any(
                version == pattern or version.startswith(pattern)
                for pattern in ignored_patterns
            )
        )
        effective_actual = {version for version in actual if version not in ignored}
        unexpected = sorted(effective_actual - allowed) if allowed_versions else []
        findings[family] = {
            "allowedMax": allowed_versions[-1] if allowed_versions else None,
            "actualVersions": sorted(effective_actual),
            "ignoredVersions": ignored,
            "unexpectedVersions": unexpected,
            "conforms": unexpected == [],
        }
    return findings


def main() -> None:
    args = parse_args()
    target = load_json(args.target_json)

    runtime_libs = collect_runtime_libs(args.runtime_lib_dir)
    missing_libs, extra_libs = missing_and_extra(runtime_libs, target["libWhitelist"])

    gcc_version = parse_gcc_version(args.cc)
    expected_gcc_major = parse_toolchain_major(target["officialToolchain"])
    actual_gcc_major = (
        parse_numeric_version(gcc_version)[0]
        if parse_numeric_version(gcc_version)
        else None
    )

    actual_versions: Dict[str, Set[str]] = {}
    for lib_path in [args.libc, args.libstdcxx, args.libatomic, args.zlib]:
        for family, versions in parse_version_defs(args.readelf, lib_path).items():
            actual_versions.setdefault(family, set()).update(versions)

    symbol_findings = exported_version_findings(
        target.get("symbolVersions", {}), actual_versions
    )

    libc_version = target.get("actualLibcVersion")
    glibc_floor = target["glibcFloor"]
    glibc_relation = "unknown"
    if libc_version is not None:
        ordering = compare_versions(libc_version, glibc_floor)
        if ordering < 0:
            glibc_relation = "older-than-floor"
        elif ordering == 0:
            glibc_relation = "matches-floor"
        else:
            glibc_relation = "newer-than-floor"

    report = {
        "target": target["name"],
        "policy": target["policy"],
        "aliases": target["aliases"],
        "officialBaseDistro": target["officialBaseDistro"],
        "officialToolchain": target["officialToolchain"],
        "glibcFloor": glibc_floor,
        "actual": {
            "gccVersion": gcc_version,
            "gccMajorMatchesOfficialReference": (
                expected_gcc_major is not None
                and actual_gcc_major == expected_gcc_major
            ),
            "libcVersion": libc_version,
            "glibcRelationToFloor": glibc_relation,
            "runtimeLibDir": args.runtime_lib_dir,
        },
        "runtimeLibWhitelist": {
            "expectedCount": len(target["libWhitelist"]),
            "actualCount": len(runtime_libs),
            "missing": missing_libs,
            "extra": extra_libs,
            "conforms": missing_libs == [] and extra_libs == [],
        },
        "symbolVersions": symbol_findings,
        "surfaceConformance": {
            "runtimeLibWhitelistConforms": missing_libs == [] and extra_libs == [],
            "symbolVersionsConform": all(
                finding["conforms"] for finding in symbol_findings.values()
            ),
        },
        "notes": target["notes"],
    }
    report["surfaceConformance"]["overallConforms"] = (
        report["surfaceConformance"]["runtimeLibWhitelistConforms"]
        and report["surfaceConformance"]["symbolVersionsConform"]
    )

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")


if __name__ == "__main__":
    main()
