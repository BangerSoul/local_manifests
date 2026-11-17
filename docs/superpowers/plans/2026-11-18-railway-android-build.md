# Railway Android Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute task-by-task; each repository change stays on a `codex/railway-android-build` branch until reviewed.

**Goal:** Build a LineageOS 22.1 userdebug ROM for TB311FU on Railway and publish the flashable ZIP plus integrity metadata to a public GitHub Release.

**Architecture:** A one-shot Railway Docker service keeps the full Lineage checkout and output on a persistent volume. It validates vendor blobs and matching firmware kernel/DTBO inputs before sync, pins the validated device/vendor commits, builds the ROM, then creates a tagged release only after every artifact check passes.

**Tech Stack:** Ubuntu Linux, Docker, LineageOS `repo`, Bash, AOSP/Lineage build tools, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-11-18-railway-android-build-design.md`

## Global Constraints

- Keep the Android branch at `lineage-22.1`; lunch target is `lineage_TB311FU-userdebug`.
- The Railway runtime needs Linux x86-64, at least 64 GiB RAM, and at least 400 GiB free on the persistent volume.
- Run one job per manual deployment; restart policy is `NEVER`, with automatic deploys and cron disabled.
- Never generate or accept placeholder proprietary blobs.
- Require the matching TB311FU kernel image and `dtbo.img` from one firmware dump under `/workspace/inputs` before source sync.
- Store `GH_TOKEN` as a Railway secret variable; require a new `BUILD_TAG` for each public release.
- Do not modify or flash the connected tablet.
- Do not add or run a separate automated test suite; verification is the configured build and release checks requested by the user.

## Review Focus

- Missing or mismatched vendor files: require all 111 listed paths and valid SHA-256 values before source sync/build.
- Missing DTBO/kernel inputs: require valid matching firmware prebuilts before the Android source sync starts.
- Railway resource/storage shortfall: report actual and required values, then exit before repo sync.
- Repeated/invalid release tag: stop before creating a release; never overwrite an existing tag.
- GitHub's 2 GiB per-asset limit: upload the OTA ZIP directly when below the limit; otherwise split into 1900 MiB parts and document reassembly.
- Failed build or incomplete ZIP: preserve source/output on the volume and create no GitHub Release.

---

### Task 1: Repair and validate vendor source inputs

**Repositories/files:**
- Modify: `BangerSoul/device_lenovo_TB311FU/proprietary-files.txt`
- Modify: `BangerSoul/device_lenovo_TB311FU/extract-files.py`
- Replace placeholder files: `BangerSoul/vendor_lenovo_TB311FU/proprietary/**`

**Interfaces:**
- Input: matching TB311FU vendor image or firmware dump containing the listed proprietary paths.
- Output: vendor tree with exactly the real files required by the proprietary list; each expected hash is verified before packaging.

- [ ] Inspect the workspace's local `vendor_stabilized.img` and the connected device for listed files; do not treat the active device as complete (currently 41 of 111 paths exist).
- [ ] Fix `extract-files.py` to import its annotations, parse the 64-character hashes as SHA-256, read only supplied dump files, fail on missing paths/hash mismatches, and remove placeholder generation.
- [ ] Correct `proprietary-files.txt` entries and hashes against the matching dump; preserve destination mappings.
- [ ] Replace all placeholder vendor files only after all 111 required paths validate; keep source files in the vendor repository as specified by the approved design.
- [ ] Verify the extractor reports 111 valid files, zero missing paths, zero placeholder files, and zero hash mismatches before continuing.

**Stop condition:** If neither the local image nor an authorized firmware dump supplies all 111 files and the matching kernel/DTBO, stop before committing vendor assets or starting the Railway build and report the missing inputs.

---

### Task 2: Validate and prepare compatible kernel and DTBO inputs

**Repositories/files:**
- Modify: `BangerSoul/local_manifests/TB311FU.xml`
- Modify: `BangerSoul/device_lenovo_TB311FU/BoardConfig.mk`
- Create: `BangerSoul/local_manifests/scripts/validate-kernel-inputs.py`
- Create: `BangerSoul/local_manifests/scripts/prepare-kernel.sh`

**Interfaces:**
- Input: the kernel image component and `dtbo.img` from the same matching TB311FU firmware dump, staged at `/workspace/inputs/Image` and `/workspace/inputs/dtbo.img`.
- Output: validated `device/lenovo/TB311FU/prebuilt/Image` and `device/lenovo/TB311FU/prebuilt/dtbo.img`.

- [ ] Require the kernel image component and `dtbo.img` from the same matching firmware dump; fail before repo sync if either is absent or invalid.
- [ ] Validate gzip or raw arm64 kernel signature, Android DT table signature, and SHA-256 values; stage immutable copies for the build.
- [ ] Update `BoardConfig.mk` with `TARGET_FORCE_PREBUILT_KERNEL := true`, `TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image`, and `BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img`.
- [ ] Prepare both prebuilts and record their hashes in provenance before lunch/build.

---

### Task 3: Add the Railway one-shot Android build service

**Files:**
- Create: `BangerSoul/local_manifests/Dockerfile`
- Create: `BangerSoul/local_manifests/scripts/railway-build.sh`
- Create: `BangerSoul/local_manifests/scripts/validate-proprietary.py`
- Create: `BangerSoul/local_manifests/scripts/validate-kernel-inputs.py`
- Create: `BangerSoul/local_manifests/scripts/pin-local-manifest.py`
- Create: `BangerSoul/local_manifests/scripts/prepare-kernel.sh`

**Interfaces:**
- Environment: `BUILD_TAG` and secret `GH_TOKEN`; Railway mounts the persistent volume at `/workspace`.
- Input: `TB311FU.xml`, the repaired device/vendor trees, and validated matching firmware kernel/DTBO inputs.
- Output: completed LineageOS package and build provenance under the persistent workspace.

- [ ] Add an Ubuntu 22.04 x86-64 Docker image with pinned versions of `repo` and `gh`, plus Java, Git/LFS, and Android build dependencies; make the build script the container entrypoint.
- [ ] In `railway-build.sh`, check architecture, memory, volume mount, and free disk before syncing; require at least 64 GiB RAM and 400 GiB free.
- [ ] Preflight all 111 vendor files and matching firmware kernel/DTBO before sync; use only validated, staged copies.
- [ ] Initialize/sync LineageOS 22.1 into `/workspace`, pin the device/vendor revisions validated by preflight, prepare the kernel/DTBO prebuilts, then build `lineage_TB311FU-userdebug`.
- [ ] Require exactly one nonempty TB311FU flashable OTA ZIP from the build output; keep build outputs and logs on the volume.
- [ ] Use shell fail-fast behavior so source sync, kernel, or ROM failures exit nonzero and skip the publish stage.

---

### Task 4: Publish and document the public release

**Files:**
- Create: `BangerSoul/local_manifests/README.md`
- Modify: `BangerSoul/local_manifests/scripts/railway-build.sh`

**Interfaces:**
- Input: successful ROM ZIP, unique `BUILD_TAG`, and `GH_TOKEN` with contents-write permission.
- Output: public GitHub Release containing the ZIP, SHA-256 file, and build provenance.

- [ ] Document Railway Dockerfile selection, a volume mounted at `/workspace` with enough capacity to retain 400 GiB free, custom per-replica RAM of at least 64 GiB, one replica, restart policy `NEVER`, and disabled automatic deploys/cron.
- [ ] Require `BUILD_TAG` and validate the tag before publication; never commit the token or artifacts to Git.
- [ ] Generate SHA-256 for the complete ROM ZIP and provenance containing target, branch, manifest revision, device/vendor revisions, firmware kernel/DTBO hashes, and build timestamp.
- [ ] Create the public release only after the package and checksum verify; upload the ZIP directly if it is under 2 GiB, otherwise upload 1900 MiB numbered parts plus checksum/provenance and document reassembly. Fail if the tag already exists.
- [ ] Provide manual Railway deployment steps and explain that the first run requires the complete source sync and qualifying custom-resource Railway plan.

---

### Task 5: Run the requested Railway build and publish

- [ ] Wait until the Railway project has the documented custom compute and persistent volume; do not change account billing or plans.
- [ ] Connect the service to `BangerSoul/local_manifests`, set its Dockerfile entrypoint, volume and secret variables, disable auto deploy/cron, and set restart policy to `NEVER`.
- [ ] Trigger one manual deployment with a fresh `BUILD_TAG`; monitor it through completion.
- [ ] Confirm Railway reports `Completed`, the build log shows the selected target, and the public GitHub Release contains the ROM ZIP (or all numbered parts), matching SHA-256, and provenance.
- [ ] If preflight or build fails, fix the reported input on its owning repository and rerun with a new tag; do not publish partial artifacts.

## Handoff limitations

Railway Trial cannot satisfy the required build resources, and this plan does not authorize a billing-plan change. The connected tablet currently lacks 70 listed vendor paths; a matching vendor image or firmware dump must supply them before Task 1 can finish.
