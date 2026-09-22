##
## plugins/godot/checker/rules/script_order.gd
##
## `script-order` reports script-declared properties assigned ahead of `script =` in the
## same block, which Godot silently drops. Base-type properties are exempt, since they
## apply regardless of the script.
##
## NOTE: `[resource]` and `[sub_resource]` blocks are covered as well as `[node]`, since
## a hand-written `.tres` can carry a script and its exports too.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const ResourceText := preload("../lib/resource_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## PROPERTY_PATTERN matches a top-level property assignment, skipping continuation lines
## of a multi-line value.
const PROPERTY_PATTERN := "^([A-Za-z_][A-Za-z0-9_/]*) = "

## SCRIPT_VALUE_PATTERN captures the ext_resource id a `script =` line references.
const SCRIPT_VALUE_PATTERN := '^script = ExtResource\\("([^"]+)"\\)'

## SCRIPT_RESOURCE_PATTERN captures the id of a declared script resource.
const SCRIPT_RESOURCE_PATTERN := 'type="Script".*id="([^"]+)"'

# -- INITIALIZATION ------------------------------------------------------------------ #

var _property := RegEx.create_from_string(PROPERTY_PATTERN)
var _script_resource := RegEx.create_from_string(SCRIPT_RESOURCE_PATTERN)
var _script_value := RegEx.create_from_string(SCRIPT_VALUE_PATTERN)

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []
	var scripts := _script_resources(file)

	var in_block := false
	var preceding := PackedStringArray()
	var lines := file.lines()

	for i in lines.size():
		var line := lines[i]

		if line.begins_with("["):
			in_block = (
				line.begins_with("[node ")
				or line.begins_with("[resource")
				or line.begins_with("[sub_resource ")
			)
			preceding.clear()
			continue

		if not in_block:
			continue

		var found := _property.search(line)
		if found == null:
			continue

		var property := found.get_string(1)
		if property != "script":
			preceding.append(property)
			continue

		in_block = false

		if preceding.is_empty():
			continue

		var id := _script_value.search(line)
		if id == null:
			continue

		var exports := _script_exports(scripts.get(id.get_string(1), ""))
		var dropped := PackedStringArray()

		for candidate in preceding:
			if candidate in exports:
				dropped.append(candidate)

		if dropped.is_empty():
			continue

		var message := (
			"%s assigned before `script =`; silently dropped" % ", ".join(dropped)
		)
		problems.append(Problem.new(file.path, i + 1, name, message))

	return problems


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"script-order"
	extensions = ["tscn", "tres"]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _script_resources maps ext_resource ids to the scripts they load in the given file.
func _script_resources(file: SourceFile) -> Dictionary:
	var scripts := {}

	for line in file.lines():
		if not line.begins_with(ResourceText.EXT_RESOURCE_PREFIX):
			continue

		var found := _script_resource.search(line)
		if found != null:
			scripts[found.get_string(1)] = ResourceText.dependency(line)

	return scripts


## _script_exports returns the names of the properties a script itself declares.
func _script_exports(script_path: String) -> PackedStringArray:
	var names := PackedStringArray()
	if script_path == "":
		return names

	var script: Script = ResourceLoader.load(script_path, "Script")
	if script == null:
		return names

	for property in script.get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property.name)

	return names
