##
## plugins/godot/checker/core/discovery.gd
##
## Discovery finds the files a run covers: every file a rule covers, or the files and
## directories named on the command line.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Rule := preload("rule.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## SCAN_ROOT is the fallback root for rules that declare none of their own.
const SCAN_ROOT: Array[String] = ["res://"]

## SCAN_EXCLUDE names the directories never scanned. Vendored addons are not ours to
## check, and script templates hold `_BASE_` placeholders that do not compile.
const SCAN_EXCLUDE: Array[String] = ["addons", "script_templates"]

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## discover returns every file any rule covers, sorted and free of duplicates.
static func discover(rules: Array[Rule]) -> Array[String]:
	var seen := {}

	for rule in rules:
		if not rule.files.is_empty():
			for rule_file in rule.files:
				if FileAccess.file_exists(rule_file):
					seen[rule_file] = true

			continue

		for rule_root in rule.roots if not rule.roots.is_empty() else SCAN_ROOT:
			scan(rule_root, rule.extensions, seen)

	var found: Array[String] = []
	found.append_array(seen.keys())
	found.sort()

	return found


## file_extensions returns every file extension a rule covers, free of duplicates.
static func file_extensions(rules: Array[Rule]) -> Array[String]:
	var found: Array[String] = []

	for rule in rules:
		if not rule.files.is_empty():
			continue

		for extension in rule.extensions:
			if extension not in found:
				found.append(extension)

	return found


## localize turns a relative or native absolute command-line path into a `res://` path.
static func localize(path: String) -> String:
	if path.begins_with("res://"):
		return path.simplify_path()

	if path.is_absolute_path():
		return ProjectSettings.localize_path(path)

	return "res://" + path.simplify_path()


## scan records every file under a directory carrying one of the given extensions.
##
## NOTE: Hidden directories are skipped outright, since `.git` alone holds ~11k files,
## and so is any directory holding a `.gdignore`, which the engine never imports.
static func scan(dir_path: String, extensions: Array[String], seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	if dir.file_exists(".gdignore"):
		return

	dir.list_dir_begin()

	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)

		if dir.current_is_dir():
			if not entry.begins_with(".") and entry not in SCAN_EXCLUDE:
				scan(path, extensions, seen)
		elif entry.get_extension() in extensions:
			seen[path] = true

		entry = dir.get_next()

	dir.list_dir_end()
