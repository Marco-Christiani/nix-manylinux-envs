#!/usr/bin/env python3

import argparse
import json
import pathlib
import re


TAG_RE = re.compile(r'This constrains the platform tag to "([^"]+)"')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize a set of auditwheel show reports for crafted probes."
    )
    parser.add_argument("--target", required=True)
    parser.add_argument("--reports", nargs="+", required=True)
    parser.add_argument("--exact", action="append", default=[])
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def extract_tag(path: pathlib.Path) -> str | None:
    text = path.read_text(encoding="utf-8")
    match = TAG_RE.search(text)
    return match.group(1) if match else None


def probe_name_from_report(path: pathlib.Path) -> str:
    stem = path.parent.name
    hash_prefix = re.compile(r"^[a-z0-9]{32}-")
    stem = hash_prefix.sub("", stem)
    suffix = "-auditwheel-show"
    if stem.endswith(suffix):
        stem = stem[: -len(suffix)]
    if "_candidate_" in stem:
        return stem.split("_candidate_", 1)[1]
    return stem


def parse_policy_floor(tag: str | None) -> tuple[int, int] | None:
    if tag is None:
        return None
    match = re.fullmatch(r"manylinux_(\d+)_(\d+)_x86_64", tag)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2)))


def main() -> None:
    args = parse_args()
    reports = [pathlib.Path(item) for item in args.reports]
    exact_expectations = dict(item.split("=", 1) for item in args.exact)
    target_floor = parse_policy_floor(args.target)
    entries = []
    for report in reports:
        entries.append(
            {
                "probe": probe_name_from_report(report),
                "report": str(report),
                "tag": extract_tag(report),
            }
        )

    passes = []
    failures = []
    for entry in entries:
        probe = entry["probe"]
        tag = entry["tag"]
        expected = exact_expectations.get(probe)
        if expected is not None:
            entry["expected"] = expected
            if tag == expected:
                passes.append(entry)
            else:
                failures.append(entry)
            continue

        entry["expected"] = f"<= {args.target}"
        tag_floor = parse_policy_floor(tag)
        if target_floor is None or tag_floor is None:
            failures.append(entry)
        elif tag_floor <= target_floor:
            passes.append(entry)
        else:
            failures.append(entry)

    summary = {
        "targetTag": args.target,
        "exactExpectations": exact_expectations,
        "probeCount": len(entries),
        "passingCount": len(passes),
        "failingCount": len(failures),
        "passes": passes,
        "failures": failures,
        "allPass": len(failures) == 0,
    }

    pathlib.Path(args.output).write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
