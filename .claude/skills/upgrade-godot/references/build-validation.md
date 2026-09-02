# Build validation

Read by `upgrade-godot` on the **minor** route only, after the diff has been reviewed. A patch
upgrade changes no image inputs, so its verification is the three-line diff assertion in `SKILL.md`.

Validation is three tiers before the merge and one check after it. **Always run Tier 1. Run
Tier 2 for the images whose pins actually changed, and Tier 3 for the platforms those images
serve.** Then, once CI has published the images, run the post-publish check against the published
tags; an image that builds and passes locally can still ship broken.

## Tier 1 — Static checks (always; ~1 minute)

Two checks. Both are a couple of shell commands; neither needs a script.

1. **No stale version strings anywhere.** After the reference sweep, nothing should still name
   the old version:

   ```bash
   SRC=(-- '*.md' '*.yml' '*.yaml' '*.godot-version' ':!CHANGELOG.md' ':!.claude')

   git grep -n  "godot-v<OLD>"                         "${SRC[@]}"
   git grep -nE "v<OLD>(\.[0-9]+)?-stable"             "${SRC[@]}"
   git grep -n  "godot-infra/[a-z-]*@<OLD_TAG>"        "${SRC[@]}"
   ```

   `git grep`, not `grep -r`: it searches tracked files only, so it skips the vendored trees under
   `thirdparty/`, whose version strings are upstream's business rather than ours. **Each command
   should print nothing** — `git grep` exits 1 when there is no match, so a non-zero exit here is
   the pass, not a failure. Every hit is a missed edit.

   `CHANGELOG.md` and `.claude/` are excluded because both name old versions on purpose — one is
   release history, the other is this skill's own worked examples. Without the exclusion the second
   pattern returns six lines every time and the check stops meaning anything. The README version
   table needs no exclusion: it records history as `` `v4.6.3` ``, which matches nothing here.

   All three patterns take `${SRC[@]}`, so all three cover `*.md`. The third was scoped to
   `'*.yml' '*.yaml'` — correct until `e2758f0` (#530) moved internal action references to local
   paths, after which it matched nothing and passed while `README.md` still said `@v4`. It shared
   the blind spot of the sweep it exists to backstop, and a check that can only pass is worse than
   no check.

   The `-stable` pattern allows an optional patch component because `package-addon` and
   `tests/project/.godot-version` pin the full version (`v4.6.3-stable`); matching only
   `v<OLD>-stable` would walk straight past a missed edit there. These values change only during this upgrade flow, so a scan here is worth more than any
   standing CI check.

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

## Tier 2 — Real image builds (for affected images)

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

`export/web` and `export/windows` are absent by design, not by omission: only
`export-godot-project-preset/macos/Dockerfile` carries a versioned `ARG`, so no dependency change
can reach the other two. They appear in the tables below because the timings are measured and the
smoke tests still apply on the rare occasion something else forces a rebuild.

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
   so check the tools actually run and report the expected version, **and that the compilers
   compile something**. `--version` is not enough: the macOS image CI published on 2026-09-01
   printed its version fine and then died with `Illegal instruction` on every source file.

   | Image | Smoke test |
   | --- | --- |
   | `compile/macos` | `for a in x86_64 arm64; do echo 'int main(){}' \| "$OSXCROSS_ROOT"/target/bin/$a-apple-darwin*-clang++ -x c++ -c - -o /dev/null; done`, `test -d /opt/angle`, `test -d "$VULKAN_SDK_ROOT/macOS/lib/MoltenVK.xcframework"` |
   | `compile/web` | `emcc --version` (must match `emscripten-version`), `echo 'int main(){}' \| emcc -x c++ -c - -o /dev/null`, `scons --version` |
   | `compile/windows` | `echo 'int main(){}' \| x86_64-w64-mingw32-clang++ -x c++ -c - -o /dev/null`, `test -d /opt/mesa /opt/agility /opt/pix /opt/angle`, `scons --version` |
   | `export/macos` | `rcodesign --version` |
   | `export/windows` | `command -v osslsigncode` |

   ```bash
   docker run --rm --platform linux/amd64 --entrypoint /bin/bash <tag> -c 'emcc --version && scons --version'
   ```

   Pass `--platform linux/amd64` on Apple Silicon so the image runs the way CI runs it.

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

## Before building `compile/macos`

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

## Tier 3 — Compile and export a project (for affected platforms)

A toolchain that installs and answers `--version` has still not compiled Godot, and a template that
compiles has still not been fed to the editor. `README.md` §"Testing the toolchain end to end" runs
both halves the way the actions run them in CI, against the sample project in `tests/project`.
**Use those commands verbatim** with `REGISTRY=""` so they pick up the images Tier 2 just built,
for every platform whose compile or export image was rebuilt.

Each platform is one compile (two for macOS, which is universal) and one export. The compiles
run one at a time for the same reason the image builds do, and the release profile's link-time
optimization makes them the slow part; the README carries measured times. Log them under
`.build-logs/` like the image builds.

The result is pass or fail per platform; there is nothing to interpret. A compile that dies within
seconds of `scons: Building targets ...` is the toolchain, not Godot.

## After CI publishes

The merge is not the end of validation. `publish-image-godot-infra.yaml` rebuilds every image on
GitHub's runners, and the result can differ from the local build of the same Dockerfile: the
`godot-v4.7-macos` image CI published on 2026-09-01 was compiled with `-march=native` on a runner
whose CPU had instructions that other runners and local emulation lack, so it crashed with
`Illegal instruction` on every compile on some runners while the same image passed on others. A
local build under emulation could never have shown it; the published tag reproduced it in seconds.

Once release-please has cut the tag and the publish workflow has pushed the images, run Tier 2's
smoke tests and Tier 3 for **all three platforms** against the published tags,
`REGISTRY="ghcr.io/coffeebeats/"` in the README commands. `upgrade-godot-chain` refuses to start
its first downstream stage until this has passed, because a failure here is a `godot-infra` fix and
every downstream bump would inherit it.

## Reporting

State plainly which images were actually built and which were not, which platforms went through
Tier 3, and whether the post-publish check has run. An unbuilt image is an unvalidated one, and an
image that only passed locally is an unpublished one — do not describe the upgrade as verified on
the strength of Tier 1 alone, or as finished before the published tags have passed.
