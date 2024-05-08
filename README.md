# **godot-infra** ![GitHub release (with filter)](https://img.shields.io/github/v/release/coffeebeats/godot-infra) ![GitHub](https://img.shields.io/github/license/coffeebeats/godot-infra) [![Build Status](https://img.shields.io/github/actions/workflow/status/coffeebeats/godot-infra/publish-image-godot-infra.yaml?branch=main)](https://github.com/coffeebeats/godot-infra/actions?query=branch%3Amain+workflow%3Apublish-image-godot-infra) ![Static Badge](https://img.shields.io/badge/godot-v4.2-478cbf)

A repository for Godot build and release infrastructure using [@coffeebeats](https://github.com/coffeebeats?tab=repositories)' tools.

> [!WARNING]
> This project is in a very early stage. API instability, missing features, and bugs are to be expected for now.

## **How it works**

This repository contains a number of GitHub actions useful for compiling and exporting Godot projects. See [Example usage](#example-usage) below for demonstrations of how to use the repository.

### Supported platforms

Currently, `godot-infra` supports targeting three platforms:

- `macos`
- `web`
- `windows`

## **Getting started**

These instructions will help you install `godot-infra` and export your _Godot_ projects.

### **Example usage**

#### **`compile-godot-export-template`**

```yaml
- uses: "coffeebeats/godot-infra/compile-godot-export-template@v0" # x-release-please-major
  with:
    # See the action implementation for avaliable inputs.
```

#### **`export-godot-project-preset`**

```yaml
- uses: "coffeebeats/godot-infra/export-godot-project-preset@v0" # x-release-please-major
  with:
    # See the action implementation for avaliable inputs.
```

## **Contributing**

All contributions are welcome! Feel free to file [bugs](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=bug&projects=&template=bug-report.md&title=) and [feature requests](https://github.com/coffeebeats/godot-infra/issues/new?assignees=&labels=enhancement&projects=&template=feature-request.md&title=) and/or open pull requests.

## **Version history**

See [CHANGELOG.md](https://github.com/coffeebeats/godot-infra/blob/main/CHANGELOG.md).

## **License**

[MIT License](https://github.com/coffeebeats/godot-infra/blob/main/LICENSE)
