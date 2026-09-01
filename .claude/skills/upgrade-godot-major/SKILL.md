---
name: upgrade-godot-major
description: Upgrade the project to a new Godot minor release (e.g. 4.6 to 4.7). Updates boilerplate versions, researches upstream dependency versions, and bumps internal action references.
disable-model-invocation: true
argument-hint: "<major.minor>"
---

Upgrade this project to Godot version `$ARGUMENTS`. This is a **major version upgrade** affecting
many files. It has four stages — boilerplate version bump, dependency version updates (researched
from upstream), internal action reference bumps, and build validation — wrapped by a prepare step
before and review/commit steps after. Work the sections below in order.

The single biggest risk in this upgrade is that the images stop building. Stage 4 is not optional
polish — a bad version pin produces a green diff and a red build, and CI's only fallback publishes
real image tags to ghcr.io, so a broken pin discovered there is already public.

## Steps

### Validate and prepare

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

### Stage 1 — Boilerplate version bump

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

### Stage 2 — Dependency version updates

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

#### Compare upstream build configuration and docs

Version pins only catch dependencies we *already* know about. A minor release can also add a new
optional dependency, or change how an existing one is linked. Godot's SCons scripts **warn and
disable** rather than fail, so a dependency we do not supply produces a green build and a silently
degraded export template. Nothing else in this skill catches that — not the pins, not a successful
`docker build`, not a smoke test.

Run three diffs for `<OLD>` → `<NEW>`.

> [!IMPORTANT]
> Fetch with `curl -f`. Without it curl exits 0 on a 404 and writes the body `404: Not Found` into
> the stream — so when a path moves between releases, **two 404s diff clean** and this check reports
> "nothing changed" on precisely the release that restructured things. Define once, use below:
>
> ```bash
> fetch() { curl -fsSL "$1" || echo "MISSING: $1" >&2; }
> ```
>
> A `MISSING:` line means the path moved; find where it went before trusting that diff.

1. **Upstream build scripts** — what Godot's own official builds pass to SCons:
   ```bash
   for f in build.sh build-macos/build.sh build-windows/build.sh build-web/build.sh; do
     echo "### $f"
     diff -u \
       <(fetch "https://raw.githubusercontent.com/godotengine/godot-build-scripts/<OLD>/$f") \
       <(fetch "https://raw.githubusercontent.com/godotengine/godot-build-scripts/<NEW>/$f")
   done
   ```
   The signal is new `deps/*` downloads and new entries in `OPTIONS=`. Compare the resulting
   `OPTIONS` line for each platform against our `ENV SCONSFLAGS` in
   `compile-godot-export-template/<platform>/Dockerfile`. **Anything upstream passes that we do not
   is a capability we silently ship without.**

2. **SCons option definitions** — whether a new option defaults to on, and what happens when its
   dependency is absent. Diff `SConstruct` and `platform/{macos,web,windows}/detect.py` between
   `<OLD>-stable` and `<NEW>-stable` in `godotengine/godot`. Look for:

   ```python
   BoolVariable("winrt", "Use WinRT API (OneCore TTS support).", True)   # on by default
   ...
   print_warning("... disable this driver by compiling with `winrt=no` explicitly.")
   env["winrt"] = False                                                   # silently degrades
   ```

   That pairing — default `True` plus a warn-and-disable fallback — is the shape to hunt for.

3. **Docs** — `godotengine/godot-docs` keeps a branch per minor version:
   ```bash
   for f in engine_details/development/compiling/compiling_for_{macos,web,windows}.rst \
            tutorials/export/exporting_for_{macos,web,windows}.rst; do
     echo "### $f"
     diff -u <(fetch "https://raw.githubusercontent.com/godotengine/godot-docs/<OLD>/$f") \
             <(fetch "https://raw.githubusercontent.com/godotengine/godot-docs/<NEW>/$f")
   done
   ```
   Read the **Requirements** section of each compiling page for bumped minimums (Python, SCons,
   compiler), and any new `Compiling with X support` section.

Classify every finding as exactly one of:

- **already covered** — we pass the flag / ship the dependency already;
- **needs work** — add a pin, install the dependency, extend `SCONSFLAGS`;
- **deliberately skipped** — then pass the explicit `<option>=no` SCons flag, so the build is
  quiet by choice rather than by accident.

> [!NOTE]
> This step was added *after* the 4.7 upgrade because that upgrade missed two things while every
> version pin was correct:
>
> - **AccessKit.** 4.6 linked it dynamically, so the option *looked* enabled with no SDK present —
>   but the library still had to ship next to the binary, and ours never did. 4.7 removed that path:
>   absent `accesskit_sdk_path`, it warns and sets `accesskit = False`. So this is **not** a
>   regression — screen reader support was missing under both — 4.7 is just where the build stopped
>   pretending otherwise. Upstream uses `godot-accesskit-c-static` with
>   `accesskit_sdk_path=/root/accesskit/accesskit-c`. Tracked as #516.
> - **WinRT.** New in 4.7 and on by default (OneCore TTS, HDR monitoring, emoji picker). Under
>   MinGW it needs headers from `godotengine/winrt-mingw` at `winrt_path=`; absent, it warns and
>   sets `winrt = False`. Tracked as #566.
>
> Both produced successful image builds and passing smoke tests. Both are currently *deferred*
> rather than *deliberately skipped* — neither `accesskit=no` nor `winrt=no` is passed, so the
> builds are still quiet by accident. Closing either issue means adding the dependency or adding
> the explicit flag.

#### Also check

- **Runner OS versions** — In `.github/workflows/package-macos-sdk.yml` and
  `package-moltenvk-sdk.yml`, check if the `os` input default needs updating (e.g. `macos-26`).
  Match to the Xcode version's required macOS.
- **`thirdparty/osxcross` submodule** — Check if `godotengine/build-containers` uses a newer
  osxcross commit. If so, update the submodule:
  `cd thirdparty/osxcross && git fetch origin && git checkout <NEW_COMMIT> && cd ../..`

### Stage 3 — Internal action version references

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

### Review the diff

Run `git diff --stat` to confirm changes look reasonable. Expect roughly:
- 6 Docker image action files (1 change each)
- 2-3 workflow files (version env var, compile dependency defaults, export RUST_VERSION)
- `package-addon/action.yaml`
- `README.md` (many lines — badge, table, Docker examples)
- ~5-7 files for internal action refs
- Possibly: macOS SDK workflow files, `thirdparty/osxcross` submodule

Present the diff summary to the user for review before validating.

### Stage 4 — Validate that the images still build

Validation is two tiers. **Always run Tier 1. Run Tier 2 for the images whose pins actually
changed.**

#### Tier 1 — Static checks (always; ~1 minute)

Two checks. Both are a couple of shell commands; neither needs a script.

1. **No stale version strings anywhere.** After Stage 3, nothing should still name the old version:

   ```bash
   git grep -n "godot-v<OLD>"             -- '*.md' '*.yml' '*.yaml'
   git grep -n "v<OLD>-stable"            -- '*.md' '*.yml' '*.yaml'
   git grep -n "godot-infra/.*@<OLD_TAG>" -- '*.yml' '*.yaml'
   ```

   `git grep`, not `grep -r`: it searches tracked files only, so it skips the vendored trees under
   `thirdparty/`, whose version strings are upstream's business rather than ours. **Each command
   should print nothing** — `git grep` exits 1 when there is no match, so a non-zero exit here is
   the pass, not a failure. Every hit is a missed edit.

   The README version table is not an exception to sift through: it records history as `` `v4.6.3` ``,
   which none of these patterns match. These values change only during this upgrade flow, so a scan
   here is worth more than any standing CI check.

2. **Every pin agrees with its own source link.** Each default in the compile workflow's `outputs`
   block carries a `# https://github.com/<repo>/blob/<sha>/<path>#L<n>` comment. After re-pinning,
   fetch each one and confirm the value really is on that line:

   ```bash
   curl -fsSL "https://raw.githubusercontent.com/<repo>/<sha>/<path>" | sed -n '<n>p'
   ```

   The printed line must contain the pinned value. Keep the `-f`: without it a moved path yields
   exit 0 and the body `404: Not Found`, so `sed` prints nothing and an empty result reads as
   "no problem here". **The line number is the fragile part** — it
   drifts between releases (during the 4.7 upgrade `build.sh#L184` became `#L229`), and a stale
   number silently points the next reader at a neighbouring variable. Search by the anchor symbol
   (`ENV APPLE_SDKV=`, `mesa_version =`, `LLVM_MINGW_VERSION=`), then write the line number the
   anchor is actually on.

   Two values need care: `godot-angle-static-version` appears URL-encoded upstream
   (`chromium%2F7578` for `chromium/7578`), and `rust-version` / `osx-version-min` have **no
   upstream link at all** — the former is "latest stable", the latter is read from the MoltenVK
   runtime requirements for the pinned MoltenVK version.

#### Tier 2 — Real image builds (for affected images)

**Use the commands in `README.md` under "Building images locally" verbatim.** They are the
documented, user-facing path and the single source of truth for local builds — do not re-derive
the build args or write a wrapper script. Running them here doubles as a check that the
documented commands still work.

Only rebuild what the changed defaults can actually break:

| Changed default | Rebuild |
| --- | --- |
| `godot-angle-static-version` | `compile/macos`, `compile/windows` |
| `clang-version`, `osx-version`, `osx-version-min`, `osxcross-sdk` | `compile/macos` |
| `emscripten-version` | `compile/web` |
| `mingw-llvm-version`, `godot-nir-static-version`, `pix-version`, `agility-version` | `compile/windows` |
| `rust-version` (export workflow) | `export/macos` |

> [!IMPORTANT]
> **Build one image at a time, platform by platform.** Each build saturates CPU, disk, and network;
> running several at once makes all of them slower and the logs impossible to read. Start the next
> build only after the previous one has finished.

For each affected image, in turn:

1. Run the README command with `run_in_background: true`, redirecting output to a log:
   ```bash
   docker build ... compile-godot-export-template/windows > .build-logs/compile-windows.log 2>&1
   ```
   (`.build-logs/` is gitignored; create it first.)
2. Wait for it to finish — poll the log rather than blocking, and do not start another build.
3. Smoke-test the toolchain inside the image. A build can succeed while a copied-in SDK is empty,
   so check the tools actually run and report the expected version:

   | Image | Smoke test |
   | --- | --- |
   | `compile/macos` | `"$OSXCROSS_ROOT/target/bin/"*-apple-darwin*-clang --version`, `test -d /opt/angle`, `test -d "$VULKAN_SDK_ROOT/macOS/lib/MoltenVK.xcframework"` |
   | `compile/web` | `emcc --version` (must match `emscripten-version`), `scons --version` |
   | `compile/windows` | `clang --version`, `test -d /opt/mesa /opt/agility /opt/pix /opt/angle`, `scons --version` |
   | `export/macos` | `rcodesign --version` |
   | `export/windows` | `command -v osslsigncode` |

   ```bash
   docker run --rm --entrypoint /bin/bash <tag> -c 'emcc --version && scons --version'
   ```

Measured cold-cache times on an M-series Mac building `linux/amd64` under emulation (4.7 upgrade):

| Image | Time |
| --- | --- |
| `export/windows` | 6s |
| `export/web` | 2 min |
| `compile/web` | 2 min |
| `compile/windows` | 7 min |
| `export/macos` | 8 min |
| `compile/macos` | **2h44m** |

`compile/macos` dominates: it builds Apple clang from source, then compiler_rt, then osxcross. Its
log stays byte-identical for long stretches while clang compiles — that is silence, not a hang.

#### Before building `compile/macos`

It consumes two build contexts that are **not in git**: the macOS SDK tarball
(`thirdparty/osxcross/tarballs/MacOSX<osx-version>.sdk.tar.gz`) and the MoltenVK framework. The
README notes this; CI produces them via `package-macos-sdk.yml` and `package-moltenvk-sdk.yml`.

**If `osx-version` changed, the existing tarball is now the wrong version** and the build asserts on
it after osxcross has already been compiled. Check before starting:

```bash
ls thirdparty/osxcross/tarballs/*.sdk.tar.gz
test -d thirdparty/moltenvk/macOS/lib/MoltenVK.xcframework
```

> [!WARNING]
> The CI fallback is **not** a dry run. `publish-image-godot-infra.yaml` hardcodes `push: true`, so
> dispatching it publishes real tags to ghcr.io before the change is merged. Prefer local builds;
> only fall back to CI with the user's explicit agreement.

> [!NOTE]
> `compile/windows` can never be built natively on arm64 — its llvm-mingw toolchain is published
> only as an `x86_64` Linux tarball — so it is always emulated on Apple Silicon. Emulation is
> cheaper than it sounds (see the times above); prefer measuring over assuming.

#### Reporting

State plainly which images were actually built and which were not, and why. An unbuilt image is an
unvalidated one — do not describe the upgrade as verified on the strength of Tier 1 alone.

### Commit

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
- `README.md` §"Building images locally" — the source of truth for local `docker build` commands

## Prior major upgrades

- `v4.4` → `v4.5` (`v2` → `v3`): commit `c7d5142` (PR #445)
- `v4.5` → `v4.6` (`v3` → `v4`): commits `f11ad6b` + `4d14ef4` + `65e82c1` (PR #495)