# Project checker

`check.gd` reports problems that a normal boot or import does not surface, and repairs
the ones it can. The `godot` plugin's edit hook runs it on each edited file,
`godot-check` runs it by hand, and `check-project.yaml` runs it over the whole project
in CI. Verified on Godot **4.7.2.stable.official**.

```sh
godot-check                         # every rule, every file
godot-check a.gd b.tscn             # only the given files
godot-check --fix a.tscn            # repair, then re-check
godot-check --list                  # print the rule registry
```

Outside Claude Code, run `godot --headless -s <path to check.gd> -- <args>` from the
project root.

| Rule | Covers | Reports | Fixable |
| --- | --- | --- | --- |
| `compile` | `.gd` | a script that does not compile, a promoted warning included | |
| `uid` | `.tscn` `.tres` | a header carrying no `uid=` | yes |
| `path-ref` | `.tscn` `.tres` | a reference that does not resolve, and a `res://` string that should be a uid | yes |
| `load` | `.tscn` `.tres` | a file that does not parse or instantiate | |
| `script-order` | `.tscn` `.tres` | a property assigned ahead of `script =` | |
| `nodepath` | `.tscn` | a `NodePath` export that resolves to null | |

Every rule covers the whole project apart from `addons/`, `script_templates/`, hidden
directories, any directory holding a `.gdignore`, and the files `.gdcheckrc` excludes. It exits 1 for a problem or a
repair alike, since the engine cannot return a code that tells them apart. Follow
`--fix` with `godot --import --headless` so the assigned uids resolve.

Add a rule only after a pitfall has bitten twice. A rule applies to every repository
that enables the plugin, so it must hold for any Godot project.

## One boot for every rule

Booting the project costs 1.17s, against about 10ms for every rule checking one file.
One boot runs every rule, and the edit hook must not add another.

## Configuration

A project can carry a `.gdcheckrc` at its root. It uses Godot's `ConfigFile` syntax, the
format of `project.godot`, not the YAML of `.gdlintrc` and `.gdformatrc`.

```ini
[all]
excludes=["res://project/scratch/*"]
extensions={"res://addons/godotsteam/godotsteam.gdextension": ["Steam"]}

[nodepath]
excludes=["res://project/menus/legacy.tscn"]
```

Section `[all]` applies to every rule, and any other section to the rule it names, as
`godot-check --list` prints it.

- `excludes` lists `res://` globs, where `*` also matches `/`. A file excluded under
  `[all]` is never checked, fixed, or counted, even when named on the command line, so
  the edit hook stays quiet on it. Under a rule's section, only that rule skips it.
- `extensions`, under `[all]` only, maps each GDExtension the project uses to the global
  names it defines.

An invalid config is reported against `res://.gdcheckrc`, and nothing else is checked.

## GDExtensions that did not load

A script naming the API of a GDExtension that did not load fails to parse, which reports
the machine rather than the script. GodotSteam has no Linux build, so a Linux runner has
no `Steam` singleton.

While an extension listed under `extensions` is unloaded, the rules that load files skip
each script using one of its names in code, outside comments and strings, and each file
depending on such a script through `[ext_resource]` headers or a `preload` or `extends`
path. The skipped files are listed. Text-only rules still run. A script referring to a
skipped one only by its `class_name` is not followed.

## Warnings

A warning set to level 2 in `project.godot` is raised as a parse error, so `compile`
reports it. The engine prints warnings only to an attached debugger, and `-d` hangs at a
`debug>` prompt on the first runtime error, so nothing else surfaces them.

## What it does not cover

`project.godot` holds fragile path strings too (the main scene, autoloads, bus layout,
translations), but it is neither a scene nor a resource, and the engine reads it before
any of this runs. Scripts are out of scope for `path-ref`, since a broken `preload`
already fails `compile`.

## Engine behavior the checker works around

Each of these returns a plausible wrong answer rather than an error.

- **`--check-only` does not register autoloads**, so every script naming one reports a
  false `Identifier not found`. `compile` loads scripts inside a running `SceneTree`
  instead.
- **A script that fails to parse still loads as non-null.** A compiled script always
  has a native base type, so `compile` checks `get_instance_base_type()`.
  `Script.reload()` cannot stand in, since it errors on any script with live instances.
- **Re-loading the running script hangs the engine**, so `compile` skips its own path.
  `ResourceLoader.has_cached()` cannot stand in for that skip, since it reports true for
  scripts the process never loaded.
- **A parse error in a `preload`ed script exits 0** having run nothing, which is why
  every rule lives in one file.
- **`SceneTree.quit(code)` collapses every non-zero code to 1** under `-s`.
- **A missing `[ext_resource]` target does not fail a load.** The scene loads without
  the node that needed it, so `path-ref` validates headers rather than `load`.
- **A move rewrites `ext_resource` headers and nothing else**, so a `res://` string in a
  property such as `StdScreen.scene_path` points at nothing until something reads it. A
  `uid://` reference survives the move.
- **A script process does not rebuild the uid cache**, so a reference to a file created
  since the last import reports as unknown until `godot --import --headless`. Uids derive
  from the path, so every machine assigns the same one.
- **Quitting mid-load prints parse errors for well-formed scenes**, and the failing set
  changes between runs. A smoke test uses `--quit-after 30`, and `load` loads
  synchronously.

## The edit hook

`hooks/on_edit.sh` fires on `Edit` and `Write` only, so run `godot-check` after a move
or any other change it never sees. Its feedback goes to stderr, since stdout never
reaches the agent; a hook that writes there shows up as "No stderr output".
