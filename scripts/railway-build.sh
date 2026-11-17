#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE=/workspace
ANDROID_ROOT="$WORKSPACE/lineage"
PREFLIGHT_ROOT="$WORKSPACE/preflight"
PROVENANCE_DIR="$WORKSPACE/provenance"
ARTIFACTS_DIR="$WORKSPACE/artifacts"
MANIFEST_REPO=/opt/manifest
BUILD_BRANCH=lineage-22.1
BUILD_TARGET=lineage_TB311FU-userdebug
BUILD_STARTED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RELEASE_REPO=BangerSoul/local_manifests
RELEASE_CREATED=0

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

check_memory() {
    local limit v2 v1 candidate
    limit=""
    v2="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
    v1="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true)"
    for candidate in "$v2" "$v1"; do
        if [[ "$candidate" =~ ^[0-9]+$ ]] && (( candidate < 9223372036850000000 )); then
            if [[ -z "$limit" ]] || (( candidate < limit )); then
                limit="$candidate"
            fi
        fi
    done
    [[ -n "$limit" ]] || fail "Cannot read the Railway replica cgroup memory limit; refusing to infer it from host RAM."
    local required=$((64 * 1024 * 1024 * 1024))
    (( limit >= required )) || fail "Runner has $((limit / 1024 / 1024 / 1024)) GiB RAM; this build requires at least 64 GiB."
    printf 'Memory preflight passed: %s GiB cgroup limit.\n' "$((limit / 1024 / 1024 / 1024))"
}

check_volume() {
    [[ -d "$WORKSPACE" ]] || fail "Railway volume mount is missing at $WORKSPACE."
    mountpoint -q "$WORKSPACE" || fail "$WORKSPACE is not a mounted persistent volume. Mount the Railway volume at /workspace."
    local available required
    available="$(df --output=avail -B1 "$WORKSPACE" | tail -n 1 | tr -d '[:space:]')"
    [[ "$available" =~ ^[0-9]+$ ]] || fail "Could not determine free space on $WORKSPACE."
    required=$((400 * 1024 * 1024 * 1024))
    (( available >= required )) || fail "Persistent volume has $((available / 1024 / 1024 / 1024)) GiB free; this build requires at least 400 GiB free."
    printf 'Volume preflight passed: %s GiB free on %s.\n' "$((available / 1024 / 1024 / 1024))" "$WORKSPACE"
}

update_or_clone() {
    local url="$1" ref="$2" path="$3"
    if [[ -d "$path/.git" ]]; then
        git -C "$path" fetch --depth=1 origin "$ref"
        git -C "$path" checkout --detach FETCH_HEAD
        git -C "$path" clean -fdx
    elif [[ -e "$path" ]]; then
        fail "Preflight path exists but is not a git checkout: $path"
    else
        git clone --depth=1 --branch "$ref" "$url" "$path"
    fi
    git -C "$path" lfs pull
}

manifest_revision_for() {
    python3 - "$MANIFEST_REPO/TB311FU.xml" "$1" <<'PY'
import sys
import xml.etree.ElementTree as ET

manifest = ET.parse(sys.argv[1]).getroot()
repository = sys.argv[2]
matches = [
    project.get("revision")
    for project in manifest.findall("project")
    if project.get("name") == repository
]
if len(matches) != 1 or not matches[0]:
    raise SystemExit(f"Expected one pinned revision for {repository} in TB311FU.xml")
print(matches[0])
PY
}

check_tag_is_unused() {
    local refs status
    set +e
    refs="$(git ls-remote --exit-code --refs "https://github.com/${RELEASE_REPO}.git" "refs/tags/${BUILD_TAG}" 2>/dev/null)"
    status=$?
    set -e
    if (( status == 0 )) && [[ -n "$refs" ]]; then
        fail "Release tag already exists: $BUILD_TAG"
    fi
    (( status == 2 )) || (( status == 0 )) || fail "Could not check whether release tag $BUILD_TAG exists."
}

cleanup_draft_release() {
    local status=$?
    if (( status != 0 && RELEASE_CREATED == 1 )); then
        local is_draft
        is_draft="$(gh release view "$BUILD_TAG" --repo "$RELEASE_REPO" --json isDraft --jq '.isDraft' 2>/dev/null || true)"
        if [[ "$is_draft" == true ]]; then
            printf '[WARN] Build failed after creating a draft; removing its draft release and tag.\n' >&2
            gh release delete "$BUILD_TAG" --repo "$RELEASE_REPO" --yes --cleanup-tag >/dev/null 2>&1 || true
        else
            printf '[WARN] Release state could not be confirmed as draft; leaving the release untouched.\n' >&2
        fi
    fi
    exit "$status"
}

[[ "$(uname -m)" == x86_64 ]] || fail "Railway runner architecture must be Linux x86_64."
[[ -n "${BUILD_TAG:-}" ]] || fail "Set BUILD_TAG to a fresh release tag before deploying."
[[ "$BUILD_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || fail "BUILD_TAG contains unsupported characters."
[[ -n "${GH_TOKEN:-}" ]] || fail "Set GH_TOKEN as a Railway secret with contents:write access to $RELEASE_REPO."
MANIFEST_REVISION=${SOURCE_MANIFEST_REVISION:-${RAILWAY_GIT_COMMIT_SHA:-}}
[[ "$MANIFEST_REVISION" =~ ^[0-9a-fA-F]{40}$ ]] || fail "Railway did not provide a valid RAILWAY_GIT_COMMIT_SHA build revision."
export MANIFEST_REVISION

check_memory
check_volume
mkdir -p "$WORKSPACE/logs"
exec > >(tee -a "$WORKSPACE/logs/railway-build.log") 2>&1
trap cleanup_draft_release EXIT

command -v repo >/dev/null 2>&1 || fail "The pinned Android repo client is not installed."
command -v gh >/dev/null 2>&1 || fail "The pinned GitHub CLI is not installed."
command -v python3 >/dev/null 2>&1 || fail "Python 3 is required."
gh auth status >/dev/null 2>&1 || fail "GH_TOKEN is not accepted by GitHub CLI."
check_tag_is_unused

mkdir -p "$PREFLIGHT_ROOT" "$PROVENANCE_DIR" "$ARTIFACTS_DIR"
DEVICE_REF="$(manifest_revision_for BangerSoul/device_lenovo_TB311FU)"
VENDOR_REF="$(manifest_revision_for BangerSoul/vendor_lenovo_TB311FU)"
update_or_clone https://github.com/BangerSoul/device_lenovo_TB311FU.git "$DEVICE_REF" "$PREFLIGHT_ROOT/device"
update_or_clone https://github.com/BangerSoul/vendor_lenovo_TB311FU.git "$VENDOR_REF" "$PREFLIGHT_ROOT/vendor"
export PREBUILD_DEVICE_REVISION="$(git -C "$PREFLIGHT_ROOT/device" rev-parse HEAD)"
export PREBUILD_VENDOR_REVISION="$(git -C "$PREFLIGHT_ROOT/vendor" rev-parse HEAD)"
printf 'Preflight device revision: %s\n' "$PREBUILD_DEVICE_REVISION"
printf 'Preflight vendor revision: %s\n' "$PREBUILD_VENDOR_REVISION"
python3 "$MANIFEST_REPO/scripts/validate-proprietary.py" \
    --device-dir "$PREFLIGHT_ROOT/device" \
    --vendor-dir "$PREFLIGHT_ROOT/vendor"
python3 "$MANIFEST_REPO/scripts/validate-kernel-inputs.py" \
    --kernel "$WORKSPACE/inputs/Image" \
    --dtbo "$WORKSPACE/inputs/dtbo.img" \
    --output-dir "$PREFLIGHT_ROOT/kernel-inputs"

mkdir -p "$ANDROID_ROOT"
cd "$ANDROID_ROOT"
repo init -u https://github.com/LineageOS/android.git -b "$BUILD_BRANCH" --git-lfs
mkdir -p .repo/local_manifests
python3 "$MANIFEST_REPO/scripts/pin-local-manifest.py" \
    --input "$MANIFEST_REPO/TB311FU.xml" \
    --output .repo/local_manifests/TB311FU.xml \
    --device-revision "$PREBUILD_DEVICE_REVISION" \
    --vendor-revision "$PREBUILD_VENDOR_REVISION"
repo sync -c --no-clone-bundle --no-tags -j"$(nproc --all)"

synced_device_revision="$(git -C "$ANDROID_ROOT/device/lenovo/TB311FU" rev-parse HEAD)"
synced_vendor_revision="$(git -C "$ANDROID_ROOT/vendor/lenovo/TB311FU" rev-parse HEAD)"
[[ "$synced_device_revision" == "$PREBUILD_DEVICE_REVISION" ]] \
    || fail "Synced device revision differs from the vendor preflight revision."
[[ "$synced_vendor_revision" == "$PREBUILD_VENDOR_REVISION" ]] \
    || fail "Synced vendor revision differs from the vendor preflight revision."

export USE_CCACHE=1
export CCACHE_DIR="$WORKSPACE/.ccache"
mkdir -p "$CCACHE_DIR"
"$MANIFEST_REPO/scripts/prepare-kernel.sh"

source build/envsetup.sh
lunch "$BUILD_TARGET"
PRODUCT_OUT="$ANDROID_ROOT/out/target/product/TB311FU"
mkdir -p "$PRODUCT_OUT"
mapfile -t stale_ota_zips < <(find "$PRODUCT_OUT" -maxdepth 1 -type f -name 'lineage-*-TB311FU.zip' -print | sort)
if (( ${#stale_ota_zips[@]} > 0 )); then
    archive_dir="$WORKSPACE/archive/previous-ota/$BUILD_TAG"
    mkdir -p "$archive_dir"
    for stale_zip in "${stale_ota_zips[@]}"; do
        mv "$stale_zip" "$archive_dir/$(basename "$stale_zip")"
    done
    printf 'Archived %s previous OTA ZIP(s) under %s.\n' "${#stale_ota_zips[@]}" "$archive_dir"
fi
mka bacon

mapfile -t ota_zips < <(find "$PRODUCT_OUT" -maxdepth 1 -type f -name 'lineage-*-TB311FU.zip' -size +0c -print | sort)
(( ${#ota_zips[@]} == 1 )) || fail "Expected exactly one nonempty TB311FU flashable OTA ZIP; found ${#ota_zips[@]}."
ROM_ZIP="${ota_zips[0]}"
unzip -tqq "$ROM_ZIP" || fail "The generated ROM ZIP failed its archive integrity check."

BUILD_STARTED_UTC=${BUILD_STARTED_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
export BUILD_STARTED_UTC BUILD_TAG BUILD_BRANCH BUILD_TARGET
repo manifest -r > "$PROVENANCE_DIR/resolved-manifest.xml"
repo forall -c 'printf "%s\t%s\n" "$REPO_PATH" "$(git rev-parse HEAD)"' \
    | sort > "$PROVENANCE_DIR/project-revisions.tsv"
python3 - "$PROVENANCE_DIR/build-provenance.json" "$PROVENANCE_DIR/project-revisions.tsv" <<'PY'
import json
import os
import sys
from pathlib import Path

output = Path(sys.argv[1])
revisions_file = Path(sys.argv[2])
projects = {}
for line in revisions_file.read_text(encoding="utf-8").splitlines():
    path, revision = line.split("\t", 1)
    if path in {
        "device/lenovo/TB311FU",
        "vendor/lenovo/TB311FU",
    }:
        projects[path] = revision

def read_revision(name):
    path = output.parent / name
    return path.read_text(encoding="utf-8").strip() if path.is_file() else None

record = {
    "build_tag": os.environ["BUILD_TAG"],
    "build_started_utc": os.environ["BUILD_STARTED_UTC"],
    "target": os.environ["BUILD_TARGET"],
    "branch": os.environ["BUILD_BRANCH"],
    "manifest_repository_revision": os.environ["MANIFEST_REVISION"],
    "device_vendor_projects": projects,
    "kernel_source": read_revision("kernel-source.txt"),
    "kernel_image_sha256": read_revision("kernel-image.sha256"),
    "dtbo_sha256": read_revision("dtbo.sha256"),
}
output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

mkdir -p "$ARTIFACTS_DIR/$BUILD_TAG"
artifact_dir="$ARTIFACTS_DIR/$BUILD_TAG"
cp "$ROM_ZIP" "$artifact_dir/"
rom_copy="$artifact_dir/$(basename "$ROM_ZIP")"
(cd "$artifact_dir" && sha256sum "$(basename "$rom_copy")" > "$(basename "$rom_copy").sha256")
cp "$PROVENANCE_DIR/build-provenance.json" "$PROVENANCE_DIR/resolved-manifest.xml" \
    "$PROVENANCE_DIR/project-revisions.tsv" "$artifact_dir/"

upload_assets=("$rom_copy.sha256" "$artifact_dir/build-provenance.json" \
    "$artifact_dir/resolved-manifest.xml" "$artifact_dir/project-revisions.tsv")
zip_size="$(stat -c '%s' "$rom_copy")"
max_asset_size=$((2 * 1024 * 1024 * 1024))
if (( zip_size < max_asset_size )); then
    upload_assets+=("$rom_copy")
else
    split -b 1900M --numeric-suffixes=1 --suffix-length=3 \
        "$rom_copy" "$artifact_dir/$(basename "$rom_copy").part-"
    mapfile -t zip_parts < <(find "$artifact_dir" -maxdepth 1 -type f -name "$(basename "$rom_copy").part-*" -print | sort)
    (( ${#zip_parts[@]} > 0 )) || fail "ROM ZIP exceeded 2 GiB but no upload parts were created."
    upload_assets+=("${zip_parts[@]}")
fi

check_tag_is_unused
release_notes="LineageOS 22.1 userdebug build for Lenovo TB311FU.

Verify the assembled ROM with the included SHA-256 file."
if (( zip_size >= max_asset_size )); then
    release_notes+=$'\n\nThe ROM is split into numbered parts because GitHub limits individual release assets to under 2 GiB. Reassemble in the directory containing the parts with: cat '
    release_notes+="$(basename "$rom_copy").part-* > $(basename "$rom_copy") && sha256sum -c $(basename "$rom_copy").sha256"
fi
gh release create "$BUILD_TAG" \
    --repo "$RELEASE_REPO" \
    --title "LineageOS 22.1 for Lenovo TB311FU $BUILD_TAG" \
    --notes "$release_notes" \
    --target "$MANIFEST_REVISION" \
    --draft
RELEASE_CREATED=1
gh release upload "$BUILD_TAG" "${upload_assets[@]}" --repo "$RELEASE_REPO"

published_assets="$(gh release view "$BUILD_TAG" --repo "$RELEASE_REPO" --json assets --jq '.assets[].name')"
for asset_path in "${upload_assets[@]}"; do
    asset_name="$(basename "$asset_path")"
    grep -Fxq "$asset_name" <<<"$published_assets" || fail "Release draft is missing uploaded asset $asset_name."
done
gh release edit "$BUILD_TAG" --repo "$RELEASE_REPO" --draft=false
RELEASE_CREATED=0
gh release view "$BUILD_TAG" --repo "$RELEASE_REPO"
printf '[OK] Railway build and public release completed: %s\n' "$BUILD_TAG"
