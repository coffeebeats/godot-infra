---
name: upgrade-godot-project
description: Move a Godot repository to a newer engine release (patch, minor, or major). Rewrites the '.godot-version' pin and 'config/features', then reimports, rebases engine patches, and proves the export pipeline before the pull request merges.
user-invocable: true
disable-model-invocation: true
argument-hint: "<major.minor | major.minor.patch>"
---

Move this repository to the Godot release named in the request. It applies to anything
holding a `.godot-version` pin: a game, `godot-prototypes`, `godot-plugin-std`,
`godot-plugin-template`, and the `gut` and `GodotSteam` forks.

The pin is the only engine version a repository stores. `config/features` in
`project.godot` names the minor too, and the script below rewrites it; anything else that
needs a hand edit is a bug in this pipeline, not a step to add here.

A major release is a minor. `5.0` follows `4.11` the way `4.8` follows `4.7`.

Not every step applies to every repository:

| Repository | Steps | Why |
| --- | --- | --- |
| a game, `godot-prototypes` | all | it compiles, exports, and may carry engine patches |
| `godot-plugin-std`, `godot-plugin-template` | 1, 2, 3, 6, 7, 8 | no patches and no export; CI is `check-project` |
| `gut`, `GodotSteam` | 1, 2, 8 | no pull request and no project of their own: push to `main`, and `publish.yaml` republishes `dist` reimported at the new pin |

## 1. Resolve the release and the route

```sh
python3 <skill directory>/upgrade_godot_project.py resolve --godot-version <X.Y|X.Y.Z>
```

Every command here runs **from the repository root**, since `--project` defaults to the
working directory. The script lives beside this file, so give it an absolute path built
from the skill directory the harness names; a bare `upgrade_godot_project.py` would
resolve against the repository and not be found.

`X.Y` takes that minor's newest stable release. Where `python3` is absent, run it with
`uv run --no-project` instead.

The pin decides the route: `none` (already current), `patch` (same minor), or `minor`
(a new minor or major). Steps 4 and 5, and the API dump in step 3, are for a minor only.

**A minor needs `godot-infra` to publish its toolchain images first**, but only for a
repository that compiles or exports — a game, or `godot-prototypes`. The published minors
are the lines of
[`godot-versions.txt`](https://github.com/coffeebeats/godot-infra/blob/v6/godot-versions.txt);
add one with the `upgrade-godot` skill there. Moving first fails the compile job with
`Toolchain image not found: …`. std, the plugin template, and the forks never compile or
export, so they need nothing published; `check-project` and `package-addon` both install
the editor with `gdenv`.

## 2. Rewrite the pins

Branch `chore/godot/upgrade`, then:

```sh
SUMMARY="${TMPDIR:-/tmp}/upgrade-summary.json"
python3 <skill directory>/upgrade_godot_project.py upgrade \
  --godot-version <target> --output "$SUMMARY"
```

It writes `.godot-version` through `gdenv pin`, rewrites `config/features` on a minor, and
records what changed in the summary, which step 8 turns into the commit and the pull
request. Keep the summary outside the repository, as above; its default path is the
working directory, where nothing ignores it. A warning that `config/features` does not name
the old minor means the project was already inconsistent; read it before continuing.

A minor sometimes removes a project setting, which the editor then carries forward
untouched. `prune-settings --exclude <key>… --output "$SUMMARY"` drops the named keys from
`project.godot`, removes any section that empties, and records what it removed in the same
summary.

## 3. Reimport and check

```sh
gdenv install
godot --verbose --headless --quit --import
godot-check
```

`.godot/` is gitignored, so this is local proof rather than a diff. The checker skips
`addons/`, so in an addon repository it has nothing to report; `GodotSteam` has no
`project.godot` at all, and `package-addon` does its reimport itself.

On a minor, also regenerate the API reference, since engine signatures move between
minors:

```sh
python3 <skill directory>/../godot-api/dump_api.py
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

## 5. Bump the addon submodules (minor)

The `gut` and `GodotSteam` forks carry their own `.godot-version` and publish `dist`
reimported at it, so they run this skill before any consumer of theirs does; a game then
bumps its gitlink to the new `dist` commit. Two constraints decide whether they can move
at all:

- GUT publishes one line per Godot minor (9.7.1 targets 4.7.x), so the fork may need the
  upstream release for the new minor merged in first.
- GodotSteam declares a `compatibility_minimum` in `addons/godotsteam/godotsteam.gdextension`,
  and its README tables which GodotSteam version supports which engine range.

## 6. Prove it

A pull request runs `check-project`, which is the tests and the checker at the new pin —
not the export pipeline. Dispatch the repository's publish workflow with `ref: <branch>`
for one target and confirm it produces an artifact: `publish-game.yaml` in a game,
`deploy-template.yaml` in `godot-prototypes`. That is the only pre-merge proof that the
toolchain, the patches, and the export presets still work together. A repository that
carries engine patches also rebuilds its custom editors after the merge, on push to
`main`; one whose patch directory is empty does not.

`check-project` also takes `test-godot-versions`, which runs the tests at further versions
as well as at the pin. Use it to keep the old minor covered while other repositories are
still on it — with the caveat that GUT ships one build per Godot minor, so the old column
runs a GUT built for the new one.

## 7. Breaking changes

A minor that breaks the project's own code is fixed in the same pull request; the checker
and the tests find it. In `godot-plugin-std`, raising the Godot version its README declares
is a `feat!` release, and a game left on the old minor stops receiving std updates, so
raise it only when std's own code needs the new minor.

## 8. Commit

One line, the summary's `commit_title`, with no body or trailers. Open the pull request
with its `changes` and `warnings` as the body. The forks have no pull request: push to
`main`, and `publish.yaml` republishes `dist`.
