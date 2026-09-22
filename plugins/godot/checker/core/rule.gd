##
## plugins/godot/checker/core/rule.gd
##
## Rule is one check over one kind of file. Subclasses set `name`, `extensions` and
## optionally `roots` or `files` in `_init` and override `check`; only rules that can
## repair what they find override `fix` and `fixable`, and only rules the project
## configures override `configure`.
##

extends RefCounted

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Config := preload("config.gd")
const Problem := preload("problem.gd")
const SourceFile := preload("source_file.gd")

# -- CONFIGURATION ------------------------------------------------------------------- #

var name: StringName = &""
var extensions: Array[String] = []

## files limits the rule to these exact paths, whether or not a walk would reach
## them; an empty list covers every file with a matching extension.
var files: Array[String] = []

## roots limits the rule to these directories; an empty list covers the whole scan.
var roots: Array[String] = []

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## applies reports whether this rule covers the given file.
func applies(path: String) -> bool:
	if not files.is_empty():
		return path in files

	if path.get_extension() not in extensions:
		return false

	if roots.is_empty():
		return true

	for root in roots:
		if path.begins_with(root + "/"):
			return true

	return false


## check reports every problem this rule finds in the file.
func check(_file: SourceFile) -> Array[Problem]:
	return []


## configure hands the rule the parsed config, and runs before any file is checked.
func configure(_config: Config) -> void:
	pass


## fix repairs what `check` reported and returns whether the file changed.
func fix(_file: SourceFile) -> bool:
	return false


## fixable reports whether this rule implements `fix`.
func fixable() -> bool:
	return false


## loads_file reports whether this rule needs the engine to load the file, which
## succeeds only when every GDExtension the file depends on is present.
func loads_file() -> bool:
	return false
