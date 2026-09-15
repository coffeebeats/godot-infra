---
name: upgrade-godot-project
description: Move a Godot repository to a newer engine release (patch, minor, or major). Rewrites the '.godot-version' pin and 'config/features', then reimports, rebases engine patches, and proves the export pipeline before the pull request merges.
user-invocable: true
disable-model-invocation: true
argument-hint: "<major.minor | major.minor.patch>"
---

Move this repository to Godot `$ARGUMENTS`. It applies to anything holding a
`.godot-version` pin: a game, `godot-prototypes`, `godot-plugin-std`,
`godot-plugin-template`, and the `gut` and `GodotSteam` forks.

The pin is the only engine version a repository stores. `config/features` in
`project.godot` names the minor too, and the script below rewrites it; anything else that
needs a hand edit is a bug in this pipeline, not a step to add here.

A major release is a minor: `5.0` follows `4.11` the way `4.8` follows `4.7`.

## 1. Resolve the release and the route

```sh
python3 "${CLAUDE_SKILL_DIR}/upgrade_godot_project.py" resolve --godot-version <X.Y|X.Y.Z>
```

`X.Y` takes that minor's newest stable release. Where `python3` is absent, run it with
`uv run --no-project` instead.

The pin decides the route: `none` (already current), `patch` (same minor), or `minor`
(a new minor or major). The routes differ from step 4 onwards.

**A minor needs `godot-infra` to publish its toolchain images first**, but only for a
repository that compiles or exports — a game, or `godot-prototypes`. The published minors
are the lines of
[`godot-versions.txt`](https://github.com/coffeebeats/godot-infra/blob/v6/godot-versions.txt);
add one with the `upgrade-godot` skill there. Moving first fails the compile job with
`Toolchain image not found: …`. A repository that only runs `check-project` — std, the
plugin template, the forks — needs nothing published, since that workflow installs the
editor with `gdenv`.

## 2. Rewrite the pins

Branch `chore/godot/upgrade`, then:

```sh
python3 "${CLAUDE_SKILL_DIR}/upgrade_godot_project.py" upgrade --godot-version <target>
```

It writes `.godot-version` through `gdenv pin`, rewrites `config/features` on a minor, and
records what changed in `upgrade-summary.json`, whose `commit_title` is the commit message
and whose `changes` and `warnings` are the pull request body. A warning that
`config/features` does not name the old minor means the project was already inconsistent;
read it before continuing.

## 3. Reimport and check

```sh
gdenv install
godot --verbose --headless --quit --import
godot-check
```

`.godot/` is gitignored, so this is local proof rather than a diff: the new editor either
imports every resource and passes the checker, or it does not. On a minor, also regenerate
the API reference, since engine signatures move between minors:

```sh
sh "${CLAUDE_SKILL_DIR}/../godot-api/dump_api.sh"
```

## 4. Rebase the engine patches (minor)

A repository with files under `.patches/godotengine/godot/` applies them to the engine
source during every compile, in both `compile-editor` and `publish-game`. A patch that no
longer applies to the new release fails the compile, so rebase it now:

```sh
gdenv vendor                   # the new release's source, into the gitignored './godot'
git apply --check --ignore-whitespace --directory=godot .patches/godotengine/godot/*
```

Those are the flags `install-godot-source` applies them with, minus `--check`.

## 5. Move the addons first (minor)

The `gut` and `GodotSteam` forks carry their own `.godot-version` and publish `dist`
reimported at it, so they run this skill before any consumer of theirs does; a game then
bumps its submodule gitlink. Two constraints decide whether they can move at all:

- GUT publishes one line per Godot minor (9.7.1 targets 4.7.x), so the fork may need the
  upstream release for the new minor merged in first.
- GodotSteam declares a `compatibility_minimum` in `addons/godotsteam/godotsteam.gdextension`,
  and its README tables which GodotSteam version supports which engine range.

## 6. Prove it

A pull request runs `check-project`, which is the tests and the checker at the new pin —
not the export pipeline. For a game, dispatch `publish-game.yaml` with `ref: <branch>` for
one target and confirm it produces a `game-*` artifact; that is the only pre-merge proof
that the toolchain, the patches, and the export presets still work together. The custom
editors rebuild after the merge, on push to `main`.

While `godot-infra` still publishes the previous minor, a repository can keep it covered
by passing `test-godot-versions` to `check-project`, which runs the tests at that version
as well as at the pin.

## 7. Breaking changes

A minor that breaks the project's own code is fixed in the same pull request; the checker
and the tests are what find it. `godot-plugin-std` has one extra decision: raising the
Godot version its README declares is a `feat!` release, and a game left on the old minor
stops receiving std updates, so raise it only when std's own code needs the new minor.

Commit with the `commit_title` from `upgrade-summary.json`, on one line, with no body or
trailers.
