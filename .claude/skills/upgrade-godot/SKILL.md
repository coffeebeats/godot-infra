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

   **Normalize `OLD_FULL` to three components**, treating a missing patch as `0`. The table carries
   patchless rows — the `v1` row reads `v4.3`, and `v4.7` sat in the top row until 4.7.2 landed —
   and step 3 compares patch numbers.

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

   **Then confirm the tag exists**, whichever path produced it. An argument is taken on trust and
   the patch route makes no upstream request that would fail later, so a typo gets pinned, passes
   every check below, and commits.

   ```bash
   echo "$TAGS" | grep -qx "<NEW_FULL>-stable" || echo "no such Godot release"
   ```

   Derive `NEW` = `NEW_FULL`'s major.minor.

3. **Route on the two versions.**

   | Condition | Route |
   | --- | --- |
   | `NEW` == `OLD`, and `NEW_FULL`'s patch > `OLD_FULL`'s patch | **patch** |
   | `NEW` is the next release, minor or major | **minor**; `NEW_TAG` = `OLD_TAG` + 1 |
   | `NEW_FULL` == `OLD_FULL` | stop — already current |
   | anything lower, or a jump of more than one release | stop and ask |

   "The next release" is `4.7` → `4.8`, or `4.7` → `5.0`. Compare the major and minor together and
   never the minor alone: `5.0` follows `4.7` even though `0 < 7`. A major bump has not happened yet
   and takes the minor route unchanged — same files, same new release tag — so it gets no branch of
   its own here.

   A multi-release jump means two releases of upstream drift to research at once, so it needs the
   user's agreement on scope before starting. State the resolved route and version before editing.

4. **Create the branch** `chore/godot/upgrade` off the current branch. Never edit `main` directly.

5. **Read the target files** before editing any of them — `README.md` and
   `package-addon/action.yaml` on both routes; on the minor route also the three
   `.github/workflows/publish-image-*.yaml` files and the six image action files named below.

## Version pins — both routes

Four lines in three files. These are the whole patch route.

1. **`README.md` badge (line 1)** — `godot-v<OLD_FULL>-478cbf` → `godot-v<NEW_FULL>-478cbf`
2. **`README.md` version table** — on the patch route, replace the version in the existing top
   row. On the minor route, insert a row and demote the previous one:
   ```
   - `<NEW_TAG>` (`main`): `v<NEW_FULL>`
   - `<OLD_TAG>`: `v<OLD_FULL>`
   ```
3. **`package-addon/action.yaml`** — `godot-editor-version` default → `"v<NEW_FULL>-stable"`
4. **`tests/project/.godot-version`** — the whole file is `v<NEW_FULL>-stable`; the end-to-end
   validation vendors the source and installs the editor from this pin.

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
4. **Consumer action pins** — `README.md` §"Example usage" pins this repo's own actions at the
   release tag. Replace `@<OLD_TAG>` with `@<NEW_TAG>`; two lines today, but find them rather than
   trusting that count:

   ```bash
   git grep -n 'coffeebeats/godot-infra/[a-z-]*@v[0-9]' -- '*.md' '*.yml' '*.yaml'
   ```

   **Search `*.md`.** Seven action files carried these pins too, until `e2758f0` (#530) switched
   internal references to local paths in March 2026. A sweep scoped to `.yml`/`.yaml` was right
   until then and has matched nothing since, reporting itself done every time — which is how `v5`
   shipped with the examples still reading `@v4`. Bump them here, in the upgrade commit;
   `@<NEW_TAG>` dangles until release-please cuts the tag on merge, and that is expected.

## Dependency research — minor route only

Read `references/dependency-research.md` and work it in full. It re-pins the upstream dependency
defaults from the `<NEW>` release branch, then diffs upstream's build configuration for options that
newly default to on. Skipping that second half is how the 4.7 upgrade shipped without AccessKit or
WinRT while every version pin was correct.

## Review the diff

**Patch route:** `git diff --stat` must show **exactly 3 files changed, 4 insertions, 4 deletions**,
and all four added lines must name the resolved version:

```bash
git diff -U0 | grep -c "^+.*<NEW_FULL>"   # must print 4
```

Every patch upgrade in this repo's history hit the previous stat (three lines in two files, before
`tests/project/.godot-version` existed) exactly, so treat a miss as a stop rather than a rounding
error — it means an edit landed somewhere it should not have. The stat alone
cannot tell `4.7.2` from `4.7.1`, which is what the second check is for.

**Minor route:** expect roughly six image action files at one line each, two or three workflow
files, `package-addon/action.yaml`, `tests/project/.godot-version`, `README.md` (many lines, the
two consumer action pins among them), and possibly the macOS SDK workflows and the
`thirdparty/osxcross` submodule.

Present the summary to the user before going further.

## Validate the builds — minor route only

Read `references/build-validation.md` and work it in full. The biggest risk in a minor upgrade is
that the images stop building, and a bad pin produces a green diff with a red build. CI's only
fallback hardcodes `push: true`, so a broken pin discovered there is already public on ghcr.io.

An image that builds is not yet an image that works: Tier 3 there compiles a template and exports
a project with it, and the post-publish check repeats that against the tags CI actually pushed,
which is where the 4.7 macOS image failed after passing every local build.

## Commit

One commit on `chore/godot/upgrade`, naming the version actually pinned:

```
chore: upgrade to Godot `v<NEW_FULL>-stable`     # patch route
chore!: upgrade to Godot `v<NEW_FULL>-stable`    # minor route
```

The `!` marks the breaking change of a new release tag, and release-please reads it to cut the major
bump that `@<NEW_TAG>` depends on. A squash merge makes this line the release note, so it has to
name the full version. That single line is the whole message — no body, no co-author trailers.
