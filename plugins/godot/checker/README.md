# Project checker

`check.gd` reports problems that a normal boot or import does not surface, and repairs
the ones that can be repaired. The `godot` plugin's edit hook runs it on each edited
file, `godot-check` runs it by hand, and `check-project.yaml` runs it over the whole
project in CI. Verified on Godot **4.7.2.stable.official**.

```sh
godot-check                         # every rule, every file
godot-check a.gd b.tscn             # only the given files
godot-check --fix a.tscn            # repair, then re-check
godot-check --list                  # print the rule registry
```

Outside Claude Code, `godot --headless -s <path to check.gd> -- <args>` from the project
root does the same.

| Rule | Covers | Reports | Fixable |
| --- | --- | --- | --- |
| `compile` | `.gd` | a script that does not compile, a promoted warning included | |
| `uid` | `.tscn` `.tres` | a header carrying no `uid=` | yes |
| `path-ref` | `.tscn` `.tres` | a reference that does not resolve, and a `res://` string that should be a uid | yes |
| `load` | `.tscn` `.tres` | a file that does not parse or instantiate | |
| `script-order` | `.tscn` `.tres` | a property assigned ahead of `script =` | |
| `nodepath` | `.tscn` | a `NodePath` export that resolves to null | |

Every rule covers the whole project apart from `addons/`, `script_templates/`, hidden
directories and any directory holding a `.gdignore`.

It exits non-zero when there is something to read, whether that is a problem found or
a repair applied, and cannot say which through the exit code. Follow a `--fix` run
with `godot --import --headless` so the assigned uids resolve. CI runs it without
`--fix`, since a check job reports rather than edits.

Add a rule only after a pitfall has bitten twice. A rule applies to every repository
that enables the plugin, so it must hold for any Godot project, not one layout.

## One Godot boot for every rule

The boot is almost the whole cost. The engine alone starts in 0.1s; booting a project
and running a no-op script takes 1.17s, and running `check.gd` over one file takes 1.17s
as well, so every rule applying to that file costs about 10ms between them. A second boot
would cost more than all of them together, which is why one boot runs every applicable
rule and why the edit hook must not add another. A full scan takes seconds, a CI cost
rather than an interactive one.

A rule declares its name, the extensions and roots it covers, and a check function.
Discovery, dispatch and `--list` all derive from the registry, so adding one touches no
shared code.

## Files a missing GDExtension makes unreadable

A GDExtension that did not load leaves every script naming its API unable to parse,
which would report the machine as a defect of the script. GodotSteam has no Linux build,
so a Linux runner has no `Steam` singleton, and neither does a checkout whose binaries
failed to load.

`KNOWN_EXTENSIONS` in `check.gd` maps each such extension to a pattern matching the
scripts that name its API; GodotSteam's is `\bSteam\.`. When the extension is in the
project but not loaded, a script matching the pattern, or a file reaching one through
its `[ext_resource]` headers, has the rules that load it held. Its text-only rules still
run, and the count is printed rather than swallowed. When the extension is loaded,
nothing is held, and no project configures anything. The list is hard-coded until
exclusions are generalized in
[#617](https://github.com/coffeebeats/godot-infra/issues/617).

Scripts are matched by what they name, not where they live. A script beside them that
never names `Steam` compiles anywhere, and the `.tres` files beside it are plain data,
so holding a whole directory would drop the scenes that depend on them from CI too.

## GDScript warnings the `compile` rule gates

A warning set to level 2 in `project.godot` is raised as a parse error, so the script
does not load and `compile` reports it. That makes a warning fail the editor, the edit
hook and CI through machinery that already exists; nothing here reads warnings, and
nothing needs to.

## What it does not cover

`project.godot` holds the same kind of fragile path string as a scene does, including
the main scene, the autoloads, the bus layout and the translation list. It is neither a
scene nor a resource, the engine reads it before any of this runs, and several of its
entries name files that carry no uid at all. Scripts are out of scope for `path-ref` too,
since `preload` breaks loudly at compile time and `compile` already catches that.

## Engine behavior the checker is shaped around

Each of these returns a plausible wrong answer rather than an error.

**A GDScript warning is reported only while a debugger is attached.** The analyzer
raises it either way, but the engine hands it to `EngineDebugger`, so a plain
`godot --headless -s` compiles every script in the project and prints not one. Adding
`-d` attaches the local debugger and surfaces them, but a runtime error under `-d` drops
into an unbounded `debug>` prompt loop that stdin cannot break out of. Promoting the
warning to an error instead reports it through the `compile` rule with no debugger
involved.

**`--check-only` does not register autoload singletons.** Every script referencing an
autoload reports a false `Identifier not found`. Loading a script from inside a running
`SceneTree` resolves them, which is what the `compile` rule does.

**A script that failed to parse still loads as non-null.** A null check proves
nothing. A compiled script always resolves a native base type, so an empty
`get_instance_base_type()` is the signal. `Script.reload()` looks like the cleaner
signal and cannot be used: it errors on any script that already has live instances.

**Re-loading the running script hangs the engine.** `ResourceLoader.load` with
`CACHE_MODE_IGNORE_DEEP` on the script executing under `-s` never returns, so
`compile` skips its own path. `ResourceLoader.has_cached()` is not a usable
substitute for that skip, since it reports true for scripts the process never loaded.

**A parse error in a `preload`ed script exits 0.** A broken entry script exits 1, but
a broken script it `preload`s prints `Failed to compile depended scripts` and the
process exits 0 having run nothing. That is why every rule lives in one file; a
checker split across files would report success while checking nothing.

**`SceneTree.quit(code)` collapses every non-zero code to 1** under `-s`, printing the
requested code to stderr and discarding it.

**A missing `[ext_resource]` target does not fail a load.** The engine prints a parse
error, then the scene loads, `instantiate()` succeeds, and the node that needed the
dependency is simply absent. `ResourceLoader.load()` returns a valid `PackedScene`, so
`load` sees nothing wrong and `path-ref` validates those headers instead. The engine
prefers the uid and falls back to the path, so a header is broken only when neither
resolves.

**A path held in a string property is never rewritten.** The engine's move and rename
fixup covers `ext_resource` headers and nothing else, so `StdScreen.scene_path`, its
attachment and dependency lists, and `StdConditionLoader.scene` point at nothing the
moment their target moves. It fails silently, since nothing reads the string until the
screen is pushed or the condition allows. A `uid://` reference survives, because the id
travels in the target's own header.

**Uid resolution reads a cache a script process does not rebuild.** A reference to a
target created since the last import reports as unknown, and a `res://` string naming
that target is left unconverted. Both settle after `godot --import --headless`. Ids
derive from the path, so every machine assigns the same uid to the same file.

**Quitting mid-load produces parse errors for well-formed scenes.** A
`godot --headless --quit` boot reports several scenes failing in `_parse_node_tag`, and
the failing set changes between runs; the engine is tearing down while threaded loads
are still in flight. Thirty frames is enough for the count to reach zero, so use
`--quit-after 30`. A boot is therefore not a substitute for the `load` rule, which loads
synchronously.

## The edit hook

`hooks/on_edit.sh` runs gdformat and gdlint on `.gd` edits, then `check.gd --fix` on any
file the checker covers, then the edited script's `<name>_test.gd` when one exists. A
repair is reported like a failure so the agent learns the file changed under it; the
engine cannot distinguish the two through an exit code, so the label stays neutral and
the checker's output says which it was.

It fires on `Edit` and `Write` only, so a file changed any other way stays unchecked
until `godot-check` or CI runs. Three things it must get right:

- The payload carries a **native absolute path**, which the engine cannot resolve
  against the project root. The hook converts it to a project-relative path with
  `cygpath`.
- Blocking feedback must go to **stderr**; anything written to stdout is not
  surfaced, and the failure appears as "No stderr output".
- Every headless run prints the engine banner, godotsteam's settings conversion, and
  the leaked-object and resources-in-use notices emitted during teardown. None is
  actionable and all of it buries the lines that are, so the hook drops those by
  exact match. Script errors and warnings are never filtered.

The test step is guarded on the test file actually existing. Pointed at nothing, GUT
spends about three seconds to report that nothing ran and exits 0, so the cost would be
invisible.
