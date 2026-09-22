##
## plugins/godot/checker/core/config.gd
##
## Config is the project's `.gdcheckrc`, in `ConfigFile` syntax. Section `all` applies
## to every rule and any other section to the rule it names. `excludes` lists `res://`
## globs of files to skip; `extensions`, only under `all`, maps each GDExtension the
## project uses to the global names it defines; `disallow_engine_output`, only under
## `logging`, turns that rule on. A project without the file has an empty config.
##

extends RefCounted

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Config := preload("config.gd")
const Problem := preload("problem.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## ALL names the config section that applies to every rule.
const ALL := "all"

## EXTENSIONS_SHAPE describes the value `extensions` must hold.
const EXTENSIONS_SHAPE := "a dictionary of .gdextension paths to arrays of names"

## LOGGING names the config section of the `logging` rule, the one rule a project
## turns on rather than inherits; see `rules/logging.gd`.
const LOGGING := "logging"

## PATH is the project's checker config.
const PATH := "res://.gdcheckrc"

# -- CONFIGURATION ------------------------------------------------------------------- #

## disallow_engine_output reports whether the project logs through something other
## than the engine's own output functions.
var disallow_engine_output: bool = false

## excludes maps a section to the globs of the files it skips.
var excludes: Dictionary = {}

## extensions maps a `.gdextension` path to the global names it defines.
var extensions: Dictionary = {}

## problems holds every error found in the file.
var problems: Array[Problem] = []

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## parse reads `PATH`, accepting `all` and each of `rule_names` as a section.
static func parse(rule_names: PackedStringArray) -> Config:
	var config := Config.new()
	if not FileAccess.file_exists(PATH):
		return config

	var file := ConfigFile.new()
	var err := file.load(PATH)
	if err != OK:
		config._error("does not parse: %s" % error_string(err))
		return config

	for section in file.get_sections():
		if section != ALL and section not in rule_names:
			config._error("unknown section [%s]" % section)
			continue

		for key in file.get_section_keys(section):
			var value: Variant = file.get_value(section, key)

			if key == "excludes":
				config._parse_excludes(section, value)
			elif key == "extensions" and section == ALL:
				config._parse_extensions(value)
			elif key == "extensions":
				config._error("[%s] extensions belongs under [all]" % section)
			elif key == "disallow_engine_output" and section == LOGGING:
				config._parse_disallow_engine_output(value)
			elif key == "disallow_engine_output":
				config._error(
					"[%s] disallow_engine_output belongs under [logging]" % section
				)
			else:
				config._error("unknown key `%s` in [%s]" % [key, section])

	return config


## excluded reports whether the given section skips the file.
func excluded(section: String, file_path: String) -> bool:
	var patterns: PackedStringArray = excludes.get(section, PackedStringArray())

	for pattern in patterns:
		if file_path.match(pattern):
			return true

	return false


## is_strings reports whether a value is an array holding only strings.
static func is_strings(value: Variant) -> bool:
	if not (value is Array or value is PackedStringArray):
		return false

	for element: Variant in value:
		if not (element is String):
			return false

	return true


# -- PRIVATE METHODS ----------------------------------------------------------------- #


func _error(message: String) -> void:
	problems.append(Problem.new(PATH, 0, &"config", message))


func _parse_disallow_engine_output(value: Variant) -> void:
	if not (value is bool):
		_error("[logging] disallow_engine_output must be a boolean")
		return

	disallow_engine_output = value


func _parse_excludes(section: String, value: Variant) -> void:
	if not is_strings(value):
		_error("[%s] excludes must be an array of strings" % section)
		return

	var patterns := PackedStringArray()

	for pattern: String in value:
		if not pattern.begins_with("res://"):
			_error("[%s] exclude must start with res://: %s" % [section, pattern])
			continue

		patterns.append(pattern)

	excludes[section] = patterns


func _parse_extensions(value: Variant) -> void:
	if not (value is Dictionary):
		_error("[all] extensions must be %s" % EXTENSIONS_SHAPE)
		return

	var entries: Dictionary = value

	for extension: Variant in entries:
		var names: Variant = entries[extension]

		if not (extension is String) or not is_strings(names):
			_error("[all] extensions must be %s" % EXTENSIONS_SHAPE)
			continue

		# NOTE: An empty list would compile to a pattern matching every script.
		if names.is_empty():
			_error("[all] extension defines no names: %s" % extension)
			continue

		for identifier: String in names:
			if not identifier.is_valid_ascii_identifier():
				_error("[all] not an identifier: %s" % identifier)

		extensions[extension] = PackedStringArray(names)
