# Railway Android build for TB311FU

This repository defines a manually triggered, one-shot LineageOS 22.1 build for the Lenovo Tab M11 TB311FU. Railway uses the root `Dockerfile`; the container checks prerequisites, syncs the Android sources to a persistent volume, builds `lineage_TB311FU-userdebug`, and publishes the ROM ZIP with SHA-256 and provenance to a public GitHub Release.

Railway detects a root `Dockerfile` automatically. See [Railway Dockerfile builds](https://docs.railway.com/builds/dockerfiles).

## Required before deployment

- A Railway runner with Linux x86-64 and at least **64 GiB RAM**.
- A Railway persistent volume mounted at `/workspace` with at least **400 GiB free** at the beginning of each run. Leave additional capacity for filesystem overhead and growth.
- The kernel image component and `dtbo.img` extracted from the same matching TB311FU firmware, staged on the volume as `/workspace/inputs/Image` and `/workspace/inputs/dtbo.img`.
- A Railway secret variable `GH_TOKEN` with `contents:write` access to `BangerSoul/local_manifests`.
- A fresh `BUILD_TAG` for each public release, using letters, numbers, dots, underscores, and hyphens. For example: `lineage-22.1-2026.11.18.1`.
- Complete, real TB311FU proprietary files whose SHA-256 hashes match `device/lenovo/TB311FU/proprietary-files.txt`.

The existing Railway Trial resources cannot satisfy the RAM or storage requirements. The account plan and billing settings must be changed by the owner if a qualifying custom runner is provisioned; this repository does not change them.

## Railway service settings

1. Connect a Railway service to `BangerSoul/local_manifests` and select the `codex/railway-android-build` branch while reviewing this implementation.
2. Use the repository root as the service root. Keep Dockerfile path at its default, `Dockerfile`.
3. Attach the persistent volume at `/workspace`.
4. Set one replica, restart policy `Never`, automatic deploys off, and no cron schedule. Deploy manually for each build.
5. Set `GH_TOKEN` as a secret variable and set a unique `BUILD_TAG`.
6. Trigger one manual deployment. The script logs to Railway and persists its log, source checkout, and build output under `/workspace`.

The first successful run downloads and syncs the full LineageOS source tree, so it can take a long time. Later runs reuse the persistent checkout and ccache.

## Proprietary source inputs

The build performs a small source preflight before `repo sync`. It rejects missing files, empty files, placeholders, Git LFS pointer files, or any SHA-256 mismatch. No full Android checkout starts until all listed inputs pass.

The device repository currently contains placeholder hash values and the vendor repository contains placeholder blobs. A matching firmware dump is required to replace those inputs before the Android build can run. The extractor now requires a supplied dump and verifies all source hashes before replacing any vendor files:

```sh
python3 device/lenovo/TB311FU/extract-files.py \
  --dump-dir /path/to/unpacked/TB311FU/firmware \
  --vendor-out vendor/lenovo/TB311FU
```

The dump should preserve partition-relative paths such as `vendor/lib64/...`, `system_ext/framework/...`, `product/overlay/...`, and `odm/etc/...`. The extractor never generates placeholder files and does not touch the connected tablet.

The build requires the matching firmware kernel image component and `dtbo.img` at `/workspace/inputs/Image` and `/workspace/inputs/dtbo.img`. The source preflight validates the kernel signature or gzip stream, the Android DT table signature, and SHA-256 values before the large Android source sync. The build then uses these exact stock inputs. The helper repo's generic GKI workflow does not provide TB311FU DTBO sources and contains permissive dm-verity and module-signature bypass edits, so the pipeline does not use that workflow to create a boot kernel.

## Release output

A successful manual run publishes a public GitHub Release containing:

- The flashable `lineage-*-TB311FU.zip` when it is under GitHub's per-file upload limit.
- Numbered 1900 MiB ZIP parts if the ROM is too large for one release asset.
- A SHA-256 file for the complete ZIP.
- `build-provenance.json`, `resolved-manifest.xml`, and `project-revisions.tsv`.

For a split package, download all numbered parts into one directory, then run:

```sh
shopt -s nullglob
parts=(lineage-*-TB311FU.zip.part-*)
(( ${#parts[@]} > 0 )) || { echo "No ROM parts found" >&2; exit 1; }
rom_zip="${parts[0]%.part-*}"
cat "${parts[@]}" > "$rom_zip"
sha256sum -c "$rom_zip.sha256"
```

The release is created as a draft first, checked for every expected asset, and published only after those checks pass. Failed builds publish no public release.
