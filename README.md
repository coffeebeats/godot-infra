# **godot-infra** ![GitHub release (with filter)](https://img.shields.io/github/v/release/coffeebeats/godot-infra) ![GitHub](https://img.shields.io/github/license/coffeebeats/godot-infra) [![Build Status](https://img.shields.io/github/actions/workflow/status/coffeebeats/godot-infra/publish-image-godot-infra.yaml?branch=main)](https://github.com/coffeebeats/godot-infra/actions?query=branch%3Amain+workflow%3Apublish-image-godot-infra) ![Static Badge](https://img.shields.io/badge/godot-v4.7.2-478cbf)

A repository for Godot build and release infrastructure using [@coffeebeats](https://github.com/coffeebeats?tab=repositories)' tools.

## **How it works**

This repository contains a number of GitHub actions useful for compiling and exporting Godot projects. See [Example usage](#example-usage) below for demonstrations of how to use the repository.

### Supported platforms

Currently, `godot-infra` supports targeting three platforms:

- `macos`
- `web`
- `windows`

### Supported Godot versions

This repository supports multiple minor versions of Godot. The `main` branch always contains the latest `godot-infra` changes and targets support for the latest Godot stable release. See the list below for the mapping of `godot-infra` release versions to supported Godot version.

> [!NOTE]
> Although it's recommended to [pin actions to the full-length commit SHA](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions), the following release tags define stable, tested versions of this project.

#### Release tag: Godot version

- `v5` (`main`): `v4.7.2`
- `v4`: `v4.6.3`
- `v3`: `v4.5.1`
- `v2`: `v4.4.1`
- `v1`: `v4.3`
- `v0`: `v4.2`

## **Getting started**

The `godot-infra` repository does not need to be installed. Simply add the actions defined in the repository to your GitHub actions workflows.

### **Example usage**

#### **`compile-godot-export-template`**

```yaml
- uses: "coffeebeats/godot-infra/compile-godot-export-template@v5"
  with:
    # See the action implementation for available inputs.
```

#### **`export-godot-project-preset`**

```yaml
- uses: "coffeebeats/godot-infra/export-godot-project-preset@v5"
  with:
    # See the action implementation for available inputs.
```

## **Template repositories**

The [@coffeebeats](https://github.com/coffeebeats) user has a few template repositories useful for various types of Godot projects. These include:

- [godot-project-template](https://github.com/coffeebeats/godot-project-template)
- [godot-plugin-template](https://github.com/coffeebeats/godot-plugin-template)
- [godot-prototype-template](https://github.com/coffeebeats/godot-prototype-template)

These can be instantiated with recommended repository settings using the [instantiate-template-repository](./scripts/instantiate-template-repository.sh) script. Run the following command (requires a Unix shell):

```sh
./scripts/instantiate-template-repository.sh \
  --name <NEW REPO NAME> \
  --template <TEMPLATE REPO NAME> \
  --branch main \
  --description "A new Godot 4+ project."
```

## **Development**

### Building images locally

During development, you may want to build the infrastructure images locally rather than relying on CI/CD workflows. This section provides commands for building images on your local machine.

#### `compile-godot-export-template`

Dependency versions are taken from the defaults defined in the [publish-image-compile-godot-export-template.yaml](.github/workflows/publish-image-compile-godot-export-template.yaml) workflow.

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
  compile-godot-export-template/macos
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker build \
  --build-arg EMSCRIPTEN_SDK_VERSION=4.0.20 \
  --build-context patches=thirdparty/.patches \
  -t compile-godot-export-template:godot-v4.7-web \
  compile-godot-export-template/web
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
  compile-godot-export-template/windows
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
  export-godot-project-preset/macos
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.98.0 \
  --build-context patches=thirdparty/.patches \
  -t export-godot-project-preset:godot-v4.7-web \
  export-godot-project-preset/web
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.98.0 \
  --build-context patches=thirdparty/.patches \
  -t export-godot-project-preset:godot-v4.7-windows \
  export-godot-project-preset/windows
```

</details>

### Testing the toolchain end to end

A successful image build only proves that the toolchain installs. The steps below compile a Godot export template with each `compile-godot-export-template` image and export the sample project in [`tests/project`](./tests/project) with each `export-godot-project-preset` image, using the same commands the actions run in CI. Run them from the repository root, against the published images once CI has pushed them and against local images while developing.

#### Setup

`gdenv` resolves the Godot version from `tests/project/.godot-version`. `GDENV_OS` and `GDENV_ARCH` make it fetch the Linux editor that the export images run.

```sh
# Leave empty to test images built locally (see "Building images locally").
REGISTRY="ghcr.io/coffeebeats/"

# Vendor the Godot source code into './godot'.
gdenv vendor -p tests/project

# Install the Linux editor and copy it into the workspace.
mkdir -p .godot-editor .scons build dist
GDENV_OS=linux GDENV_ARCH=x86_64 gdenv install -p tests/project
cp "$(GDENV_OS=linux GDENV_ARCH=x86_64 gdenv which -p tests/project 2>&1)" .godot-editor/godot

# Shared arguments. The repository root is the container's workspace, as in CI.
RUN=(docker run --rm --platform linux/amd64 -v "$PWD:/github/workspace" -w /github/workspace)
SCONS='scons -j$(nproc) -C godot cache_path=/github/workspace/.scons verbose=yes warnings=extra werror=yes'
EXPORT='.godot-editor/godot --path tests/project --headless --export-release'
```

The `scons` arguments below are the ones `compile-godot-export-template/*/action.yml` passes for the `release` profile, and `tests/project/export_presets.cfg` expects the templates under `build/` with the names CI gives them. Keep both in sync with the actions.

<details>
<summary><strong>macOS</strong></summary>

CI compiles `x86_64` first, then `arm64` with `generate_bundle=yes`, which merges both into a universal `godot_macos.zip`.

```sh
CCFLAGS="-Wno-ordered-compare-function-pointers -Wno-c99-designator"

"${RUN[@]}" "${REGISTRY}compile-godot-export-template:godot-v4.7-macos" /bin/bash -c \
  "$SCONS arch=x86_64 target=template_release production=yes optimize=speed ccflags='$CCFLAGS'"
"${RUN[@]}" "${REGISTRY}compile-godot-export-template:godot-v4.7-macos" /bin/bash -c \
  "$SCONS arch=arm64 target=template_release production=yes optimize=speed generate_bundle=yes ccflags='$CCFLAGS'"
mv godot/bin/godot_macos.zip build/

"${RUN[@]}" "${REGISTRY}export-godot-project-preset:godot-v4.7-macos" /bin/bash -c \
  "$EXPORT macos /github/workspace/dist/Game.app.zip"
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
"${RUN[@]}" "${REGISTRY}compile-godot-export-template:godot-v4.7-web" /bin/bash -c \
  "$SCONS arch=wasm32 target=template_release production=yes optimize=speed javascript_eval=no threads=yes"
mv godot/bin/godot.web.template_release.wasm32.zip build/web_release.zip

"${RUN[@]}" "${REGISTRY}export-godot-project-preset:godot-v4.7-web" /bin/bash -c \
  "$EXPORT web /github/workspace/dist/Game.html"
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
"${RUN[@]}" "${REGISTRY}compile-godot-export-template:godot-v4.7-windows" /bin/bash -c \
  "$SCONS arch=x86_64 target=template_release production=yes optimize=speed"
mv godot/bin/godot.windows.template_release.x86_64.llvm.exe build/

"${RUN[@]}" "${REGISTRY}export-godot-project-preset:godot-v4.7-windows" /bin/bash -c \
  "$EXPORT windows /github/workspace/dist/Game.exe"
```

</details>

#### What passing looks like

Each compile ends with `scons: done building targets.` and each export with `[ DONE ] export`, leaving `Game.app.zip`, `Game.html` with `Game.wasm`, and `Game.exe` in `dist/`. A broken toolchain fails within seconds of `scons: Building targets ...`. Two editor messages are noise: `Unable to load fontconfig`, and the macOS exporter's `No export template found at the expected path`, which reports the official template before it finds the custom one. Only the errors after it fail the export.

The `release` profile enables link-time optimization, so compiles are slow under emulation on an M-series Mac (the web template takes about 23 minutes; an export takes seconds). `.scons/` caches object files between runs. `godot/`, `build/`, `dist/`, `.godot-editor/`, and `.scons/` are gitignored.

## **Contributing**

All contributions are welcome! Feel free to file [bugs](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=bug&projects=&template=bug-report.md&title=) and [feature requests](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=enhancement&projects=&template=feature-request.md&title=) and/or open pull requests.

## **Version history**

See [CHANGELOG.md](https://github.com/coffeebeats/godot-infra/blob/main/CHANGELOG.md).

## **License**

[MIT License](https://github.com/coffeebeats/godot-infra/blob/main/LICENSE)
