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
| `logging` | `.gd` | a bare `print` or `push_error` in a project that disallows engine output | |
| `uid` | `.tscn` `.tres` | a header carrying no `uid=` | yes |
| `path-ref` | `.tscn` `.tres` | a reference that does not resolve, a `res://` string that should be a uid, and a dependency whose `path` disagrees with its `uid` | yes |
| `load` | `.tscn` `.tres` | a file that does not parse or instantiate | |
| `script-order` | `.tscn` `.tres` | a property assigned ahead of `script =` | |
| `nodepath` | `.tscn` | a `NodePath` export that resolves to null | |
| `export-overrides` | `export_presets.cfg` | a preset value differing from `export_overrides.cfg` | yes |
| `export-ref` | `export_presets.cfg` | a file a preset keeps whose dependency that same preset excludes | |

Every rule covers the whole project apart from `addons/`, `script_templates/`, hidden
directories, any directory holding a `.gdignore`, and the files `.gdcheckrc` excludes.
`export-overrides` and `export-ref` are the exceptions; each covers one file and reads
the whole project, `addons/` included. `logging` covers nothing until `.gdcheckrc` turns
it on. The checker exits 1 for a problem or a repair alike, since the engine cannot
return a code that tells them apart. Follow `--fix` with `godot --import --headless` so
the assigned uids resolve.

Add a rule only after a pitfall has bitten twice, and add it to this file rather than a
second script. Booting the project costs 1.17s against about 10ms per rule per file, so
one boot has to run everything. A rule applies to every repository that enables the
plugin, so it must hold for any Godot project.

## Configuration

A project can carry a `.gdcheckrc` at its root. It uses Godot's `ConfigFile` syntax, the
format of `project.godot`, not the YAML of `.gdlintrc` and `.gdformatrc`.

```ini
[all]
excludes=["res://project/scratch/*"]
extensions={"res://addons/godotsteam/godotsteam.gdextension": ["Steam"]}

[logging]
disallow_engine_output=true

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
- `disallow_engine_output`, under `[logging]` only, turns that rule on; see below.

An invalid config is reported against `res://.gdcheckrc`, and nothing else is checked.

## Logging

A bare `print()` or `push_error()` bypasses whatever the project logs through, so the
line carries no logger name, no level and no timestamp, and nothing can filter or route
it. On Windows it can reach no reader at all. Without `debug/export_console_wrapper` on
the preset a build attaches to no terminal, and the line survives only in
`user://logs/godot.log`, which nothing points a reader at.

The rule reports eleven names, every output function of `@GlobalScope` and `@GDScript`:
`print`, `printerr`, `printraw`, `print_rich`, `print_verbose`, `printt`, `prints`,
`print_debug`, `print_stack`, `push_warning` and `push_error`. `Node.print_tree()`,
`print_tree_pretty()` and the static `print_orphan_nodes()` are callable bare inside a
node too, and the rule leaves them alone, as it does `assert()`. Each dumps engine state
or halts rather than emitting a log line a logger could carry.

The rule is off until a project turns it on. It covers no file until
`disallow_engine_output` is set, which `--list` shows as an empty Covers column. "Never
call `print()`" does not hold for a project with nothing to call instead, and a rule
here applies to every repository that enables the plugin.

A match has to be a call in code. Comments and strings are masked before the scan, so a
doc comment naming `print_rich()` reports nothing, and each masked span keeps the
newlines it held so a multi-line string shifts no line number under it. Anything dotted
is skipped, which lets a logger own a `print` method of its own, and so is anything
preceded by `func `, so a project may declare a method that shadows one of the eleven.
The cost is a missed `self.push_error()`, cheaper here than a false positive.

Two exemptions are structural rather than incidental. Their paths differ per repository,
so a project names them itself under `[logging] excludes`:

- **The sink the logger pushes through**, which is implemented on `push_error` and
  `push_warning`. There is nothing under it to log through.
- **CLI tooling**, whose stdout is its product and whose caller parses it. A logger
  would prefix that output with a category and, at the usual default level, drop it.

## Export overrides

Godot has no way to share a value between export presets. A project can declare those
values once in an `export_overrides.cfg` beside `export_presets.cfg`, and the
`export-overrides` rule writes them into every preset they name. A project without the
file is left alone.

The file uses `ConfigFile` syntax, like `.gdcheckrc`. A section name is a glob over
preset names, so a naming convention such as `[component-]arch-platform-storefront`
gives a section per storefront, platform, component or architecture. Keys are preset
keys in the presets file's own syntax, and a key in a preset's options block carries an
`options/` prefix.

```ini
[*]
export_filter="all_resources"
export_files=PackedStringArray()
exclude_filter=["addons/gut", "*_test.gd", "*/tests/*"]

[*-unknown]
exclude_filter=["addons/godotsteam"]

[*-macos-*]
options/application/bundle_identifier="com.example.game"
```

A preset takes every section whose glob matches its name, in file order.
`exclude_filter` and `include_filter` accumulate across those sections, deduplicated and
comma-joined, because a comma-separated glob string is the only preset value that
composes. Every other key is a value, and the last matching section wins.

A declared value must be the type the preset already holds, and the rule never adds a
key the preset lacks. Both are reported instead, since the editor cannot read back a key
it did not write. `export_files` is the one to watch, because the editor omits it under
`all_resources`; pin `export_filter` alone and a switch back to a file-selecting mode is
itself reported.

The rule also reports an entry naming nothing in the project, and a glob matching no
file. Both read the tree, so run it with submodules checked out, or every addon glob
looks dead.

A new preset made in the export dialog takes every value its categories declare on the
next `godot-check --fix export_presets.cfg`. Its own name, path and unmentioned options
are never read or written.

### Export globs

A filter entry names a path or a pattern, and the rule writes it as the glob Godot
needs:

| Entry | Written as | Because |
| --- | --- | --- |
| `addons/gut` | `addons/gut/*` | it names a directory in the project |
| `icon.svg` | `icon.svg` | it names a file |
| `*_test.gd` | as written | it contains a wildcard |

Godot's [export filters](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html#resource-options)
are not a `.gitignore`'s, in three ways worth knowing before writing one:

- `*` crosses `/`, so one star is recursive and `**` buys nothing.
- A pattern is tested against files, never directories, so `**/tests` matches nothing
  while `*/tests/*` matches everything under one.
- The exporter drops text files before any filter runs and adds a few after, so `*.md`,
  the icon named by `application/config/icon`, and the 4.8 MB `icudt_godot.dat` are
  unaffected by any pattern. An entry for one is reported by nothing, since the file
  does exist, so a dependency `export-ref` reports into it is the only signal.
- `*.po` is safe to drop. `project.godot` names the compiled `.mo`, and a runtime scan
  for a `.po` reads `user://`, never `res://`.

Prefer a directory per category. `*/editor/*` drops tooling from every build, and
`*/steam/*` under `[*-unknown]` drops a storefront from the builds that do not use it,
which holds only while nothing outside such a directory names something inside one.
`export-ref` is what keeps that honest.

### Running it

`godot-check --fix` writes the presets, **with the editor closed**. The editor caches
presets at startup and writes them back when the export dialog opens or it exits, so a
fix made underneath a running editor is undone
([godotengine/godot#39681](https://github.com/godotengine/godot/issues/39681)). CI only
reports; the fix is a local command and its result is committed.

The rule writes through `ConfigFile`, and only after proving it reproduces the file byte
for byte, which keeps every option and the file's line ending as they are. It also means
a file holding something `ConfigFile` cannot keep, such as a comment, is reported and
left alone.

## Export references

Dropping `*/steam/*` from a build is safe exactly while nothing that build keeps holds a
hard link into it. The declaration cannot show that, and neither can a boot of the
editor, where every file is present.

`export-ref` closes it. For each preset it assembles the same exclusion globs
`export-overrides` writes, works out which files they drop, and reports any
`[ext_resource]` header in a surviving file that points at a dropped one, naming every
preset that breaks:

```
res://project/main/system.tscn:9: [export-ref] dependency is excluded from
  main-x86_64-windows-unknown: res://addons/kit/system/debug/editor/bridge.tscn
```

A header is the whole of what it reports. A `uid://` or `res://` string in a property is
not a dependency, since the engine resolves it only when something asks, so a condition
loader naming an excluded scene is correct and is left alone.

The target is the path the header's uid resolves to rather than the `path` beside it,
which is why `path-ref` reports the two disagreeing. The exporter filters on the real
path, so measuring against the header's own text would read a file that moved.

It is keyed on `export_presets.cfg`, so the edit hook runs it when the presets change
and the whole-project run catches a crossing introduced by editing a scene.

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

Nothing here reaches what a stripped export template drops. The checker runs on an
editor build, which defines every class `disable_3d` removes and every method
`deprecated="no"` removes, so it cannot see either. Booting the packaged game is what
finds those, which is the `boot` job in `publish-game.yaml`.

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
- **A `preload`ed script that names anything unresolved hangs the engine**, measured on
  4.7.2 for an unknown global, a missing preload target and an unknown type; a plain
  syntax error exits 1 instead. Splitting the rules out also needs
  `ResourceLoader.load` on an absolute path, since the checker runs from outside the
  project and `preload` cannot reach its own files. Both are why every rule lives here.
- **`SceneTree.quit(code)` collapses every non-zero code to 1** under `-s`.
- **A missing `[ext_resource]` target does not fail a load.** The scene loads without
  the node that needed it, so `path-ref` validates headers rather than `load`.
- **A move rewrites `ext_resource` headers and nothing else**, so a `res://` string in a
  property such as `StdScreen.scene_path` points at nothing until something reads it. A
  `uid://` reference survives the move.
- **A script process does not rebuild the uid cache**, so a reference to a file created
  since the last import reports as unknown, and one to a file moved since then reports as
  resolving to a missing file. Both clear after `godot --import --headless`; the second
  reads like a real dangling reference and is not. Uids derive from the path, so every
  machine assigns the same one.
- **Quitting mid-load prints parse errors for well-formed scenes**, and the failing set
  changes between runs. A smoke test uses `--quit-after 30`, and `load` loads
  synchronously.

## The edit hook

`hooks/on_edit.sh` fires on `Edit` and `Write` only, so run `godot-check` after a move
or any other change it never sees. Its feedback goes to stderr, since stdout never
reaches the agent; a hook that writes there shows up as "No stderr output".

An edit to `export_overrides.cfg` is checked against `export_presets.cfg`, since that is
the file the rule covers and the pair is meaningless apart.
