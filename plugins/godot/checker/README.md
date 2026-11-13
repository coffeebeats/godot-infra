# Project checker

`check.gd` reports problems that a normal boot or import does not surface, and repairs
the ones it can. The `godot` plugin's edit hook runs it on each edited file,
`godot-check` runs it by hand, and `check-project.yaml` runs it over the whole project
in CI.

```sh
godot-check                         # every rule, every file
godot-check a.gd b.tscn             # only the given files
godot-check --fix a.tscn            # repair, then re-check
godot-check --report=out.json       # also write the findings as JSON
godot-check --list                  # print the rule registry
```

Where the plugin's `bin/` is not on `PATH`, as under Codex, run
`godot --headless -s <path to check.gd> -- <args>` from the project root. The
`godot-check` skill carries that form.

| Rule | Covers | Reports | Fixable |
| --- | --- | --- | --- |
| `compile` | `.gd` | a script that does not compile, a promoted warning included, with each error the engine raised | |
| `logging` | `.gd` | a bare `print` or `push_error` in a project that disallows engine output | |
| `preload` | `.gd` `.tscn` `.tres` | a `preload` of a scene or resource carrying a script, a `preload` it cannot follow, a load in a static initializer, and a built-in script | |
| `self-preload` | `.gd` | a `preload`, or a load in a static initializer, of a file that loads the script back | |
| `resource-loader` | `.gd` | a threaded load outside the project's loader, and a bare `load()`, in a project that names its loader | |
| `disable-3d` | `.gd` | a 3D class, or a load of a 3D-only script as the script compiles, in a project whose 2D builds leave out 3D | |
| `uid` | `.tscn` `.tres` | a header carrying no `uid=` | yes |
| `path-ref` | `.tscn` `.tres` | a reference that does not resolve, a `res://` string that should be a uid, and a dependency whose `path` disagrees with its `uid` | yes |
| `load` | `.tscn` `.tres` | a file that does not parse or instantiate, and a scene node instantiated missing, as another class, or without its script, with the first error the engine raised | |
| `script-order` | `.tscn` `.tres` | a property assigned ahead of `script =` | |
| `nodepath` | `.tscn` | a `NodePath` export that resolves to null | |
| `export-overrides` | `export_presets.cfg` | a preset value differing from `export_overrides.cfg` | yes |
| `export-ref` | `export_presets.cfg` | a file a preset keeps whose dependency that same preset excludes | |

Every rule covers the whole project apart from `addons/`, `script_templates/`, hidden
directories, any directory holding a `.gdignore`, and the files `.gdcheckrc` excludes.
`export-overrides` and `export-ref` are the exceptions; each covers one file and reads
the whole project, `addons/` included. `logging`, `resource-loader` and `disable-3d`
cover nothing until `.gdcheckrc` turns them on. The checker exits 1 for a problem or a
repair alike; the `--report` file tells them apart, and `check.gd`'s header lists what
it holds. An error in the checker's own scripts fails the run too: one raised while a
rule checks a file is a problem on that file, and one that stops the run exits 1 with a
line saying so.

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

[disable-3d]
disallow_3d_classes=true
scripts_3d=["res://project/map/3d/*", "res://*_3d.gd"]

[logging]
disallow_engine_output=true

[nodepath]
excludes=["res://project/menus/legacy.tscn"]

[preload]
excludes=["res://*_test.gd"]

[resource-loader]
allow=["res://addons/std/load/*"]
```

Section `[all]` applies to every rule, and any other section to the rule it names, as
`godot-check --list` prints it.

- `excludes` lists `res://` globs, where `*` also matches `/`. A file excluded under
  `[all]` is never checked, fixed, or counted, even when named on the command line, so
  the edit hook stays quiet on it. Under a rule's section, only that rule skips it.
- `extensions`, under `[all]` only, maps each GDExtension the project uses to the global
  names it defines.
- `disallow_3d_classes`, under `[disable-3d]` only, turns that rule on, and
  `scripts_3d` lists the `res://` globs of the scripts only a 3D game loads; see
  [Builds without 3D](#builds-without-3d).
- `disallow_engine_output`, under `[logging]` only, turns that rule on; see below.
- `allow`, under `[resource-loader]` only, lists the `res://` globs of the files that
  implement the project's loader, and turns that rule on; see
  [Loading](#loading).

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

## Loading

Godot 4.6 to 4.8 deadlock when a thread compiling a GDScript waits in the resource
loader for something another thread is loading, and that load needs the script cache.
A compile holds the cache's lock throughout, so whatever a script loads while it
compiles must never wait on another thread. `preload` and `self-preload` keep it so,
and are on in every project, since they state engine facts.

`preload` reports, in a script:

- a `preload` of a file that carries a script: a scene or resource that holds one or
  loads one through its `[ext_resource]` headers to any depth; a binary `.scn` or
  `.res`, which cannot be proven free of one without loading it; or an imported scene,
  whose importer can attach one. Export the `PackedScene` or `Resource` and set it in
  the scene instead; a scene's own dependencies are waited on from the loader, not from
  a compile. A script is fine to preload, since it comes from the script cache.
- a `preload` of anything but one string literal, which cannot be followed.
- any load in a `static var` initializer or in `_static_init`, which run before the lock
  is released: `load`, `ResourceLoader.load`, its threaded calls, and a method named
  `load_now`.

In a scene or resource it reports a built-in script, which compiles on whichever thread
loads its file and cannot be followed here.

A script compiled only at boot, such as an autoload, is reported though nothing can be
loading then; an export is the fix either way. GUT loads a test script while it collects
the tests, before any can start a load, so a project usually adds
`[preload] excludes=["res://*_test.gd"]`.

`self-preload` reports a `preload`, or a load in a static initializer, of a file that
loads the script back, such as the scene whose root carries it or a script preloading
that scene. That fails with no second thread involved, leaving the scene cached
without its script or the script invalid. Scripts that only preload one another are
fine, since the script cache allows the cycle. It is a rule of its own so that excluding
a file from `preload` cannot turn it off.

Both rules report a load in a lambda inside a static initializer's brackets, though its
body runs only when something calls it, since the checker cannot tell whether that
happens while the script compiles. Store a named `static func` instead, as
`{"a": _load_a}` rather than `{"a": func(): return load(...)}`, and call it only once
the script has compiled, since the checker does not follow the call.

`resource-loader` keeps a project with its own loader, such as std's `StdLoader`, from
bypassing it. It reports `load_threaded_request`, `load_threaded_get` or
`load_threaded_get_status` named in code or in a string, and a bare `load()` or
`ResourceLoader.load()`, which blocks beside whatever the loader has in flight. A file
declaring its own `func load(` is spared a bare `load()`, which calls that method, but
not `ResourceLoader.load()`. It covers nothing until `allow` lists the files that
implement the loader, and it skips those files.

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
the machine rather than the script. An addon pinned to a commit with no library for the
runner's platform leaves its names undefined there.

While an extension listed under `extensions` is unloaded, the rules that load files skip
each script using one of its names in code, outside comments and strings, and each file
depending on such a script through `[ext_resource]` headers or a `preload` or `extends`.
The walk follows a dependency's uid, and its path only when the uid resolves to nothing,
as the engine does. The skipped files are listed. Text-only rules still run. A script
referring to a skipped one only by its `class_name` is not followed.

## Builds without 3D

A 2D game's export template is often built with `disable_3d`, which drops `Node3D` and
everything inheriting from it, most classes named with `3D`, the XR and glTF classes,
the primitive meshes and `WorldEnvironment`. The engine then fails to parse a script
naming one, along with every script depending on it. The editor keeps 3D, so nothing
shows until a 2D export boots.

`disable-3d` reports, in a script:

- a 3D class named in code. An engine class counts when its name holds `3D` or opens
  with `FBX`, `GLTF`, `OpenXR` or `XR`, or when it inherits from a root `disable_3d`
  drops, unless 2D builds still register it, as they do `Texture3D` and `AStar3D`. The
  lists follow the 4.7.2 engine; a listed class an older engine lacks matches nothing.
- a project's 3D class, meaning a global class whose name holds `3D` or whose script
  `scripts_3d` matches. The prefixes name engine modules, so a project's `XRayScanner`
  passes.
- an `extends` or `preload` of a 3D-only script, or a load of one in a static
  initializer, since each loads it as the script compiles. A path is followed bare,
  relative, as `res://` or as `uid://`.

It passes over comments, strings, node paths such as `$Camera3D` or `$A/Camera3D`, and
anything dotted, so `node.is_class(&"Node3D")` tests a node without naming the class. A
`load()` outside a static initializer runs later, when the game can choose not to, and
is left alone. The 3D-only scripts are skipped. A project's tests run on the editor's
full build, so a project usually adds `excludes=["res://*_test.gd"]` under
`[disable-3d]`.

A 2D-only class the match catches by its name belongs in the rule's allowlist, which
takes a release of this repository.

## Warnings

A warning set to level 2 in `project.godot` is raised as a parse error, so `compile`
reports it. A lower level prints only to an attached debugger, so the checker never
sees it.

## What it does not cover

`project.godot` holds fragile path strings too (the main scene, autoloads, bus layout,
translations), but it is neither a scene nor a resource, and the engine reads it before
any of this runs. Scripts are out of scope for `path-ref`, since a broken `preload`
already fails `compile`.

`load` compares each node a scene declares with the node it instantiates, which must
exist, be of the declared class, and carry the declared script. A misspelled property, a
value of the wrong type, and an error a script raises in `_init` still pass it; GUT
catches the last.

Nothing here sees what a stripped export template removes, since the checker runs on an
editor build that still defines it; `disable-3d` predicts the one module a 2D build
most often leaves out, from names alone. Booting the packaged game finds the rest, which
is the `boot` job in `publish-game.yaml`.

## The edit hook

`hooks/on_edit.py` fires on an edit only — Claude Code's `Edit` and `Write`, Codex's
`apply_patch` — so run `godot-check` after a move or any other change it never sees. A
patch that touches several files is checked in one run. An edit to `export_overrides.cfg`
is checked against `export_presets.cfg`, the file the rule covers. Only the edited files
are checked, so a scene a renamed node or a changed `extends` breaks elsewhere waits for
the next whole-project run.

An edited file belongs to the nearest `project.godot` above it, no higher than the
directory the session works in, so a project need not sit at the repository root. A
script's test is its `<name>_test.gd`, the name `check-project.yaml` runs GUT with, or
the one `.gutconfig.json` names through its `prefix` and `suffix`. The hook looks beside
the script first, then in the directories the file lists.

The tools run at once, so an edit takes as long as the slowest of them, which is GUT
when a script has a test and the checker otherwise. GUT runs that test alone, not the
directories `.gutconfig.json` lists, and the hook reads a failure from its JUnit export
rather than its output, which carries every test's logging. It reads the checker's
`--report` for the same reason, since a checker run boots the project's autoloads and
its output carries whatever they print. GUT places an error a script raised at line -1,
so the report adds where the engine raised it. GUT skips a test that does not load and
still exits 0, so the hook reports a test the export holds nothing from. The checker
compiles each test too, and the hook leaves the tests out of its report when the
checker finds a script that does not compile.

gdformat rewrites a script it would reformat once the other tools are done reading it,
and the report says so. A tool that runs past two minutes is stopped, along with
everything it started, and the report as a whole stays under 8,000 characters, below the
10,000 at which Claude Code moves hook output to a file.

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
