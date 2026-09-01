# Dependency version updates

Read by `upgrade-godot` on the **minor** route only. A patch upgrade changes no dependency pins.

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
- `godotengine/godot` — check the `<NEW_FULL>-stable` **tag** (e.g. `4.7.2-stable`), which is the
  release being pinned. The other two repos use a per-minor *branch*; this one does not. Fetch via:
  `gh api repos/godotengine/godot/contents/misc/scripts/install_d3d12_sdk_windows.py?ref=<NEW_FULL>-stable`

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

## Dependencies to update

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

## Applying updates

1. Update each default value in the compile workflow file.
2. Update the source URL comments to reference the new commit/branch.
3. Update the `RUST_VERSION` fallback default in `publish-image-export-godot-project-preset.yaml`.
4. **Mirror build arg changes to `README.md`** — update the `--build-arg` values in all Docker
   build example commands to match the new defaults (both `compile-godot-export-template` and
   `export-godot-project-preset` sections, including the `RUST_VERSION` build arg).

## Compare upstream build configuration and docs

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
   `<OLD_FULL>-stable` and `<NEW_FULL>-stable` in `godotengine/godot`. Look for:

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

## Also check

- **Runner OS versions** — In `.github/workflows/package-macos-sdk.yml` and
  `package-moltenvk-sdk.yml`, check if the `os` input default needs updating (e.g. `macos-26`).
  Match to the Xcode version's required macOS.
- **`thirdparty/osxcross` submodule** — Check if `godotengine/build-containers` uses a newer
  osxcross commit. If so, update the submodule:
  `cd thirdparty/osxcross && git fetch origin && git checkout <NEW_COMMIT> && cd ../..`
