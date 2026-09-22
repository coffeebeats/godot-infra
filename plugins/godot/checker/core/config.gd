##
## plugins/godot/checker/core/config.gd
##
## Config is the project's `.gdcheckrc`, in `ConfigFile` syntax. Section `all` applies
## to every rule, and any other section to the rule it names, which declares the keys it
## reads with `Rule.options`. A project without the file has an empty config.
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

## PATH is the project's checker config.
const PATH := "res://.gdcheckrc"

# -- CONFIGURATION ------------------------------------------------------------------- #

## excludes maps a section to the globs of the files it skips.
var excludes: Dictionary = {}

## extensions maps a `.gdextension` path to the global names it defines.
var extensions: Dictionary = {}

## problems holds every error found in the file.
var problems: Array[Problem] = []

# -- INITIALIZATION ------------------------------------------------------------------ #

## _options maps a rule's section to its options, each a key mapped to its value.
var _options: Dictionary = {}

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## parse reads `PATH`. `sections` maps each rule's section to the options it declares,
## each a key mapped to its default; `all` is always accepted.
static func parse(sections: Dictionary) -> Config:
	var config := Config.new()

	for section: String in sections:
		config._options[section] = sections[section].duplicate()

	if not FileAccess.file_exists(PATH):
		return config

	var file := ConfigFile.new()
	var err := file.load(PATH)
	if err != OK:
		config._error("does not parse: %s" % error_string(err))
		return config

	for section in file.get_sections():
		if section != ALL and section not in sections:
			config._error("unknown section [%s]" % section)
			continue

		for key in file.get_section_keys(section):
			var value: Variant = file.get_value(section, key)

			if key == "excludes":
				config._parse_excludes(section, value)
			elif key == "extensions" and section == ALL:
				config._parse_extensions(value)
			elif section != ALL and key in sections[section]:
				config._parse_option(section, key, value)
			else:
				config._misplaced(section, key, sections)

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


## options returns a rule's options, each default replaced by the project's value.
func options(section: String) -> Dictionary:
	return _options.get(section, {})


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _error records a problem with the config file itself.
func _error(message: String) -> void:
	problems.append(Problem.new(PATH, 0, &"config", message))


## _misplaced reports a key its section does not take, naming the section that does.
func _misplaced(section: String, key: String, sections: Dictionary) -> void:
	var home := ALL if key == "extensions" else ""

	for other: String in sections:
		if key in sections[other]:
			home = other
			break

	if home == "":
		_error("unknown key `%s` in [%s]" % [key, section])
		return

	_error("[%s] %s belongs under [%s]" % [section, key, home])


## _parse_excludes records a section's `excludes`, reporting a glob outside `res://`.
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


## _parse_extensions records `[all] extensions`, reporting an entry of the wrong shape.
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


## _parse_option records a rule's option, which must hold the type of its default.
func _parse_option(section: String, key: String, value: Variant) -> void:
	var default: Variant = _options[section][key]

	if typeof(value) != typeof(default):
		var type := type_string(typeof(default))
		_error("[%s] %s must be of type %s" % [section, key, type])
		return

	_options[section][key] = value
