---
name: godot-check
description: Run the project checker (`godot-check`) over a Godot project — every rule and every file, or named files — and repair what it can with `--fix`. Use after a move, a rename, or any change the edit hook never saw, and whenever a run of it is asked for and the command is not on PATH.
user-invocable: true
argument-hint: "[--fix] [paths...]"
---

The checker reports the project-file mistakes an editor makes silently: a missing `uid=`
header, a file path held in a string property, an `[ext_resource]` naming a file that
does not exist, a property assigned ahead of `script =`, a `NodePath` export whose type
does not match, and the export declaration drifting from the presets.

The edit hook already runs it on every file an agent edits. This is for everything else.

## Running it

From the project root, where `project.godot` is:

```sh
godot-check                  # every rule, every file
godot-check a.gd b.tscn      # only the given files
godot-check --fix a.tscn     # repair, then re-check
godot-check --list           # print what each rule covers
```

`godot-check` is on `PATH` in Claude Code, which puts the plugin's `bin/` there. Where it
is not, run the checker through the engine instead — the same thing the command does:

```sh
godot --headless --path . -s ../../checker/check.gd -- [--fix] [paths...]
```

That path is relative to this skill's directory, whose location the harness names when it
loads the skill; pass it as an absolute path. This form needs only `godot`, so it is the
one to use outside Claude Code.

## Reading the result

It exits 1 when it reports a problem **or** applies a repair, so the exit code alone does
not say which happened; read the output. After a `--fix` that rewrote uids, run
`godot --import --headless` or the new uids do not resolve.

`../../checker/README.md` documents every rule, what `--fix` repairs, and how to add a
rule.
