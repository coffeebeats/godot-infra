##
## plugins/godot/checker/lib/export_declaration.gd
##
## ExportDeclaration reads `res://export_overrides.cfg`, which declares values once for
## every export preset whose name a section globs, and assembles what each preset should
## hold. `export-overrides` writes that into the presets, and `export-ref` checks it.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Config := preload("../core/config.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## LIST_KEYS name the preset keys declared as a list and accumulated across every
## section matching a preset, which is every key holding a comma-separated glob.
const LIST_KEYS := ["exclude_filter", "include_filter"]

## OPTIONS_PREFIX marks a declared key belonging to a preset's options block.
const OPTIONS_PREFIX := "options/"

## OVERRIDES_PATH is the declaration, kept beside the presets it overlays.
const OVERRIDES_PATH := "res://export_overrides.cfg"

## PRESETS_PATH is the presets file the editor writes and the declaration overlays.
const PRESETS_PATH := "res://export_presets.cfg"

# -- INITIALIZATION ------------------------------------------------------------------ #

## _tree holds every file `tree` returns, once the project is walked.
static var _tree := PackedStringArray()

## _walked records whether the project has been walked into `_tree`.
static var _walked: bool = false

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## assemble returns every key the sections matching a preset name declare for it, each
## `LIST_KEYS` entry accumulated into the glob string the preset holds.
static func assemble(preset_name: String, overrides: ConfigFile) -> Dictionary:
	var declared := {}
	var lists := {}

	for section in overrides.get_sections():
		if not preset_name.match(section):
			continue

		for key in overrides.get_section_keys(section):
			var value: Variant = overrides.get_value(section, key)

			if key not in LIST_KEYS:
				declared[key] = value
				continue

			if not Config.is_strings(value):
				continue

			var globs: PackedStringArray = lists.get(key, PackedStringArray())

			for entry: String in value:
				var glob := to_glob(entry)
				if glob != "" and glob not in globs:
					globs.append(glob)

			lists[key] = globs

	for key: String in lists:
		declared[key] = ",".join(lists[key])

	return declared


## lines returns a file's contents split on newlines, carriage returns removed.
static func lines(path: String) -> PackedStringArray:
	return FileAccess.get_file_as_string(path).replace("\r\n", "\n").split("\n")


## preset_names maps each preset's section to the name it carries.
static func preset_names(presets: ConfigFile) -> Dictionary:
	var names := {}

	for section in presets.get_sections():
		if section.ends_with(".options"):
			continue

		var preset_name: String = presets.get_value(section, "name", "")
		if preset_name != "":
			names[section] = preset_name

	return names


## read returns the project's declaration, or null when it is absent or does not parse.
## `export-overrides` reports a declaration that does not parse.
static func read() -> ConfigFile:
	if not FileAccess.file_exists(OVERRIDES_PATH):
		return null

	var overrides := ConfigFile.new()
	if overrides.load(OVERRIDES_PATH) != OK:
		return null

	return overrides


## target_key returns the preset key a declared key names.
static func target_key(key: String) -> String:
	return key.trim_prefix(OPTIONS_PREFIX)


## target_section returns the preset section a declared key belongs in.
static func target_section(section: String, key: String) -> String:
	return section + ".options" if key.begins_with(OPTIONS_PREFIX) else section


## to_glob returns the exporter glob an entry names, recursive for a directory and as
## written for a file or a pattern, or an empty string when it names nothing.
static func to_glob(entry: String) -> String:
	if entry.contains("*") or entry.contains("?"):
		return entry

	var path := entry if entry.begins_with("res://") else "res://" + entry

	if DirAccess.dir_exists_absolute(path):
		return entry.trim_suffix("/") + "/*"

	if FileAccess.file_exists(path):
		return entry

	return ""


## tree returns every file the exporter's walk reaches, without the scheme. The project
## is walked once per run.
static func tree() -> PackedStringArray:
	if not _walked:
		_walked = true
		_collect("res://", _tree)

	return _tree


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	assert(
		not OS.is_debug_build(),
		"Invalid config; this 'Object' should not be instantiated!"
	)


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _collect appends every file under a directory, passing over the directories the
## exporter ignores, those named with a leading period and those holding a `.gdignore`.
static func _collect(dir_path: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null or dir.file_exists(".gdignore"):
		return

	dir.list_dir_begin()

	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)

		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect(path, found)
		else:
			found.append(path.trim_prefix("res://"))

		entry = dir.get_next()

	dir.list_dir_end()
