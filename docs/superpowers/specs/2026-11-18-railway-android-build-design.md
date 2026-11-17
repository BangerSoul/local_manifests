# Railway Android Build and Public Release

## Intent

Run a reproducible LineageOS 22.1 userdebug build for the Lenovo Tab M11 TB311FU on Railway, then publish the flashable ROM ZIP and checksum as a public GitHub Release in `BangerSoul/local_manifests`.

## Current state

- The manifest repository contains only `TB311FU.xml`; it pins `BangerSoul/device_lenovo_TB311FU` and `BangerSoul/vendor_lenovo_TB311FU` to `lineage-22.1`.
- The device tree declares `lineage_TB311FU-userdebug`, sets `TARGET_NO_KERNEL := false`, and points at `prebuilt/dtbo.img`, which is absent. Its manifest has no kernel project.
- `BangerSoul/kernel_lenovo_TB311FU` contains GKI defconfigs, patches, and a GitHub workflow, not a complete kernel source tree. The workflow clones `kernel/common` separately.
- The vendor tree contains 111 placeholder files. The connected tablet currently has only 41 of those 111 paths; its extractor does not actually pull from ADB, can create placeholder blobs, and refers to `Any` without importing it.
- Railway currently has a Trial service. AOSP's current build requirements are 64 GB RAM and 400 GB free disk. Railway Trial resources and storage are far below that.
- A public ROM release may contain Lenovo proprietary vendor binaries. The user selected public GitHub Releases as the destination.

## Implementation correction after source review

The kernel helper workflow does not provide TB311FU DTBO source files, masks its `dtbo.img` build failure, and also applies module-signature and permissive dm-verity bypasses. The Railway implementation therefore uses the matching stock kernel image component and `dtbo.img` from one authorized TB311FU firmware dump. It validates both before the Android source sync and does not add a generic GKI kernel to a public ROM without demonstrated device compatibility.

## Goals

- Replace Railpack detection with a Docker based Railway build container.
- Keep the Android checkout, build output, and cache on a persistent Railway volume.
- Run as a one shot job with explicit manual deployment and no retry loop.
- Fail before syncing/building when runner resources or device inputs are incomplete.
- Build `lineage_TB311FU-userdebug` from the pinned `lineage-22.1` sources.
- On a successful build only, publish the flashable OTA ZIP, SHA-256 checksum, and a small build provenance file to a tagged public GitHub Release.
- Keep GitHub credentials in Railway service variables; never commit them.

## Non-goals

- Upgrading the Railway account or changing billing settings.
- Flashing or modifying the tablet.
- Publishing signing keys or private build credentials.
- Changing the ROM branch or adding unrelated tablet features.

## Approaches

1. **Railway one shot build service with a persistent volume — selected.** Railway builds a small Ubuntu toolchain image from this repo. At runtime the service checks resources and source inputs, syncs LineageOS into a mounted volume, builds the target, and uploads artifacts to a tagged GitHub Release. This keeps the requested build on Railway and preserves the expensive source checkout between runs.
2. **Always on Railway builder.** Rejected because it would hold paid compute while idle and offers no benefit for a build that exits when complete.
3. **Build on another provider.** Rejected because the user chose to keep the build on Railway.

## Design decisions

- Use a Dockerfile and a shell entrypoint. Do not use Railpack auto-detection. Do not rely on Railway's legacy `railway.toml` configuration; Railway is deprecating Config as Code on 2026-12-01.
- Treat the Railway service as a manually triggered, one shot deployment. Set restart policy to `NEVER`, disable automatic deploys for ordinary commits, and do not configure a cron schedule.
- Mount one persistent volume at `/workspace`. Require at least 400 GiB free at the start of a run; provision enough total volume size to leave this free after filesystem overhead and future growth.
- Require at least 64 GiB RAM and Linux x86-64. Railway must provide Enterprise/custom per-replica resources; Trial cannot run this workload, and the documented Pro per-replica memory cap is below the target.
- Pin repo sync and build to LineageOS 22.1 and the manifest's existing target. Do not silently upgrade the ROM branch.
- Before a build, verify the matching stock kernel image, DTBO, and all required proprietary files. Placeholder or missing inputs stop the job before source sync.
- Do not extract files from a tablet at Railway runtime. Prepare device and vendor inputs from an authorized firmware dump or the local vendor image, validate them, then sync them as build inputs.
- Require a release tag for publication. Upload only after build and artifact checks pass. The public release contains the ROM ZIP, its SHA-256 file, and source/build revision metadata. Use a `GH_TOKEN` Railway variable with repository contents write permission.
- Do not publish proprietary blobs as a standalone source archive. The ROM package is still public and may include them; the owner must have rights to distribute those binaries.

## Implementation scope

The implementation spans the linked Android input repositories as well as `BangerSoul/local_manifests`:

- In `BangerSoul/local_manifests`, add a `Dockerfile`, preflight and kernel-input preparation scripts, `scripts/railway-build.sh`, and Railway setup/release instructions in `README.md`. The script handles resource checks, source sync, target build, artifact validation, checksum/provenance generation, and tagged release upload.
- In `BangerSoul/device_lenovo_TB311FU`, update `BoardConfig.mk` to consume the verified kernel/DTBO outputs and repair `extract-files.py` so it imports its typing dependencies, validates listed hashes, and errors on missing inputs instead of generating placeholders.
- In `BangerSoul/vendor_lenovo_TB311FU`, replace the 111 placeholder files with the matching real files from an authorized device/vendor dump and preserve verified hashes. The tablet currently supplies 41 listed files, so the remaining paths must come from the local vendor image or a matching firmware dump.
- Use the matching firmware kernel image component and DTBO as prebuilts; do not compile the helper's generic kernel workflow for this ROM.
- Pin the exact device/vendor commits validated by the lightweight preflight into the runtime local manifest so a moving branch cannot change inputs before sync.
- Add a preflight that rejects missing DTBO/kernel inputs, missing vendor files, invalid hashes, and placeholder binaries before the Android source sync begins.

## Acceptance criteria

- Railway selects the Dockerfile and no longer reports that the repository has nothing to build.
- The job fails clearly before a large sync if RAM, free volume space, DTBO, kernel, or proprietary blobs are missing or invalid.
- With complete sources and a qualifying Railway runner, the target builds and the deployment reaches Completed.
- A successful run publishes the ROM ZIP, matching SHA-256 checksum, and provenance file to the requested public GitHub Release.
- Failed or incomplete builds never create or update a release.
- No build artifacts or secrets are committed to the source repository.
