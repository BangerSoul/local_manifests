#!/usr/bin/env python3
"""Fail closed unless every listed TB311FU vendor input is real and hash-matched."""

import argparse
import hashlib
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Dict, List, Tuple

SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
LFS_POINTER = b"version https://git-lfs.github.com/spec/v1"
EXPECTED_BLOB_COUNT = 111


def safe_path(value: str, field: str, line_number: int) -> str:
    path = PurePosixPath(value)
    if path.is_absolute() or not value or any(part in ("", ".", "..") for part in path.parts):
        raise ValueError(f"line {line_number}: unsafe {field} path {value!r}")
    return path.as_posix()


def parse_list(path: Path) -> List[Dict[str, str]]:
    entries: List[Dict[str, str]] = []
    destinations = set()
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("-"):
            line = line[1:].strip()
        if "|" not in line:
            raise ValueError(f"line {line_number}: missing SHA-256 hash")
        line, digest = line.rsplit("|", 1)
        digest = digest.strip().lower()
        if not SHA256_RE.fullmatch(digest):
            raise ValueError(f"line {line_number}: expected a 64-character SHA-256 hash")
        if ":" in line:
            source, destination = line.split(":", 1)
        else:
            source = destination = line
        source = safe_path(source.strip(), "source", line_number)
        destination = safe_path(destination.strip(), "destination", line_number)
        if destination in destinations:
            raise ValueError(f"line {line_number}: duplicate destination {destination!r}")
        destinations.add(destination)
        entries.append({"source": source, "destination": destination, "sha256": digest})
    if not entries:
        raise ValueError("proprietary-files.txt contains no entries")
    if len(entries) != EXPECTED_BLOB_COUNT:
        raise ValueError(
            f"expected {EXPECTED_BLOB_COUNT} TB311FU blobs, found {len(entries)}"
        )
    return entries


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_placeholder(path: Path) -> bool:
    with path.open("rb") as stream:
        prefix = stream.read(256)
    if LFS_POINTER in prefix or b"# Placeholder blob" in prefix:
        return True
    if path.suffix == ".so" and (not prefix.startswith(b"\x7fELF") or path.stat().st_size < 64):
        return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-dir", type=Path, required=True)
    parser.add_argument("--vendor-dir", type=Path, required=True)
    args = parser.parse_args()

    proprietary_list = args.device_dir / "proprietary-files.txt"
    proprietary_root = args.vendor_dir / "proprietary"
    entries = parse_list(proprietary_list)
    expected_paths = {entry["destination"] for entry in entries}
    problems: List[str] = []
    checked = 0

    for entry in entries:
        path = proprietary_root / entry["destination"]
        if not path.is_file():
            problems.append(f"missing: {entry['destination']}")
            continue
        if path.stat().st_size == 0 or is_placeholder(path):
            problems.append(f"placeholder or empty: {entry['destination']}")
            continue
        actual = sha256(path)
        if actual != entry["sha256"]:
            problems.append(
                f"SHA-256 mismatch: {entry['destination']} "
                f"(expected {entry['sha256']}, got {actual})"
            )
            continue
        checked += 1

    actual_paths = {
        path.relative_to(proprietary_root).as_posix()
        for path in proprietary_root.rglob("*")
        if path.is_file()
    } if proprietary_root.is_dir() else set()
    for extra_path in sorted(actual_paths - expected_paths):
        problems.append(f"unlisted vendor file: {extra_path}")

    print(f"Listed blobs: {len(entries)}; valid: {checked}; problems: {len(problems)}")
    for problem in problems:
        print(f"  - {problem}")
    if problems:
        print("Vendor preflight failed; no Android source sync was started.", file=sys.stderr)
        return 1
    print("Vendor preflight passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
