##
## plugins/godot/checker/lib/resource_text.gd
##
## ResourceText holds what the checker knows about the text of a scene or resource.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEFINITIONS --------------------------------------------------------------------- #

## EXT_RESOURCE_PREFIX opens a dependency header, an `[ext_resource]` line.
const EXT_RESOURCE_PREFIX := "[ext_resource "

## REFERENCE_PATTERN matches one quoted `res://` or `uid://` string literal.
const REFERENCE_PATTERN := '"((?:res|uid)://[^"]*)"'

# -- INITIALIZATION ------------------------------------------------------------------ #

## _reference is `REFERENCE_PATTERN`, compiled once for every caller.
static var _reference := RegEx.create_from_string(REFERENCE_PATTERN)

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## dependency returns the file a dependency header loads, which is the one its uid
## resolves to, or the `path` it carries when the uid resolves to nothing, as the engine
## falls back. It returns an empty string when neither names a file.
static func dependency(line: String) -> String:
	var carried := ""

	for found in _reference.search_all(line):
		var ref := found.get_string(1)

		if ref.begins_with("uid://"):
			var resolved := uid_path(ref)
			if resolved != "":
				return resolved
		elif ref.begins_with("res://"):
			carried = ref

	return carried


## uid_path returns the file a `uid://` reference resolves to, or an empty string when
## it resolves to nothing or to a file that is not there.
static func uid_path(ref: String) -> String:
	var id := ResourceUID.text_to_id(ref)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return ""

	var target := ResourceUID.get_id_path(id)

	return target if FileAccess.file_exists(target) else ""


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	assert(
		not OS.is_debug_build(),
		"Invalid config; this 'Object' should not be instantiated!"
	)
