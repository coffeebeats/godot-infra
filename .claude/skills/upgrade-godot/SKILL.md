---
name: upgrade-godot
description: Upgrade the project to a new Godot release, minor or patch (e.g. 4.6.3 to 4.7.2). Resolves the target version, bumps every version pin, and for a minor release also re-pins upstream dependencies and validates that the images still build.
disable-model-invocation: true
argument-hint: "[version]"
---

Upgrade this project to Godot version `$ARGUMENTS`, or to the newest stable release when that is
empty. Resolve the target first and let it pick the route: a **patch** bump edits three lines in two
files, while a **minor** bump also sweeps every `major.minor` string, re-pins upstream dependencies,
and forces a new `godot-infra` release tag (`v4` → `v5`).

**Do not pick the route by hand.** Both inputs are readable — what is pinned now, and what
upstream has released — and every minor upgrade that guessed at the patch component got it wrong.
`4.5` was pinned six weeks after 4.5.1 shipped, `4.7` two weeks after 4.7.2, each corrected hours
later by a second commit that resolving the version properly makes unnecessary.

## Resolve the target

1. **Read the current state.** `README.md` carries a version table under
   `#### Release tag: Godot version`. Its top row gives `OLD_FULL` (e.g. `4.7.2`) and `OLD_TAG`
   (e.g. `v5`). Derive `OLD` = that version's major.minor (e.g. `4.7`).

2. **Resolve `NEW_FULL`.** Godot tags a minor's *first* release with no patch component, so
   `4.7-stable` **is** 4.7.0 and there is no `4.7.0-stable`. Never pin a bare `<minor>-stable`
   without checking for a later patch first.

   ```bash
   TAGS=$(gh api repos/godotengine/godot/tags --paginate -q '.[].name')

   # No argument — the newest stable release:
   echo "$TAGS" | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?-stable$' | sort -V | tail -1

   # A bare major.minor argument (e.g. `4.8`) — the newest patch of that minor:
   echo "$TAGS" | grep -E '^4\.8(\.[0-9]+)?-stable$'           | sort -V | tail -1
   ```

   `sort -V` is what makes this correct: it ranks `4.7-stable` below `4.7.1-stable`, and
   `4.10-stable` above both. Do not rely on the API's own ordering. When `$ARGUMENTS` already names
   a full `major.minor.patch`, take it as given, stripping any leading `v`.

   Derive `NEW` = `NEW_FULL`'s major.minor.

3. **Route on the two versions.**

   | Condition | Route |
   | --- | --- |
   | `NEW` == `OLD`, and `NEW_FULL`'s patch > `OLD_FULL`'s patch | **patch** |
   | `NEW`'s minor == `OLD`'s minor + 1 | **minor**; `NEW_TAG` = `OLD_TAG` + 1 |
   | `NEW_FULL` == `OLD_FULL` | stop — already current |
   | anything lower, or a jump of more than one minor | stop and ask |

   A multi-minor jump means two releases of upstream drift to research at once, so it needs the
   user's agreement on scope before starting. State the resolved route and version before editing.

4. **Create the branch** `chore/godot/upgrade` off the current branch. Never edit `main` directly.

5. **Read the target files** before editing any of them — `README.md` and
   `package-addon/action.yaml` on both routes; on the minor route also the three
   `.github/workflows/publish-image-*.yaml` files and the six image action files named below.

## Version pins — both routes

Three lines in two files. These are the whole patch route.

1. **`README.md` badge (line 1)** — `godot-v<OLD_FULL>-478cbf` → `godot-v<NEW_FULL>-478cbf`
2. **`README.md` version table** — on the patch route, replace the version in the existing top
   row. On the minor route, insert a row and demote the previous one:
   ```
   - `<NEW_TAG>` (`main`): `v<NEW_FULL>`
   - `<OLD_TAG>`: `v<OLD_FULL>`
   ```
3. **`package-addon/action.yaml`** — `godot-editor-version` default → `"v<NEW_FULL>-stable"`

**On the patch route, stop here and go to Review.** Nothing else in the repo names a patch version;
image tags and workflow variables carry `major.minor` only.

## Mechanical sweep — minor route only

Everything here takes the bare `<OLD>` → `<NEW>` major.minor, never the full version.

1. **Docker image tags** — replace `godot-v<OLD>-` with `godot-v<NEW>-` in six files:
   `{compile-godot-export-template,export-godot-project-preset}/{macos,web,windows}/action.yml`
2. **`GODOT_MAJOR_MINOR_VERSION`** — in `.github/workflows/publish-image-godot-infra.yaml`.
3. **`README.md` Docker examples** — every image tag containing `godot-v<OLD>-`, across both the
   `compile-godot-export-template` and `export-godot-project-preset` sections, in the local build
   and local run commands alike.
4. **Internal action references** — `grep` every `.yml`/`.yaml` for `coffeebeats/godot-infra/`
   followed by `@<OLD_TAG>`, then replace with `@<NEW_TAG>`. Typically seven files:
   `.github/actions/{check-code-formatting,install-godot-source}/action.yml`,
   `check-godot-project/action.yaml`, `compile-godot-export-template/action.yml`,
   `export-godot-project-preset/action.yaml`, `package-addon/action.yaml`, and
   `publish-project-itchio/action.yml`.

## Dependency research — minor route only

Read `references/dependency-research.md` and work it in full. It re-pins the upstream dependency
defaults from the `<NEW>` release branch, then diffs upstream's build configuration for options that
newly default to on. Skipping that second half is how the 4.7 upgrade shipped without AccessKit or
WinRT while every version pin was correct.

## Review the diff

**Patch route:** `git diff --stat` must show **exactly 2 files changed, 3 insertions, 3 deletions.**
Every patch upgrade in this repo's history has hit that exactly, so treat a miss as a stop rather
than a rounding error — it means an edit landed somewhere it should not have.

**Minor route:** expect roughly six image action files at one line each, two or three workflow
files, `package-addon/action.yaml`, `README.md` (many lines), five to seven files for the internal
action references, and possibly the macOS SDK workflows and the `thirdparty/osxcross` submodule.

Present the summary to the user before going further.

## Validate the builds — minor route only

Read `references/build-validation.md` and work it in full. The biggest risk in a minor upgrade is
that the images stop building, and a bad pin produces a green diff with a red build. CI's only
fallback hardcodes `push: true`, so a broken pin discovered there is already public on ghcr.io.

## Commit

One commit on `chore/godot/upgrade`, naming the version actually pinned:

```
chore: upgrade to Godot `v<NEW_FULL>-stable`     # patch route
chore!: upgrade to Godot `v<NEW_FULL>-stable`    # minor route
```

The `!` marks the breaking change of a new release tag, and release-please reads it to cut the major
bump that `@<NEW_TAG>` depends on. A squash merge makes this line the release note, so it has to
name the full version. That single line is the whole message — no body, no co-author trailers.

## Key reference files

- `README.md` — badge, version table, Docker build/run examples
- `README.md` §"Building images locally" — the source of truth for local `docker build` commands
- `package-addon/action.yaml` — `godot-editor-version` default
- `.github/workflows/publish-image-godot-infra.yaml` — `GODOT_MAJOR_MINOR_VERSION`
- `.github/workflows/publish-image-compile-godot-export-template.yaml` — compile dependency versions
- `.github/workflows/publish-image-export-godot-project-preset.yaml` — `RUST_VERSION` default
- `compile-godot-export-template/{macos,web,windows}/action.yml` — Docker image tags
- `export-godot-project-preset/{macos,web,windows}/action.yml` — Docker image tags
- `thirdparty/osxcross` — osxcross submodule (may need updating for macOS builds)
