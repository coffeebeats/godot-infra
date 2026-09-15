---
name: upgrade-godot
description: Add a new Godot minor release (e.g. 4.8) to godot-infra. Re-pins the upstream build dependencies from the new release branch and validates that the toolchain images still build and export.
disable-model-invocation: true
argument-hint: "<major.minor>"
---

Add Godot `$ARGUMENTS` to `godot-infra`. A supported minor is one line in `godot-versions.txt`, and `main` builds the images for the last line. A patch release needs nothing here, since `scripts/resolve_godot_versions.py` resolves each minor to its newest stable tag; consumers move with `scripts/upgrade_godot_project.py`.

The references use four placeholders. `<NEW>` is the minor being added and `<NEW_FULL>` its newest stable release (e.g. `4.8.1`); `<OLD>` is the current last line of `godot-versions.txt` and `<OLD_FULL>` its newest stable release.

1. **Resolve the release.** Godot tags a minor's first release with no patch component, so `4.8-stable` is 4.8.0. Take the newest matching tag, and stop if nothing matches:

   ```bash
   gh api repos/godotengine/godot/tags --paginate -q '.[].name' |
     grep -E '^<NEW>(\.[0-9]+)?-stable$' | sort -V | tail -1
   ```

   `sort -V` ranks `4.8-stable` below `4.8.1-stable`; the API's own order does not.

2. **Branch** `chore/godot/upgrade` off `main` and append `<NEW>` to `godot-versions.txt`.
3. **Re-pin the dependencies.** Work `references/dependency-research.md` in full. Its second half diffs upstream's build configuration for options that newly default to on, which is how the 4.7 upgrade shipped without AccessKit or WinRT while every pin was correct.
4. **Validate the builds.** Work `references/build-validation.md` through Tier 3 before opening the PR, and its post-publish check once the images are published.
5. **Commit** one line naming the release, `chore: support Godot <NEW_FULL>`, with no body or trailers.
