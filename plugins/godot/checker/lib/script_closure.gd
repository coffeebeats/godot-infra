##
## plugins/godot/checker/lib/script_closure.gd
##
## ScriptClosure knows which files loading a file loads with it, and whether any of
## them carries a script. A script that preloads such a file makes its own compile wait
## on the resource loader.
##
## A scene or resource loads each `[ext_resource]` target, and a script loads what it
## preloads apart from other scripts, which come from the script cache rather than the
## loader. A target resolves by its uid first and its path second, as the engine does,
## and one that resolves to no file is left out.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEPENDENCIES -------------------------------------------------------------------- #

const GDScriptText := preload("gdscript_text.gd")
const ResourceText := preload("resource_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## BINARY_EXTENSIONS are the binary scene and resource formats, which cannot be proven
## free of a built-in script without loading them.
const BINARY_EXTENSIONS: Array[String] = ["res", "scn"]

## BUILT_IN_SCRIPT opens the block of a script saved inside a scene or resource.
const BUILT_IN_SCRIPT := '[sub_resource type="GDScript"'

## IMPORTED_SCENE marks an import file whose importer builds a scene, which can carry a
## script through its root script, a script class as its root type, or a node's script.
const IMPORTED_SCENE := 'importer="scene"'

## SCRIPT_EXTENSIONS are the GDScript formats.
const SCRIPT_EXTENSIONS: Array[String] = ["gd", "gdc"]

## TEXT_EXTENSIONS are the text scene and resource formats.
const TEXT_EXTENSIONS: Array[String] = ["tres", "tscn"]

# -- INITIALIZATION ------------------------------------------------------------------ #

## _bearing maps each file settled so far to whether it is script-bearing.
static var _bearing: Dictionary = {}

## _closures maps each file whose closure was walked to that closure.
static var _closures: Dictionary = {}

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## closure returns, as the keys of a dictionary, every file that loading `path` loads,
## to any depth. `path` is among them only when a cycle leads back to it.
static func closure(path: String) -> Dictionary:
	if path in _closures:
		return _closures[path]

	var reached := {}
	var pending: Array[String] = [path]

	while not pending.is_empty():
		for dependency in dependencies(pending.pop_back()):
			if dependency not in reached:
				reached[dependency] = true
				pending.append(dependency)

	_closures[path] = reached

	return reached


## dependencies returns each file that loading `path` loads directly.
static func dependencies(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var extension := path.get_extension()

	if extension in SCRIPT_EXTENSIONS:
		var text := FileAccess.get_file_as_string(path)

		for preloaded in GDScriptText.calls(text, ["preload"]):
			var target := resolve(path, GDScriptText.literal(preloaded.argument))
			if target != "" and not is_script(target):
				found.append(target)

	elif extension in TEXT_EXTENSIONS:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.begins_with(ResourceText.EXT_RESOURCE_PREFIX):
				continue

			var target := ResourceText.dependency(line)
			if target != "" and FileAccess.file_exists(target):
				found.append(target)

	return found


## is_script reports whether `path` names a GDScript.
static func is_script(path: String) -> bool:
	return path.get_extension() in SCRIPT_EXTENSIONS


## is_script_bearing reports whether loading `path` loads a script: it is one, or it or
## any file it loads is a scene or resource holding a built-in script, a binary scene or
## resource, or an imported scene.
static func is_script_bearing(path: String) -> bool:
	if path in _bearing:
		return _bearing[path]

	var bearing := _carries_script(path)

	if not bearing:
		for dependency: String in closure(path):
			if _carries_script(dependency):
				bearing = true
				break

	_bearing[path] = bearing

	return bearing


## resolve returns the file a `preload` or `load` in the script at `script_path` names
## with `target`, a `res://` or `uid://` path or one relative to the script, or an empty
## string when it names no file.
static func resolve(script_path: String, target: String) -> String:
	if target.is_empty():
		return ""

	var resolved := target

	if target.begins_with("uid://"):
		resolved = ResourceText.uid_path(target)
	elif not target.contains("://"):
		resolved = script_path.get_base_dir().path_join(target).simplify_path()

	if resolved.is_empty() or not FileAccess.file_exists(resolved):
		return ""

	return resolved


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _carries_script reports whether `path` itself is or holds a script, ignoring what it
## loads.
static func _carries_script(path: String) -> bool:
	var extension := path.get_extension()

	if extension in SCRIPT_EXTENSIONS or extension in BINARY_EXTENSIONS:
		return true

	if extension in TEXT_EXTENSIONS:
		return FileAccess.get_file_as_string(path).contains(BUILT_IN_SCRIPT)

	if FileAccess.file_exists(path + ".import"):
		return FileAccess.get_file_as_string(path + ".import").contains(IMPORTED_SCENE)

	return false


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	assert(
		not OS.is_debug_build(),
		"Invalid config; this 'Object' should not be instantiated!"
	)
