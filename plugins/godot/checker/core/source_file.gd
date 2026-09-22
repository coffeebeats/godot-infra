##
## plugins/godot/checker/core/source_file.gd
##
## SourceFile is the per-file context every rule shares. The text is read once and the
## resource loaded and instantiated at most once, so N rules cost one read and one load.
##

extends RefCounted

# -- CONFIGURATION ------------------------------------------------------------------- #

var path: String

# -- INITIALIZATION ------------------------------------------------------------------ #

var _instance: Node = null
var _instantiated: bool = false
var _lines := PackedStringArray()
var _loaded: bool = false
var _read: bool = false
var _resource: Resource = null
var _text: String = ""

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## text returns the file's contents verbatim, line endings included.
func text() -> String:
	if not _read:
		_read = true

		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			_text = file.get_as_text()
			_lines = _text.replace("\r\n", "\n").split("\n")

	return _text


## lines returns the contents split on newlines, with carriage returns normalized out.
func lines() -> PackedStringArray:
	text()
	return _lines


## resource returns the loaded resource, or null if it does not load.
func resource() -> Resource:
	if not _loaded:
		_loaded = true
		_resource = ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)

	return _resource


## instance returns the instantiated scene root, or null if this is not a scene or it
## does not load.
func instance() -> Node:
	if not _instantiated:
		_instantiated = true

		var scene := resource() as PackedScene
		if scene != null:
			_instance = scene.instantiate()

	return _instance


## release frees the instantiated scene, if one was created.
func release() -> void:
	if _instance != null:
		_instance.free()
		_instance = null


## reset drops everything cached, so rules running after a fix see the new contents.
func reset() -> void:
	release()

	_instantiated = false
	_lines = PackedStringArray()
	_loaded = false
	_read = false
	_resource = null
	_text = ""


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init(file_path: String) -> void:
	path = file_path
