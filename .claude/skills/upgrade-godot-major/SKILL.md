---
name: upgrade-godot-major
description: Upgrade the project to a new Godot minor release (e.g. 4.6 to 4.7). Updates boilerplate versions, researches upstream dependency versions, and bumps internal action references.
disable-model-invocation: true
argument-hint: "<major.minor>"
---

Upgrade this project to Godot version `$ARGUMENTS`. This is a **major version upgrade** affecting
many files. It has three stages: boilerplate version bump, dependency version updates (researched
from upstream), and internal action reference bumps.

## Steps

### 1. Validate and prepare

1. **Validate the argument.** Extract the version (e.g. `4.7`) from `$ARGUMENTS`. Strip a leading
   `v` if present. Verify the format is `major.minor` (exactly two numeric components, no patch).
   If invalid, stop and ask the user.

2. **Determine the current state.** Read `README.md` and find the version table under
   `#### Release tag: Godot version`. Identify:
   - The current Godot version on `main` (e.g. `v4.6.1`)
   - The current release tag number (e.g. `4` from `v4`)
   - Derive: new release tag = `v` + (current tag number + 1)
   - Derive: old major.minor from the current version (e.g. `4.6`)

   Verify the new version is an upgrade (new minor > old minor). If not, stop and ask the user.

3. **Read all target files** before making any edits. At minimum read:
   - `README.md`
   - `package-addon/action.yaml`
   - `.github/workflows/publish-image-godot-infra.yaml`
   - `.github/workflows/publish-image-compile-godot-export-template.yaml`
   - `.github/workflows/publish-image-export-godot-project-preset.yaml`
   - The 6 Docker image action files listed in Stage 1

4. **Create a new branch** named `chore/godot/upgrade` off the current branch (typically `main`)
   before making any edits. Do not commit the upgrade directly to `main`.

### 2. Stage 1 — Boilerplate version bump

Replace all `major.minor` version references from old to new. Let `OLD` = old major.minor (e.g.
`4.6`) and `NEW` = new major.minor (e.g. `4.7`). Let `OLD_TAG` = current release tag (e.g. `v4`)
and `NEW_TAG` = new release tag (e.g. `v5`).

1. **Docker image tags** — In each of these 6 files, replace `godot-v<OLD>-` with `godot-v<NEW>-`:
   - `compile-godot-export-template/macos/action.yml`
   - `compile-godot-export-template/web/action.yml`
   - `compile-godot-export-template/windows/action.yml`
   - `export-godot-project-preset/macos/action.yml`
   - `export-godot-project-preset/web/action.yml`
   - `export-godot-project-preset/windows/action.yml`

2. **`GODOT_MAJOR_MINOR_VERSION`** — In `.github/workflows/publish-image-godot-infra.yaml`,
   update the env var value from `<OLD>` to `<NEW>`.

3. **`package-addon/action.yaml`** — Update the `godot-editor-version` input default from the
   current value (e.g. `"v4.6.1-stable"` or `"v4.6-stable"`) to `"v<NEW>-stable"`.

4. **`README.md`** — Three types of edits:
   - **Badge (line 1):** Replace `godot-v<OLD_FULL>-478cbf` with `godot-v<NEW>.0-478cbf`
   - **Version table:** Add a new `main` entry and demote the previous one:
     ```
     - `<NEW_TAG>` (`main`): `v<NEW>.0`
     - `<OLD_TAG>`: `v<OLD_FULL>`
     ```
     where `OLD_FULL` is the complete old version (e.g. `4.6.1`).
   - **Docker build/run examples:** Replace ALL occurrences of image tags containing
     `godot-v<OLD>-` with `godot-v<NEW>-` throughout the file (in both `compile-godot-export-template`
     and `export-godot-project-preset` sections, including local build and local run commands).

### 3. Stage 2 — Dependency version updates

Two workflow files contain dependency version defaults:

- `.github/workflows/publish-image-compile-godot-export-template.yaml` — the `outputs` block of
  the `inputs` job. Locate it by shape, not line number: every entry is
  `<key>: ${{ inputs.<key> || '<default>' }}` with a source URL in a trailing comment, which is what
  distinguishes it from the bare `inputs:` declarations above it.
- `.github/workflows/publish-image-export-godot-project-preset.yaml` — the `RUST_VERSION` env var
  (has a fallback default used when the caller doesn't pass `rust-version`).

For each dependency, **fetch the upstream source** to determine the correct new version. Each
default has a comment with a source URL — **follow that URL pattern** to find the equivalent file
on the new Godot version's branch. The upstream repos are:

- `godotengine/build-containers` — check the **`<NEW>` release branch**, not `main`. Fetch via:
  `gh api repos/godotengine/build-containers/contents/Dockerfile.osx?ref=<NEW>` (likewise `.web`,
  `.windows`)
- `godotengine/godot-build-scripts` — check the **`<NEW>` release branch**, not `main`. Fetch via:
  `gh api repos/godotengine/godot-build-scripts/contents/build.sh?ref=<NEW>`
- `godotengine/godot` — check the `<NEW>-stable` branch (e.g. `4.7-stable`). Fetch via:
  `gh api repos/godotengine/godot/contents/misc/scripts/install_d3d12_sdk_windows.py?ref=<NEW>-stable`

**Important:** The source URL in each comment is the ground truth for where to look. If a
dependency's source has moved between versions, follow whatever URL is currently documented.

> [!IMPORTANT]
> **Read from the `<NEW>` release branch, never from `main`.** Upstream cuts a release branch and
> then immediately moves `main` on to the *next* dev cycle. During the 4.7 upgrade, `main` already
> carried 4.8-dev values (Emscripten 6.0.1, llvm-mingw 20260616) and had **deleted `Dockerfile.osx`
> entirely** — following it would have pinned versions Godot 4.7 was never built with, and the
> failure is silent because every value still looks plausible.
>
> List branches with `gh api repos/godotengine/build-containers/branches --paginate --jq '.[].name'`
> — **without `--paginate` the release branch may not appear at all.**
>
> Pin the comment URLs to the resolved commit SHA, not the branch name, so a later reader can tell
> exactly what was current.

> [!NOTE]
> A freshly-cut release branch is often identical to the previous one. It is normal and correct for
> most versions to be unchanged — during the 4.7 upgrade only three values actually moved. Do not
> manufacture bumps to make the diff look substantial.

#### Dependencies to update

**Cross-platform:**
- `godot-angle-static-version` — source varies; follow the existing comment URL

**macOS:**
- `clang-version` — from `build-containers` `Dockerfile.osx` (`LLVM_VERSION` arg). **Only the
  major version matters**: `thirdparty/osxcross/build_clang.sh` maps each major to a hardcoded
  `apple/llvm-project` stable branch. If the new major has no `case` entry there, the build fails
  after osxcross has already compiled. Check the mapping by hand before pinning a new major.
- `moltenvk-version` — from `godot-build-scripts` `build.sh`
- `osx-version` — from `build-containers` `Dockerfile.osx` (`OSX_SDK` arg)
- `osx-version-min` — from MoltenVK runtime requirements (check the MoltenVK docs for the
  version found above)
  - **If `osx-version` changes, the macOS SDK tarball must be regenerated.** The build asserts on
    `tarballs/MacOSX<osx-version>.sdk.tar.gz`, which is not in git; re-run the
    `package-macos-sdk.yml` workflow. A stale tarball fails ~40 minutes into the build.
- `osxcross-sdk` — from `godot-build-scripts` `build-macos/build.sh` (format: `darwin<XX.Y>`).
  The Darwin major is always the macOS major minus one (macOS `26.1` → `darwin25.1`); bumping
  `osx-version` without this is a classic miss.
- `rust-version` — use the latest stable Rust version
- `xcode-version` — from `build-containers` `Dockerfile.osx`

**Web:**
- `emscripten-version` — from `build-containers` `Dockerfile.web`

**Windows:**
- `mingw-llvm-version` — from `build-containers` `Dockerfile.windows` (**note:** may be pinned
  to an older version due to known ANGLE compilation issues; check if the FIXME comment still
  applies before updating)
- `godot-nir-static-version` — from `godot` `misc/scripts/install_d3d12_sdk_windows.py`
- `pix-version` — from `godot` `misc/scripts/install_d3d12_sdk_windows.py`
- `agility-version` — from `godot` `misc/scripts/install_d3d12_sdk_windows.py`

#### Applying updates

1. Update each default value in the compile workflow file.
2. Update the source URL comments to reference the new commit/branch.
3. Update the `RUST_VERSION` fallback default in `publish-image-export-godot-project-preset.yaml`.
4. **Mirror build arg changes to `README.md`** — update the `--build-arg` values in all Docker
   build example commands to match the new defaults (both `compile-godot-export-template` and
   `export-godot-project-preset` sections, including the `RUST_VERSION` build arg).

#### Also check

- **Runner OS versions** — In `.github/workflows/package-macos-sdk.yml` and
  `package-moltenvk-sdk.yml`, check if the `os` input default needs updating (e.g. `macos-26`).
  Match to the Xcode version's required macOS.
- **`thirdparty/osxcross` submodule** — Check if `godotengine/build-containers` uses a newer
  osxcross commit. If so, update the submodule:
  `cd thirdparty/osxcross && git fetch origin && git checkout <NEW_COMMIT> && cd ../..`

### 4. Stage 3 — Internal action version references

Search all `.yml` and `.yaml` files for `coffeebeats/godot-infra/` followed by `@<OLD_TAG>` and
replace with `@<NEW_TAG>`. Use `grep` to find all occurrences first, then apply edits.

Files that typically contain these references:
- `.github/actions/check-code-formatting/action.yml`
- `.github/actions/install-godot-source/action.yml`
- `check-godot-project/action.yaml`
- `compile-godot-export-template/action.yml`
- `export-godot-project-preset/action.yaml`
- `package-addon/action.yaml`
- `publish-project-itchio/action.yml`

### 5. Verify

Run `git diff --stat` to confirm changes look reasonable. Expect roughly:
- 6 Docker image action files (1 change each)
- 2-3 workflow files (version env var, compile dependency defaults, export RUST_VERSION)
- `package-addon/action.yaml`
- `README.md` (many lines — badge, table, Docker examples)
- ~5-7 files for internal action refs
- Possibly: macOS SDK workflow files, `thirdparty/osxcross` submodule

Present the diff summary to the user for review before committing.

### 6. Commit

Create a single commit on the `chore/godot/upgrade` branch with the message:
```
chore!: upgrade to Godot `v<NEW>-stable`
```

where `<NEW>` is the major.minor version (e.g. `4.7`, not `4.7.0`). The `!` indicates a breaking
change (new major release tag).

## Key reference files

- `README.md` — badge, version table, Docker build/run examples
- `package-addon/action.yaml` — `godot-editor-version` default
- `.github/workflows/publish-image-godot-infra.yaml` — `GODOT_MAJOR_MINOR_VERSION`
- `.github/workflows/publish-image-compile-godot-export-template.yaml` — compile dependency versions
- `.github/workflows/publish-image-export-godot-project-preset.yaml` — `RUST_VERSION` default
- `compile-godot-export-template/{macos,web,windows}/action.yml` — Docker image tags
- `export-godot-project-preset/{macos,web,windows}/action.yml` — Docker image tags
- `thirdparty/osxcross` — osxcross submodule (may need updating for macOS builds)

## Prior major upgrades

- `v4.4` → `v4.5` (`v2` → `v3`): commit `c7d5142` (PR #445)
- `v4.5` → `v4.6` (`v3` → `v4`): commits `f11ad6b` + `4d14ef4` + `65e82c1` (PR #495)