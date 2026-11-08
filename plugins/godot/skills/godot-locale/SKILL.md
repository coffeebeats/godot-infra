---
name: godot-locale
description: Manage a Godot project's gettext catalogue with `godot-locale` — validate every '.pot' and '.po', merge the message template into the translations, and compile the '.mo' files the engine loads. Use after adding or changing a translatable string, and whenever a catalogue run is asked for.
user-invocable: true
argument-hint: "validate | update | compile [--verify]"
---

The catalogue is keyed by message ID, so a translation can silently drop a placeholder
its English text declares. `validate` is what catches that; gettext cannot. It checks
printf placeholders such as `%s` and named ones such as `{action}`. A translator must
keep every one, and may reorder only the named ones, since `%s` is filled in order and
`validate` cannot see two swapped.

## Running it

From the project root:

```sh
godot-locale validate          # every '.pot' and '.po' compiles and keeps its placeholders
godot-locale update            # merge 'messages.pot' into every '.po'
godot-locale compile           # build the '.mo' files the engine loads
godot-locale compile --verify  # also assert the transform is deterministic
```

Set `LOCALE_DIR` to the catalogue's directory where it is not `project/locale`.

Every `.po` but `en_US.po` is keyed by English text, so translators see English. Two
strings that share English text in different contexts stay separate entries, and each
compiles to its own translation.

`update` fills a new string with a guess from a similar translation and marks it
fuzzy. `compile` leaves every fuzzy entry out of the `.mo`, so the game shows the
English text until someone reviews the guess. Keep the translation if it is right or
empty it if not, and clear the `#, fuzzy` flag either way, since CI's release check fails
on any flag left in a committed `.po`.

`godot-locale` is on `PATH` in Claude Code, which puts the plugin's `bin/` there.
Elsewhere, run the file itself:

```sh
sh <skill directory>/../../bin/godot-locale validate
```

Run it from the project root. The script sits two directories above the skill, so build
the path from the skill directory the harness names and pass it absolute.

## What it needs

`msgfmt` and `msgmerge` from gettext, and `uv`, which fetches translate-toolkit for
poswap, pofilter and `compile`'s reverse swap. Unlike the checker, it is a shell script
and needs a POSIX shell, so on Windows it needs MSYS2 or Git Bash. Under a sandbox that
blocks either, the run has to happen outside the sandbox — ask for that rather than
reporting the catalogue as broken.

## Before running update or compile

gettext wraps long and non-ASCII lines differently between releases, so `update` and
`compile` rewrite a catalogue that CI produced with another version. Match the version CI
installs, or leave those two to CI. `validate` is unaffected.
