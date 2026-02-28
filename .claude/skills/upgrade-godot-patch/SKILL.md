---
name: upgrade-godot-patch
description: Upgrade the project to a new Godot patch release (e.g. 4.6.0 to 4.6.1). Use when bumping the Godot patch version.
disable-model-invocation: true
argument-hint: "<version>"
---

Upgrade this project to Godot patch version `$ARGUMENTS`. Only **2 files** are modified during
a patch upgrade — `README.md` and `package-addon/action.yaml`. No other files change because
Docker image tags and workflow variables use `major.minor` only.

## Steps

1. **Validate the argument.** Extract the full version (e.g. `4.6.1`) from `$ARGUMENTS`. Strip
   a leading `v` if present. Verify the format is `major.minor.patch` where `patch > 0`. If
   invalid, stop and ask the user.

2. **Read the target files** to determine the current version and find the exact strings to
   replace:
   - `README.md` — find the Shields.io badge URL containing `godot-v<VERSION>` and the version
     table entry under `#### Release tag: Godot version`
   - `package-addon/action.yaml` — find the `godot-editor-version` input's `default` value

3. **Update `README.md`** — exactly two edits:
   - **Badge:** Replace the version in the badge URL
     `https://img.shields.io/badge/godot-v<OLD>-478cbf` →
     `https://img.shields.io/badge/godot-v<NEW>-478cbf`
   - **Version table:** Replace the version in the `main` mapping entry
     e.g. `` `v4.6.0` `` → `` `v4.6.1` ``

4. **Update `package-addon/action.yaml`** — one edit:
   - **`godot-editor-version` default:** Replace the default value
     e.g. `"v4.6-stable"` or `"v4.6.0-stable"` → `"v4.6.1-stable"`

5. **Verify the diff.** Run `git diff --stat` and confirm exactly 2 files changed with 3
   insertions and 3 deletions.

6. **Commit** with the message:
   ```
   chore: upgrade to Godot `v<NEW_VERSION>-stable`
   ```

## Key reference files

- `README.md` — badge (line 1) and version table
- `package-addon/action.yaml` — `godot-editor-version` default value

## Prior patch upgrades

- `v4.4` → `v4.4.1`: commit `b379589` (PR #375)
- `v4.5` → `v4.5.1`: commit `02b5552` (PR #452)
