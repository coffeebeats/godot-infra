# **godot-infra** ![GitHub release (with filter)](https://img.shields.io/github/v/release/coffeebeats/godot-infra) ![GitHub](https://img.shields.io/github/license/coffeebeats/godot-infra) [![Build Status](https://img.shields.io/github/actions/workflow/status/coffeebeats/godot-infra/publish-image-godot-infra.yaml?branch=main)](https://github.com/coffeebeats/godot-infra/actions?query=branch%3Amain+workflow%3Apublish-image-godot-infra) ![Static Badge](https://img.shields.io/badge/godot-4.7-478cbf)

A repository for Godot build and release infrastructure using [@coffeebeats](https://github.com/coffeebeats?tab=repositories)' tools.

## **How it works**

This repository publishes reusable GitHub workflows and actions for checking, compiling, exporting, and releasing Godot projects and addons, plus the Docker toolchain images they run in. See [Example usage](#example-usage) below.

### Supported platforms

Currently, `godot-infra` supports targeting three platforms:

- `macos`
- `web`
- `windows`

### Supported Godot versions

Toolchain images are published per Godot minor version, tagged `godot-v<major.minor>-<platform>`, and selected at run time from the consuming project's `.godot-version` pin. A `godot-infra` release is therefore independent of the Godot version; its major only changes when a workflow or action interface changes.

[`godot-versions.txt`](./godot-versions.txt) lists the minors with published images. The last line is the one `main` currently builds and tests against; images for earlier minors are frozen and never deleted, so an archived project keeps working at its pin.

> [!NOTE]
> Although it's recommended to [pin actions to the full-length commit SHA](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions), the following release tags define stable, tested versions of this project.

| `godot-infra` | Godot minors |
| --- | --- |
| `v6` (`main`) | 4.7 |
| `v5` | 4.7 |
| `v4` | 4.6 |
| `v3` | 4.5 |
| `v2` | 4.4 |
| `v1` | 4.3 |
| `v0` | 4.2 |

## **Getting started**

The `godot-infra` repository does not need to be installed. Call its reusable workflows from your repository's workflows, or use its actions directly.

### **Example usage**

#### **Reusable workflows**

A game repository's export pipeline is one call per workflow file. Secrets (encryption key, codesigning, itch.io) stay in the game's repository and reach the workflow through `secrets: inherit`; each workflow's header comment lists the secret names and the permissions the caller must grant.

```yaml
name: "🎮 Export: Godot project"

on:
  workflow_dispatch:
    inputs:
      platform: { type: string, required: true }
      arch: { type: string, required: true }

permissions:
  contents: read

jobs:
  export:
    uses: coffeebeats/godot-infra/.github/workflows/export-project.yaml@v6
    secrets: inherit
    with:
      platform: ${{ inputs.platform }}
      arch: ${{ inputs.arch }}
      storefront: unknown
      profile: release
```

Compose a game's release pipeline in the game repository rather than calling a single workflow that does everything. The build matrix stays readable YAML, `release-please` keeps its own pin and configuration, and the chain is shallow enough to leave room under GitHub's four-level nesting limit.

```yaml
name: "🚀 Release: Project version"

on:
  push:
    branches: [main]

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest

    outputs:
      release-created: ${{ steps.release.outputs.releases_created }}
      release-tag: ${{ steps.release.outputs.tag_name }}

    steps:
      # The repository's existing 'release-please' configuration.
      - uses: googleapis/release-please-action@v4
        id: release

  publish:
    needs: ["release-please"]
    if: needs.release-please.outputs.release-created == 'true'

    strategy:
      matrix:
        include:
          - { arch: x86_64, platform: windows, storefront: unknown }
          # ... one entry per shipped target.

    uses: coffeebeats/godot-infra/.github/workflows/publish-game.yaml@v6
    secrets: inherit
    with:
      arch: ${{ matrix.arch }}
      platform: ${{ matrix.platform }}
      storefront: ${{ matrix.storefront }}
      profile: release
      ref: ${{ needs.release-please.outputs.release-tag }}

  upload:
    needs: ["release-please", "publish"]
    if: needs.release-please.outputs.release-created == 'true'

    runs-on: ubuntu-latest

    steps:
      - uses: coffeebeats/godot-infra/actions/attach-release-assets@v6
        with:
          tag: ${{ needs.release-please.outputs.release-tag }}
```

Available workflows: `check-project.yaml` (games and addons), `export-project.yaml`, `publish-game.yaml`, `compile-editor.yaml` (games), `release-addon.yaml` (addons). `check-project.yaml` gates each of its jobs on what the repository carries, so an addon repository skips the Python, image and translation work rather than needing a workflow of its own.

A caller declares its own aggregate status job. A job defined inside a reusable workflow reports as `<caller-job> / <job>`, which a branch ruleset cannot require, so the job whose name the ruleset names has to live in the calling repository.

```yaml
jobs:
  check:
    uses: coffeebeats/godot-infra/.github/workflows/check-project.yaml@v6
    secrets: inherit

  branch_protection:
    needs: ["check"]
    if: ${{ always() }}
    runs-on: ubuntu-latest
    timeout-minutes: 1
    steps:
      - if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')
        run: exit 1
```

#### **Actions**

Every action under [`actions/`](./actions) can also be used on its own:

```yaml
- uses: "coffeebeats/godot-infra/actions/compile-godot-export-template@v6"
  with:
    # See the action implementation for available inputs.
```

## **Template repositories**

The [@coffeebeats](https://github.com/coffeebeats) user has two template repositories for Godot projects:

- [godot-project-template](https://github.com/coffeebeats/godot-project-template)
- [godot-plugin-template](https://github.com/coffeebeats/godot-plugin-template)

The [instantiate_template_repository.py](./scripts/instantiate_template_repository.py) script creates a repository from either one, with the recommended settings:

```sh
uv run scripts/instantiate_template_repository.py \
  --name <NEW REPO NAME> \
  --template <TEMPLATE REPO NAME> \
  --description "A new Godot 4+ project."
```

A run creates the repository, rewrites the generated contents for their new home, applies every repository setting and both branch rule sets, and reports what still needs attention. By default it seeds `release-please` at `v0.1.0`; `--no-release` removes the release workflow and configuration as well as skipping the tag.

Pass `--dry-run` first; it prints every mutating call with its payload and issues none. `--existing` applies settings alone, which resumes a failed run and re-converges a repository created before a setting existed. It touches no content and never changes visibility.

`--name` and `--template` each take `owner/name`, or a bare name under a default owner — `@coffeebeats` for the template, the authenticated user for the new repository. `--branch` takes a branch or a commit. The default branch uses GitHub's template generation; a pinned or non-default ref is cloned from the source and pushed as a new initial commit, so the pin is honored even though template generation squashes history.

| Option | Purpose |
| --- | --- |
| `--public` | Create a public repository. The script enables secret and code scanning on public repositories only, since both need Advanced Security on a private one. |
| `--allow-action PATTERN` | Permit a third-party action. Repeatable and additive; it never narrows an allow-list the repository already has. |
| `--allow-direct-push` | Drop the pull-request and status-check rules, for a repository that commits straight to `main`. Force-pushing stays blocked. |
| `--no-release` | Skip `release-please` seeding and the initial tag. |
| `--secret NAME` | Set a repository secret from the environment variable of the same name. Repeatable; for many at once, `gh secret set -f` is simpler. |
| `--workflow-permissions` | The default `GITHUB_TOKEN` permissions (default `read`). |

The script deliberately leaves SHA pinning off. Dependent repositories consume godot-infra's actions by floating major tag, so enforcing it here would churn every dependent on every release. Workflows pin third-party actions by hand instead.

## **Development**

### Setup

[Install `uv`](https://docs.astral.sh/uv/getting-started/installation/), then run `uv sync`. That installs the Python tooling from [`uv.lock`](./uv.lock), and downloads the interpreter named by [`.python-version`](./.python-version) if the machine has none. Invoke each tool as `uv run <tool>`.

#### System dependencies

Installed by hand, and each has to be on the `PATH` of the shell that runs the scripts: `git`, `gh` for [`scripts/instantiate_template_repository.py`](./scripts/instantiate_template_repository.py), and Docker to build images locally (see below). Godot is not among them, since the actions bring their own.

### Building images locally

During development, you may want to build the infrastructure images locally rather than relying on CI/CD workflows. This section provides commands for building images on your local machine.

#### `compile-godot-export-template`

Dependency versions are taken from the defaults defined in the [publish-image-compile-godot-export-template.yaml](.github/workflows/publish-image-compile-godot-export-template.yaml) workflow. Substitute the Godot minor you are building for in the image tag.

<details>
<summary><strong>macOS</strong></summary>

> **NOTE:** The macOS image requires the `osxcross` and `moltenvk` build contexts; these dependencies are packaged by the [package-macos-sdk.yml](.github/workflows/package-macos-sdk.yml) and [package-moltenvk-sdk.yml](.github/workflows/package-moltenvk-sdk.yml) workflows. Run these via GitHub, download and extract the resulting artifacts, then place their contents in the expected directories.

```sh
docker build \
  --build-arg CLANG_VERSION=19.1.5 \
  --build-arg GODOT_ANGLE_STATIC_VERSION=chromium/7578 \
  --build-arg MACOS_VERSION_MINIMUM=11.0 \
  --build-arg MACOS_VERSION=26.1 \
  --build-arg OSXCROSS_SDK=darwin25.1 \
  --build-context osxcross=thirdparty/osxcross \
  --build-context patches=thirdparty/.patches \
  --build-context vulkan=thirdparty/moltenvk \
  -t compile-godot-export-template:godot-v4.7-macos \
  actions/compile-godot-export-template/macos
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker build \
  --build-arg EMSCRIPTEN_SDK_VERSION=4.0.20 \
  --build-context patches=thirdparty/.patches \
  -t compile-godot-export-template:godot-v4.7-web \
  actions/compile-godot-export-template/web
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
docker build \
  --build-arg AGILITY_VERSION=1.618.5 \
  --build-arg GODOT_ANGLE_STATIC_VERSION=chromium/7578 \
  --build-arg GODOT_NIR_STATIC_VERSION=25.3.1-3 \
  --build-arg MINGW_LLVM_VERSION=20251118 \
  --build-arg PIX_VERSION=1.0.240308001 \
  --build-context patches=thirdparty/.patches \
  -t compile-godot-export-template:godot-v4.7-windows \
  actions/compile-godot-export-template/windows
```

</details>

#### `export-godot-project-preset`

Dependency versions are taken from the defaults defined in the [publish-image-export-godot-project-preset.yaml](.github/workflows/publish-image-export-godot-project-preset.yaml) workflow.

<details>
<summary><strong>macOS</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.98.0 \
  --build-context patches=thirdparty/.patches \
  -t export-godot-project-preset:godot-v4.7-macos \
  actions/export-godot-project-preset/macos
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.98.0 \
  --build-context patches=thirdparty/.patches \
  -t export-godot-project-preset:godot-v4.7-web \
  actions/export-godot-project-preset/web
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.98.0 \
  --build-context patches=thirdparty/.patches \
  -t export-godot-project-preset:godot-v4.7-windows \
  actions/export-godot-project-preset/windows
```

</details>

### Testing the toolchain end to end

A successful image build only proves that the toolchain installs. CI runs the export pipeline against the sample project in [`tests/project`](./tests/project) for every minor in `godot-versions.txt` on each pull request that touches the pipeline. The same runs locally; the build commands are the scripts beside each Dockerfile (`actions/compile-godot-export-template/<platform>/compile.sh`, `actions/export-godot-project-preset/<platform>/export.sh`), mounted into the container exactly as the actions do it. Each script documents the environment variables it reads.

#### Setup

```sh
# Leave empty to test images built locally (see "Building images locally").
REGISTRY="ghcr.io/coffeebeats/"
GODOT_VERSION="4.7.2-stable"
GODOT_MINOR="${GODOT_VERSION%.*}"

# Pin the sample project, vendor the Godot source code into './godot', and
# install the Linux editor (the one the export images run).
gdenv pin -p tests/project "$GODOT_VERSION"
gdenv vendor -p tests/project
mkdir -p .godot-editor .scons build dist
GDENV_OS=linux GDENV_ARCH=x86_64 gdenv install -p tests/project
cp "$(GDENV_OS=linux GDENV_ARCH=x86_64 gdenv which -p tests/project 2>&1)" .godot-editor/godot

# Shared arguments. The repository root is the container's workspace, as in CI.
RUN=(docker run --rm --platform linux/amd64 -v "$PWD:/github/workspace" -v "$PWD/actions:/actions:ro" -w /github/workspace)
COMPILE=(-e GODOT_SRC_PATH=godot -e SCONS_CACHE_PATH=.scons -e TARGET=template_release -e PROFILE=release)
EXPORT=(-e GODOT_EDITOR_PATH=.godot-editor/godot -e PROJECT_PATH=tests/project -e PROFILE=release)
```

<details>
<summary><strong>macOS</strong></summary>

```sh
"${RUN[@]}" "${COMPILE[@]}" -e ARCH=universal "${REGISTRY}compile-godot-export-template:godot-v${GODOT_MINOR}-macos" \
  /actions/compile-godot-export-template/macos/compile.sh
mv godot/bin/godot_macos.zip build/

"${RUN[@]}" "${EXPORT[@]}" -e PRESET_NAME=universal-macos-unknown -e PRESET_OUTPUT_PATH=dist/Game.app.zip \
  "${REGISTRY}export-godot-project-preset:godot-v${GODOT_MINOR}-macos" /actions/export-godot-project-preset/macos/export.sh
```

> [!NOTE]
> The macOS exporter prints `No export template found at the expected path` before it finds the custom template. That line is noise; only the errors after it fail the export.

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
"${RUN[@]}" "${COMPILE[@]}" -e ARCH=wasm32 "${REGISTRY}compile-godot-export-template:godot-v${GODOT_MINOR}-web" \
  /actions/compile-godot-export-template/web/compile.sh
mv godot/bin/web_release.zip build/

"${RUN[@]}" "${EXPORT[@]}" -e PRESET_NAME=wasm32-web-unknown -e PRESET_OUTPUT_PATH=dist/Game.html \
  "${REGISTRY}export-godot-project-preset:godot-v${GODOT_MINOR}-web" /actions/export-godot-project-preset/web/export.sh
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
"${RUN[@]}" "${COMPILE[@]}" -e ARCH=x86_64 "${REGISTRY}compile-godot-export-template:godot-v${GODOT_MINOR}-windows" \
  /actions/compile-godot-export-template/windows/compile.sh
mv godot/bin/godot.windows.template_release.x86_64.llvm.exe build/

"${RUN[@]}" "${EXPORT[@]}" -e PRESET_NAME=x86_64-windows-unknown -e PRESET_OUTPUT_PATH=dist/Game.exe \
  "${REGISTRY}export-godot-project-preset:godot-v${GODOT_MINOR}-windows" /actions/export-godot-project-preset/windows/export.sh
```

</details>

#### What passing looks like

Each compile ends with `scons: done building targets.` and each export with `[ DONE ] export`, leaving `Game.app.zip`, `index.html` with `Game.wasm`, and `Game.exe` in `dist/`. A broken toolchain fails within seconds of `scons: Building targets ...`. The editor's `Unable to load fontconfig` errors are noise.

The `release` profile enables link-time optimization, so compiles are slow under emulation on an M-series Mac (the web template takes about 23 minutes; an export takes seconds). `.scons/` caches object files between runs. `godot/`, `build/`, `dist/`, `.godot-editor/`, `.scons/`, and `tests/project/.godot-version` are gitignored.

## **Contributing**

All contributions are welcome! Feel free to file [bugs](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=bug&projects=&template=bug-report.md&title=) and [feature requests](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=enhancement&projects=&template=feature-request.md&title=) and/or open pull requests.

## **Version history**

See [CHANGELOG.md](https://github.com/coffeebeats/godot-infra/blob/main/CHANGELOG.md).

## **License**

[MIT License](https://github.com/coffeebeats/godot-infra/blob/main/LICENSE)
