# **godot-infra** ![GitHub release (with filter)](https://img.shields.io/github/v/release/coffeebeats/godot-infra) ![GitHub](https://img.shields.io/github/license/coffeebeats/godot-infra) [![Build Status](https://img.shields.io/github/actions/workflow/status/coffeebeats/godot-infra/publish-image-godot-infra.yaml?branch=main)](https://github.com/coffeebeats/godot-infra/actions?query=branch%3Amain+workflow%3Apublish-image-godot-infra) ![Static Badge](https://img.shields.io/badge/godot-v4.5-478cbf)

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
> It's recommended to use the release tag as the version pin in your GitHub Actions workflow files since these represent stable, tested versions of this project.

#### Branch name / Release tag: Godot version

- `main` / `v3`: `v4.5`
- `v2`: `v4.4.1`
- `v1`: `v4.3`
- `v0`: `v4.2`

## **Getting started**

The `godot-infra` repository does not need to be installed. Simply add the actions defined in the repository to your GitHub actions workflows.

### **Example usage**

#### **`compile-godot-export-template`**

```yaml
- uses: "coffeebeats/godot-infra/compile-godot-export-template@v3" # x-release-please-major
  with:
    # See the action implementation for available inputs.
```

#### **`export-godot-project-preset`**

```yaml
- uses: "coffeebeats/godot-infra/export-godot-project-preset@v3" # x-release-please-major
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

## **Contributing**

All contributions are welcome! Feel free to file [bugs](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=bug&projects=&template=bug-report.md&title=) and [feature requests](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=enhancement&projects=&template=feature-request.md&title=) and/or open pull requests.

## **Version history**

See [CHANGELOG.md](https://github.com/coffeebeats/godot-infra/blob/main/CHANGELOG.md).

## **License**

[MIT License](https://github.com/coffeebeats/godot-infra/blob/main/LICENSE)
