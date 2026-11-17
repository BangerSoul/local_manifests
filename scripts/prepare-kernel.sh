#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE=/workspace
ANDROID_ROOT="$WORKSPACE/lineage"
INPUT_DIR="$WORKSPACE/preflight/kernel-inputs"
PREBUILT="$ANDROID_ROOT/device/lenovo/TB311FU/prebuilt"
VALIDATOR=/opt/manifest/scripts/validate-kernel-inputs.py

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

[[ -s "$INPUT_DIR/Image" && -s "$INPUT_DIR/dtbo.img" ]] \
    || fail "Validated firmware kernel/DTBO inputs are missing from $INPUT_DIR."
(cd "$INPUT_DIR" && sha256sum -c kernel-inputs.sha256) \
    || fail "Firmware kernel/DTBO changed after preflight."
python3 "$VALIDATOR" --kernel "$INPUT_DIR/Image" --dtbo "$INPUT_DIR/dtbo.img"

mkdir -p "$PREBUILT" "$WORKSPACE/provenance"
cp "$INPUT_DIR/Image" "$PREBUILT/Image"
cp "$INPUT_DIR/dtbo.img" "$PREBUILT/dtbo.img"
(cd "$PREBUILT" && sha256sum -c "$INPUT_DIR/kernel-inputs.sha256") \
    || fail "Prepared kernel/DTBO files differ from the preflight inputs."
awk '$2 == "Image" {print $1}' "$INPUT_DIR/kernel-inputs.sha256" \
    > "$WORKSPACE/provenance/kernel-image.sha256"
awk '$2 == "dtbo.img" {print $1}' "$INPUT_DIR/kernel-inputs.sha256" \
    > "$WORKSPACE/provenance/dtbo.sha256"
printf 'matching TB311FU firmware prebuilt\n' > "$WORKSPACE/provenance/kernel-source.txt"
printf '[OK] Matching firmware kernel and DTBO are ready under %s\n' "$PREBUILT"
