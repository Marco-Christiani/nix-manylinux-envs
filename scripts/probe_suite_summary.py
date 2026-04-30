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
    prefix = "manylinux_2_28_candidate_"
    suffix = "-auditwheel-show"
    if stem.startswith(prefix) and stem.endswith(suffix):
        return stem[len(prefix) : -len(suffix)]
    return stem


def main() -> None:
    args = parse_args()
    reports = [pathlib.Path(item) for item in args.reports]
    entries = []
    for report in reports:
        entries.append(
            {
                "probe": probe_name_from_report(report),
                "report": str(report),
                "tag": extract_tag(report),
            }
        )

    expected = args.target
    passes = [entry for entry in entries if entry["tag"] == expected]
    failures = [entry for entry in entries if entry["tag"] != expected]
    summary = {
        "expectedTag": expected,
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
