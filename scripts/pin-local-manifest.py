#!/usr/bin/env python3
"""Write a runtime local manifest pinned to the exact preflighted commits."""

import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device-revision", required=True)
    parser.add_argument("--vendor-revision", required=True)
    args = parser.parse_args()

    revisions = {
        "BangerSoul/device_lenovo_TB311FU": args.device_revision,
        "BangerSoul/vendor_lenovo_TB311FU": args.vendor_revision,
    }
    for repository, revision in revisions.items():
        if not SHA_RE.fullmatch(revision):
            raise SystemExit(f"Invalid preflight commit for {repository}: {revision!r}")

    tree = ET.parse(args.input)
    root = tree.getroot()
    for repository, revision in revisions.items():
        matches = [
            project
            for project in root.findall("project")
            if project.get("name") == repository
        ]
        if len(matches) != 1:
            raise SystemExit(f"Expected exactly one manifest project for {repository}")
        matches[0].set("revision", revision)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(args.output, encoding="UTF-8", xml_declaration=True)
    print(f"Wrote runtime manifest pinned to device/vendor commits: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
