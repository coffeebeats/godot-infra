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
| `path-ref` | `.tscn` `.tres` | a reference that does not resolve, a `res://` string that should be a uid, and a dependency whose `path` disagrees with its `uid` | yes |
| `load` | `.tscn` `.tres` | a file that does not parse or instantiate | |
| `script-order` | `.tscn` `.tres` | a property assigned ahead of `script =` | |
| `nodepath` | `.tscn` | a `NodePath` export that resolves to null | |
| `export-overrides` | `export_presets.cfg` | a preset value differing from `export_overrides.cfg` | yes |

Every rule covers the whole project apart from `addons/`, `script_templates/`, hidden
directories, any directory holding a `.gdignore`, and the files `.gdcheckrc` excludes.
`export-overrides` is the exception: it covers one file and reads the whole project,
`addons/` included, to decide whether a glob still matches anything. The checker exits 1
for a problem or a repair alike, since the engine cannot return a code that tells them
apart. Follow `--fix` with `godot --import --headless` so the assigned uids resolve.

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

## Export overrides

Godot has no way to share a value between export presets. A project shipping several
keeps the same decision in each of them by hand, and nothing notices when one drifts. A
project can instead declare those values once in an `export_overrides.cfg` beside
`export_presets.cfg`, and the `export-overrides` rule writes them into every preset they
name. A project without the file is left alone.

The file uses `ConfigFile` syntax, like `.gdcheckrc`. A section name is a glob over
preset names, so a naming convention such as `[component-]arch-platform-storefront`
gives a section per storefront, platform, component or architecture. Keys are preset
keys in the presets file's own syntax, and a key in a preset's options block carries an
`options/` prefix.

Adding a preset is where that pays off. Make it in the export dialog as usual, run
`godot-check --fix export_presets.cfg`, and it takes every value its categories declare,
so a new storefront or architecture starts out agreeing with its siblings instead of
being copied across by hand. Keep using the dialog for everything else; a preset's own
values, its name, its path and every option the declaration does not mention, are never
read or written.

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

A declared value must be the type the preset already holds. A value of any other type is
reported rather than written, since the editor cannot read back a key whose type it did
not write.

A filter entry names a path or a pattern, and the rule writes it as the glob Godot
needs:

| Entry | Written as | Because |
| --- | --- | --- |
| `addons/gut` | `addons/gut/*` | it names a directory in the project |
| `icon.svg` | `icon.svg` | it names a file |
| `*_test.gd` | as written | it contains a wildcard |

Godot's globs are not a `.gitignore`'s. `*` crosses `/`, so one star is recursive and
`**` buys nothing. A pattern is tested against files, never directories, so `**/tests`
matches nothing while `*/tests/*` matches everything under one. The exporter also drops
text files before any filter runs, so `*.md` and `LICENSE.*` exclude nothing that was
going to ship.

The rule reports an entry that names nothing in the project, and a glob that matches no
file. Both read the tree, so run it with submodules checked out; without them every
addon glob looks dead.

Declare only the keys worth pinning, which are the ones a whole category must agree on.

The rule never adds a key to a preset, because the editor decides which keys a preset
carries and would drop one it did not write. A declared key the preset lacks is
reported instead, and the usual cause is that the key does not apply in that preset's
current shape. `export_files` is the one to know: the editor writes it only under the
`scenes`, `resources` and `exclude` filters, and omits it under `all_resources`, so
pinning it alongside `export_filter="all_resources"` reports a missing key forever.
Pinning `export_filter` alone is enough, since a switch back to a file-selecting mode is
itself reported and fixed.

### Running it

`godot-check --fix` writes the presets, **with the editor closed**. The editor caches
presets at startup and writes them back when the export dialog opens or it exits, so a
fix made underneath a running editor is undone
([godotengine/godot#39681](https://github.com/godotengine/godot/issues/39681)). CI only
reports; the fix is a local command and its result is committed, as it is for every
other rule here.

The rule writes through `ConfigFile`, the editor's own writer, and only after proving it
reproduces the file byte for byte. That proof keeps every option the editor wrote, and
the file's line ending, exactly as they are. It also means the rule reports and leaves
alone a file holding something `ConfigFile` cannot keep, such as a comment or
hand-placed spacing.

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
  since the last import reports as unknown until `godot --import --headless`. Uids derive
  from the path, so every machine assigns the same one.
- **Quitting mid-load prints parse errors for well-formed scenes**, and the failing set
  changes between runs. A smoke test uses `--quit-after 30`, and `load` loads
  synchronously.

## The edit hook

`hooks/on_edit.sh` fires on `Edit` and `Write` only, so run `godot-check` after a move
or any other change it never sees. Its feedback goes to stderr, since stdout never
reaches the agent; a hook that writes there shows up as "No stderr output".

An edit to `export_overrides.cfg` is checked against `export_presets.cfg`, since that is
the file the rule covers and the pair is meaningless apart.
