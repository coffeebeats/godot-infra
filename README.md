# **godot-infra** ![GitHub release (with filter)](https://img.shields.io/github/v/release/coffeebeats/godot-infra) ![GitHub](https://img.shields.io/github/license/coffeebeats/godot-infra) [![Build Status](https://img.shields.io/github/actions/workflow/status/coffeebeats/godot-infra/publish-image-godot-infra.yaml?branch=main)](https://github.com/coffeebeats/godot-infra/actions?query=branch%3Amain+workflow%3Apublish-image-godot-infra) ![Static Badge](https://img.shields.io/badge/godot-v4.5.1-478cbf)

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

#### Branch name / Release tag: Godot version

- `main` / `v3`: `v4.5.1`
- `v2`: `v4.4.1`
- `v1`: `v4.3`
- `v0`: `v4.2`

## **Getting started**

The `godot-infra` repository does not need to be installed. Simply add the actions defined in the repository to your GitHub actions workflows.

### **Example usage**

#### **`compile-godot-export-template`**

```yaml
- uses: "coffeebeats/godot-infra/compile-godot-export-template@v3"
  with:
    # See the action implementation for available inputs.
```

#### **`export-godot-project-preset`**

```yaml
- uses: "coffeebeats/godot-infra/export-godot-project-preset@v3"
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
  --build-arg CLANG_VERSION=19.1.4 \
  --build-arg GODOT_ANGLE_STATIC_VERSION=chromium/6601.2 \
  --build-arg MACOS_VERSION_MINIMUM=10.15 \
  --build-arg MACOS_VERSION=15.5 \
  --build-arg OSXCROSS_SDK=darwin24.5 \
  --build-context osxcross=thirdparty/osxcross \
  --build-context vulkan=thirdparty/moltenvk \
  -t compile-godot-export-template:godot-v4.5-macos \
  compile-godot-export-template/macos
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker build \
  --build-arg EMSCRIPTEN_SDK_VERSION=4.0.10 \
  -t compile-godot-export-template:godot-v4.5-web \
  compile-godot-export-template/web
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
docker build \
  --build-arg AGILITY_VERSION=1.613.3 \
  --build-arg GODOT_ANGLE_STATIC_VERSION=chromium/6601.2 \
  --build-arg GODOT_NIR_STATIC_VERSION=23.1.9-1 \
  --build-arg MINGW_LLVM_VERSION=20240619 \
  --build-arg PIX_VERSION=1.0.240308001 \
  -t compile-godot-export-template:godot-v4.5-windows \
  compile-godot-export-template/windows
```

</details>

#### `export-godot-project-preset`

Dependency versions are taken from the defaults defined in the [publish-image-export-godot-project-preset.yaml](.github/workflows/publish-image-export-godot-project-preset.yaml) workflow.

<details>
<summary><strong>macOS</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.91.1 \
  -t export-godot-project-preset:godot-v4.5-macos \
  export-godot-project-preset/macos
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.91.1 \
  -t export-godot-project-preset:godot-v4.5-web \
  export-godot-project-preset/web
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
docker build \
  --build-arg RUST_VERSION=1.91.1 \
  -t export-godot-project-preset:godot-v4.5-windows \
  export-godot-project-preset/windows
```

</details>

### Compiling export templates locally

You can test building export templates locally using the above images. First, vendor the Godot source code using [gdenv](https://github.com/coffeebeats/gdenv) by running:

```sh
gdenv vendor
```

This will download and extract the Godot source code into the `godot/` directory. Then, use the Docker commands below to build export templates for each platform.

<details>
<summary><strong>macOS</strong></summary>

```sh
docker run --rm -it \
  -v "$(pwd)/godot:/github/workspace" \
  -v "$(pwd)/.scons:/github/workspace/.scons" \
  compile-godot-export-template:godot-v4.5-macos \
  /bin/bash -c -O extglob "scons -j\$(nproc) -C /github/workspace cache_path=/github/workspace/.scons verbose=yes warnings=extra werror=yes arch=arm64 target=template_debug debug_symbols=yes optimize=debug ccflags='-Wno-ordered-compare-function-pointers -Wno-c99-designator'"
```

</details>

<details>
<summary><strong>Web</strong></summary>

```sh
docker run --rm -it \
  -v "$(pwd)/godot:/github/workspace" \
  -v "$(pwd)/.scons:/github/workspace/.scons" \
  compile-godot-export-template:godot-v4.5-web \
  /bin/bash -c "scons -j\$(nproc) -C /github/workspace cache_path=/github/workspace/.scons verbose=yes warnings=extra werror=yes arch=wasm32 target=template_debug debug_symbols=yes optimize=debug"
```

</details>

<details>
<summary><strong>Windows</strong></summary>

```sh
docker run --rm -it \
  -v "$(pwd)/godot:/github/workspace" \
  -v "$(pwd)/.scons:/github/workspace/.scons" \
  compile-godot-export-template:godot-v4.5-windows \
  /bin/bash -c "scons -j\$(nproc) -C /github/workspace cache_path=/github/workspace/.scons verbose=yes warnings=extra werror=yes arch=x86_64 target=template_debug debug_symbols=yes optimize=debug"
```

</details>

## **Contributing**

All contributions are welcome! Feel free to file [bugs](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=bug&projects=&template=bug-report.md&title=) and [feature requests](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=enhancement&projects=&template=feature-request.md&title=) and/or open pull requests.

## **Version history**

See [CHANGELOG.md](https://github.com/coffeebeats/godot-infra/blob/main/CHANGELOG.md).

## **License**

[MIT License](https://github.com/coffeebeats/godot-infra/blob/main/LICENSE)
