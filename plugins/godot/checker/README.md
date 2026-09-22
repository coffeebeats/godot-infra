# Project checker

`check.gd` reports problems that a normal boot or import does not surface, and repairs
the ones it can. The `godot` plugin's edit hook runs it on each edited file,
`godot-check` runs it by hand, and `check-project.yaml` runs it over the whole project
in CI.

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
return a code that tells them apart.

The checker reads uids from the cache the last import wrote, and a script process never
rebuilds it. Run `godot --import --headless` after `--fix` and after creating or moving
a file. Until then a new file's uid reports as unknown and a moved file's as resolving
to a missing file, which looks like a real dangling reference and is not.

A move in the editor rewrites `[ext_resource]` headers and nothing else, so a `res://`
string in a property then points at nothing, while a `uid://` reference survives. That
is why `path-ref` asks for uids.

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
it.

The rule reports every output function of `@GlobalScope` and `@GDScript`: `print`,
`printerr`, `printraw`, `print_rich`, `print_verbose`, `printt`, `prints`,
`print_debug`, `print_stack`, `push_warning` and `push_error`. It passes over comments
and strings, anything dotted, such as a logger's own `print` method, and a declaration
that shadows one of the eleven, at the cost of missing `self.push_error()`.
`Node.print_tree()`, `print_tree_pretty()`, `print_orphan_nodes()` and `assert()` are
left alone, since none of them emits a log line.

Two exemptions are structural. Their paths differ per repository, so a project names
them under `[logging] excludes`:

- **The sink the logger pushes through**, which is implemented on `push_error` and
  `push_warning`.
- **CLI tooling**, whose stdout is its product and whose caller parses it.

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
  the icon named by `application/config/icon`, and `icudt_godot.dat` are unaffected by
  any pattern. An entry for one is reported by nothing, since the file does exist, so a
  dependency `export-ref` reports into it is the only signal.

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
res://main/menu.tscn:9: [export-ref] dependency is excluded from
  x86_64-windows-unknown: res://debug/editor/overlay.tscn
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
depending on such a script through `[ext_resource]` headers or a `preload` or `extends`.
The walk follows a dependency's uid, and its path only when the uid resolves to nothing,
as the engine does. The skipped files are listed. Text-only rules still run. A script
referring to a skipped one only by its `class_name` is not followed.

## Warnings

A warning set to level 2 in `project.godot` is raised as a parse error, so `compile`
reports it. A lower level prints only to an attached debugger, so the checker never
sees it.

## What it does not cover

`project.godot` holds fragile path strings too (the main scene, autoloads, bus layout,
translations), but it is neither a scene nor a resource, and the engine reads it before
any of this runs. Scripts are out of scope for `path-ref`, since a broken `preload`
already fails `compile`.

Nothing here sees what a stripped export template removes, since the checker runs on an
editor build that still defines it. Booting the packaged game finds that, which is the
`boot` job in `publish-game.yaml`.

## The edit hook

`hooks/on_edit.py` fires on an edit only — Claude Code's `Edit` and `Write`, Codex's
`apply_patch` — so run `godot-check` after a move or any other change it never sees. A
patch that touches several files is checked in one run. An edit to `export_overrides.cfg`
is checked against `export_presets.cfg`, the file the rule covers.

## Adding a rule

Add a rule only after a pitfall has bitten twice. A rule applies to every repository
that enables the plugin, so it must hold for any Godot project, and it runs in the same
boot as every other rule, since booting costs far more than any rule does.

`check.gd` is the entry point, and it preloads everything else. `core/` holds what every
run needs: the config, the per-file cache, discovery and the GDExtension gate. `lib/`
holds what more than one rule reads. `rules/` holds one file per rule, named for the
rule with `_` in place of `-`.

1. Write `rules/<name>.gd`. It extends `"../core/rule.gd"`, sets `name`, `extensions`
   and optionally `roots` or `files` in `_init`, and overrides `check`. A rule that can
   repair what it finds also overrides `fix` and `fixable`, and one a project configures
   overrides `options` and `configure`.
2. Add it to `RULES` in `check.gd`, whose order is the order the rules run in.
3. Add files that break it to `tests/checker/violations/`, along with any it must pass
   over. Run `uv run scripts/test_project_checker.py --update` and review the lines it
   adds.
4. Add its row to the table above.

A rule preloads from `core/` and `lib/`, never another rule; what two rules share moves
into `lib/`. No file declares a `class_name`, since the checker runs inside a project
whose class cache it must not add to.
