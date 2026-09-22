---
name: godot-api
description: Look up an exact Godot, addon, or project API (a class's methods, signatures, parameters, signals, constants, or enum values) against a generated reference instead of recalling it. Use when unsure whether a method exists, what it is named, what it returns, or what arguments it takes.
user-invocable: true
argument-hint: "<ClassName> [member]"
---

Answer API questions by grepping a generated reference, never from memory. Engine APIs shift between minor versions and addons such as `std` are private libraries with no public docs, so a recalled signature is a guess that compiles only by luck.

## When to use something else

Grep the source instead when the question is "what does this do" about a single addon or project symbol, and you already know where it lives:

```sh
grep -rn -B6 "func load_save_data" addons/std/save/
```

The `##` comment above the definition is the same prose the dump carries, and it costs no dump. The dump earns its keep in two cases the source cannot answer:

- **Engine classes**, which are not in the repository at all. This is the main case, as for `ResourceUID.create_id_for_path`, `RenderingServer.frame_post_draw`, `DisplayServer` capability checks.
- **Inherited members**, where the dump flattens the chain into one file per class. `StdSaveFile` inherits through `StdConfigWriterBinary`, `StdConfigWriter`, `StdFileWriter`, and `StdThreadWorker`; the source makes you walk it by hand.

## Generating the dump

The reference lives in the project's `.godot/agent-api/`, so it is absent in a fresh clone and stale after an addon bump or an edit to any `##` doc comment. Regenerate it whenever a lookup comes back empty or contradicts the code:

```sh
python3 <skill directory>/dump_api.py
```

Run it **from the project root**, and give the script an absolute path. The harness names
this skill's directory when it loads the skill; a bare `dump_api.py` would resolve against
the project instead. The script finds the project through `CLAUDE_PROJECT_DIR`, or through
`git rev-parse` in the working directory, so running it from anywhere else writes the dump
into whatever repository that directory belongs to.

Takes about 15 seconds and prints a class count per tree. It removes each tree before rewriting it, so a renamed or deleted class never lingers.

## Layout

| Tree | Holds | Prose? |
| --- | --- | --- |
| `.godot/agent-api/engine/` | ~1080 built-in classes, from ClassDB reflection | **No** |
| `.godot/agent-api/addons/<name>/` | each addon, from its `##` comments | Yes |
| `.godot/agent-api/<dir>/` | each top-level project directory holding GDScript | Yes |

**The engine tree carries signatures but no descriptions**, since a release binary does not embed the documentation text. For what a method does, use the online docs for the pinned version, or read how the project already calls it.

Engine classes are split across `doc/classes/` and `modules/*/doc_classes/`, so find the file rather than assuming a path:

```sh
find .godot/agent-api/engine -name 'ResourceUID.xml'
```

## Looking something up

The files are XML, so grep the tag, not free text:

```sh
# every method on a class, with its file
grep -o '<method name="[^"]*"' "$(find .godot/agent-api/engine -name 'ResourceUID.xml')"

# one method's full signature: return type, then each parameter in order
grep -A6 '<method name="create_id_for_path"' "$(find .godot/agent-api/engine -name 'ResourceUID.xml')"

# an addon or project class, which is one predictable file
grep -A8 '<method name="load_save_data"' .godot/agent-api/addons/std/StdSaveFile.xml

# properties, signals, constants and enum values
grep -E '<member name=|<signal name=|<constant name=' .godot/agent-api/project/Main.xml

# which class has this member, as a method, signal, property or constant
grep -rl 'name="frame_post_draw"' .godot/agent-api/
```

`<return type=...>` gives the return, `<param index=... name=... type=... />` gives arguments in order, and an `enum="Class.EnumName"` attribute on either means the int is an enum whose values are `<constant>` entries in that class's file.

## Verification

End every lookup by quoting the line you found, not a paraphrase of it. If a grep returns nothing, the answer is not "the method does not exist" until you have confirmed the class file itself is present, since an empty result far more often means the dump is stale or the class name is spelled differently. Regenerate, then say the method does not exist.
