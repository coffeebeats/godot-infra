##
## plugins/godot/checker/core/extension_gate.gd
##
## ExtensionGate decides which files the rules that load a file skip, because a
## GDExtension they depend on did not load. A script naming the API of a missing
## extension fails to parse, which reports the machine rather than the script.
##

extends RefCounted

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Config := preload("config.gd")
const GDScriptText := preload("../lib/gdscript_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## DEPENDENCY_PATTERN captures the path an `[ext_resource]` header points at.
const DEPENDENCY_PATTERN := 'path="([^"]+)"'

## SCRIPT_DEPENDENCY_PATTERN captures the path a script `preload`s or `extends`.
const SCRIPT_DEPENDENCY_PATTERN := (
	"(?m)(?:\\bpreload\\s*\\(\\s*|^(?:class_name\\s+\\w+\\s+)?extends\\s+)"
	+ "[\\x22\\x27]([^\\x22\\x27]+)[\\x22\\x27]"
)

# -- CONFIGURATION ------------------------------------------------------------------- #

## missing maps each extension in the config that this process did not load to the
## names it defines; see `_missing_extensions`.
var missing: Dictionary = {}

# -- INITIALIZATION ------------------------------------------------------------------ #

## _blocked_cache maps each file a walk has settled to whether it reaches a script using
## a name from an extension that did not load; see `_blocked`.
var _blocked_cache: Dictionary = {}

var _dependency := RegEx.create_from_string(DEPENDENCY_PATTERN)
var _names: RegEx = null
var _non_code := RegEx.create_from_string(GDScriptText.NON_CODE_PATTERN)
var _script_dependency := RegEx.create_from_string(SCRIPT_DEPENDENCY_PATTERN)

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## blocks reports whether the rules that load a file must skip it; see `_blocked`.
func blocks(path: String) -> bool:
	return _names != null and _blocked(path, _names)


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init(config: Config) -> void:
	missing = _missing_extensions(config)
	_names = _blocking_pattern(missing)


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _blocked reports whether a file is a script using a name `names` matches, or depends
## on one to any depth; see `_dependencies`.
##
## NOTE: A scene naming a blocked script in a header still loads and instantiates, so
## without the walk every rule would pass it unchecked.
func _blocked(path: String, names: RegEx) -> bool:
	var visited := {}

	if _reaches_blocked(path, names, visited):
		return true

	# NOTE: A walk that finds nothing proves every file it visited clean. One that finds a
	# blocked script stops early, so only the files on the way to it are settled.
	for visited_path: String in visited:
		_blocked_cache[visited_path] = false

	return false


## _blocking_pattern returns a pattern matching a use of any name a missing extension
## defines, or null when no extension is missing.
func _blocking_pattern(missing: Dictionary) -> RegEx:
	if missing.is_empty():
		return null

	var names := PackedStringArray()

	for extension: String in missing:
		names.append_array(missing[extension])

	return RegEx.create_from_string(GDScriptText.NAME_BOUNDARY + ("(?:%s)\\b" % "|".join(names)))


## _dependencies returns the files a file needs in order to load: the `[ext_resource]`
## headers of a scene or resource, and the paths a script `preload`s or `extends`.
##
## NOTE: A script referring to another only by its `class_name` is not followed.
func _dependencies(path: String, text: String) -> PackedStringArray:
	var found := PackedStringArray()

	if path.get_extension() == "gd":
		for result: RegExMatch in _script_dependency.search_all(text):
			var target := result.get_string(1)

			if not target.contains("://"):
				target = path.get_base_dir().path_join(target).simplify_path()

			found.append(target)

		return found

	for line in text.split("\n"):
		if not line.begins_with("[ext_resource "):
			continue

		var result := _dependency.search(line)
		if result != null:
			found.append(result.get_string(1))

	return found


## _missing_extensions returns each extension in the config that this process did not
## load, mapped to the names it defines. An extension absent from the checkout, such as
## an uninitialized submodule, counts as not loaded.
##
## NOTE: A GDExtension with no binary for the platform does not load, so scripts naming
## its API fail to parse. GodotSteam ships no Linux binary.
func _missing_extensions(config: Config) -> Dictionary:
	var missing := {}

	for extension: String in config.extensions:
		if not GDExtensionManager.is_extension_loaded(extension):
			missing[extension] = config.extensions[extension]

	return missing


## _reaches_blocked walks a file's dependencies depth-first, settling each file it finds
## to reach a blocked script.
func _reaches_blocked(path: String, names: RegEx, visited: Dictionary) -> bool:
	if path in _blocked_cache:
		return _blocked_cache[path]

	if path in visited:
		return false

	visited[path] = true

	var extension := path.get_extension()
	if extension not in ["gd", "tscn", "tres"]:
		return false

	var text := FileAccess.get_file_as_string(path)

	if extension == "gd" and names.search(_non_code.sub(text, " ", true)) != null:
		_blocked_cache[path] = true
		return true

	for dependency in _dependencies(path, text):
		if _reaches_blocked(dependency, names, visited):
			_blocked_cache[path] = true
			return true

	return false
