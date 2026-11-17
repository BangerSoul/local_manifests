#!/usr/bin/env python3
"""Validate and optionally stage a matching TB311FU firmware kernel and DTBO."""

import argparse
import gzip
import hashlib
import shutil
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_kernel(path: Path) -> None:
    with path.open("rb") as stream:
        prefix = stream.read(60)
    if prefix.startswith(b"\x1f\x8b"):
        try:
            with gzip.open(path, "rb") as stream:
                image_header = stream.read(60)
                if len(image_header) < 60 or image_header[56:60] != b"ARM\x64":
                    raise ValueError("gzip payload is not an arm64 Image")
                while stream.read(1024 * 1024):
                    pass
        except (OSError, EOFError) as error:
            raise ValueError(f"Kernel gzip is corrupt: {error}") from error
    elif len(prefix) >= 60 and prefix[56:60] == b"ARM\x64":
        pass
    else:
        raise ValueError("Kernel must be a valid gzip image or raw arm64 Image")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--dtbo", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()

    kernel = args.kernel.resolve()
    dtbo = args.dtbo.resolve()
    for path in (kernel, dtbo):
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"Missing or empty firmware input: {path}")

    try:
        validate_kernel(kernel)
    except ValueError as error:
        raise SystemExit(f"Invalid firmware kernel {kernel}: {error}") from error

    with dtbo.open("rb") as stream:
        dtbo_header = stream.read(4)
    if dtbo_header != b"\x1e\xab\xb7\xd7" or dtbo.stat().st_size < 32:
        raise SystemExit(f"Invalid Android DT table image: {dtbo}")

    hashes = {
        "Image": sha256(kernel),
        "dtbo.img": sha256(dtbo),
    }
    if args.output_dir:
        output_dir = args.output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(kernel, output_dir / "Image")
        shutil.copy2(dtbo, output_dir / "dtbo.img")
        (output_dir / "kernel-inputs.sha256").write_text(
            "".join(f"{digest}  {name}\n" for name, digest in hashes.items()),
            encoding="utf-8",
        )
    print(f"Validated matching firmware kernel: {hashes['Image']} ({kernel.stat().st_size} bytes)")
    print(f"Validated matching firmware DTBO: {hashes['dtbo.img']} ({dtbo.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
