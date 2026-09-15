---
name: upgrade-godot
description: Add a new Godot minor or major release (e.g. 4.8, 5.0) to godot-infra. Re-pins the upstream build dependencies from the new release branch, validates that the toolchain images still build and export, and rolls the release out to the consuming repositories.
disable-model-invocation: true
argument-hint: "<major.minor>"
---

Add Godot `$ARGUMENTS` to `godot-infra`. A supported minor is one line in `godot-versions.txt`, and `main` builds the images for the last line.

Which kind of release needs what:

- **A patch** (`4.7.2` to `4.7.3`) needs no change here. Image tags name the minor only, and `scripts/resolve_godot_versions.py` resolves each listed minor to its newest stable tag, so `check-commit` compiles and exports against a new patch on its next run — including on a pull request that has nothing to do with it. A patch that turns the self-test red is fixed here, not in a consumer.
- **A minor or a major** is this skill. `5.0` follows `4.11` exactly as `4.8` follows `4.7`: image tags and `godot-versions.txt` lines are both `X.Y`.
- **Neither bumps this repository's major.** A `godot-infra` release is independent of the Godot version (README, "Supported Godot versions"), so the commit below is a `chore:`.

Consumers move with the `upgrade-godot-project` skill in `plugins/godot`, which every repository loading the `godot` plugin already has. Step 7 is the order they move in.

The references use four placeholders. `<NEW>` is the minor being added and `<NEW_FULL>` its newest stable release (e.g. `4.8.1`); `<OLD>` is the current last line of `godot-versions.txt` and `<OLD_FULL>` its newest stable release.

1. **Resolve the release.** Godot tags a minor's first release with no patch component, so `4.8-stable` is 4.8.0. Take the newest matching tag, and stop if nothing matches:

   ```bash
   gh api repos/godotengine/godot/tags --paginate -q '.[].name' |
     grep -E '^<NEW>(\.[0-9]+)?-stable$' | sort -V | tail -1
   ```

   `sort -V` ranks `4.8-stable` below `4.8.1-stable`; the API's own order does not.

2. **Branch** `chore/godot/upgrade` off `main` and append `<NEW>` to `godot-versions.txt`. The file holds the two newest minors, matching the two that upstream still patches, so drop the oldest line when appending would make three; by then every active repository is on one of the two that remain. Dropping a line stops the self-test and the image rebuilds for that minor; its published tags are never deleted, so a project pinned there keeps building.

3. **Re-pin the dependencies.** Work `references/dependency-research.md` in full. Its second half diffs upstream's build configuration for options that newly default to on, which is how the 4.7 upgrade shipped without AccessKit or WinRT while every pin was correct.

4. **Update the README's version references.** Four places name a version by hand, and nothing fails when they go stale:

   - the `godot-<minor>` badge on line 1;
   - the `v6` row of the major-to-minors table, which mirrors `godot-versions.txt`;
   - the six `-t <image>:godot-v<minor>-<platform>` tags in "Building images locally";
   - `GODOT_VERSION` in "Testing the toolchain end to end", which names a full release.

   The `--build-arg` values inside those same code blocks belong to "Applying updates" in `references/dependency-research.md`; do both in one pass.

5. **Validate the builds.** Work `references/build-validation.md` through Tier 3 before opening the PR, and its post-publish check once the merge has published the images.

6. **Commit** one line naming the release, `chore: support Godot <NEW_FULL>`, with no body or trailers.

7. **Roll it out.** Merging publishes the images, so nothing that compiles or exports can move before that. Then, in order, with `upgrade-godot-project` in each: the `gut` and `GodotSteam` forks, since their `dist` branches are reimported at their own pins; `godot-plugin-std`, whose matrix is what shows an addon break; `godot-project-template`, `godot-prototypes`, and `godot-plugin-template`; then the games, which bump their addon gitlinks along with the pin. No consumer waits on a `godot-infra` release, since the images publish on the merge itself, and nothing changes in a consumer but `.godot-version`, `config/features`, and the addon gitlinks.
