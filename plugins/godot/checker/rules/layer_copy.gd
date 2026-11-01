##
## plugins/godot/checker/rules/layer_copy.gd
##
## `layer-copy` reports an action set layer whose actions differ from those of another
## layer of the same name. A project shares a layer across action sets by copying its
## file and changing only `parent`, and the copies keep one name so they share a
## player's bindings. Nothing links a copy to its source, so an action the source gains
## later is missing from the copy with no error.
##
## NOTE: A layer is recognized by the properties it carries, so the checker names no
## addon's class.
##
## NOTE: Only a project's own layers are checked. One passes by matching any layer of
## its name under `addons/`; with none, it is compared with the project's other copies.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Discovery := preload("../core/discovery.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## ADDONS is the directory holding the layers a copy's source may be, which `Discovery`
## never walks into from the project's root.
const ADDONS := "res://addons"

## ACTION_PROPERTIES maps each property listing a layer's actions to the suffix marking
## an action of that kind, so an action moved to another kind reads as a difference.
const ACTION_PROPERTIES := {
	&"actions_digital": "",
	&"actions_analog_1d": " (analog 1D)",
	&"actions_analog_2d": " (analog 2D)",
}

## LAYER_MARKER is the text a file must hold to be read as a possible source, which
## spares loading every resource under `addons/` when one layer is checked. It covers
## every kind of action, since a file doesn't save an empty list.
const LAYER_MARKER := "actions_"

# -- INITIALIZATION ------------------------------------------------------------------ #

## _layers maps each layer name to its layers' actions, keyed by path; see `_index`.
var _layers: Dictionary = {}

## _indexed is whether `_layers` has been built.
var _indexed: bool = false

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []

	var resource := file.resource()
	if not _is_layer(resource):
		return problems

	var actions := _actions(resource)
	var layers: Dictionary = _index().get(resource.get(&"name"), {})
	var sources := _sources(layers)

	# NOTE: A copy has one source, so matching any addon's layer of its name passes it.
	for path in sources:
		if layers[path] == actions:
			return problems

	var compared := sources if not sources.is_empty() else _others(layers, file.path)

	for path in compared:
		if layers[path] == actions:
			continue

		var message := (
			"layer '%s' lists different actions from %s: %s"
			% [resource.get(&"name"), path, _difference(actions, layers[path])]
		)
		problems.append(Problem.new(file.path, 0, name, message))

	return problems


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"layer-copy"
	extensions = ["tres"]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _actions returns every action resource lists, sorted, each marked with its kind.
func _actions(resource: Resource) -> PackedStringArray:
	var actions := PackedStringArray()

	for property: StringName in ACTION_PROPERTIES:
		if property in resource:
			for action: StringName in resource.get(property):
				actions.append(String(action) + ACTION_PROPERTIES[property])

	actions.sort()

	return actions


## _difference describes what actions lacks and adds relative to expected.
func _difference(actions: PackedStringArray, expected: PackedStringArray) -> String:
	var parts := PackedStringArray()

	var missing := _subtract(expected, actions)
	if not missing.is_empty():
		parts.append("missing %s" % ", ".join(missing))

	var extra := _subtract(actions, expected)
	if not extra.is_empty():
		parts.append("extra %s" % ", ".join(extra))

	return "; ".join(parts)


## _index returns every layer in the project and its addons that `.gdcheckrc` leaves to
## this rule, built on first use.
func _index() -> Dictionary:
	if _indexed:
		return _layers

	_indexed = true

	var paths := {}
	Discovery.scan("res://", extensions, paths)
	Discovery.scan(ADDONS, extensions, paths)

	for path: String in paths:
		if config.excluded(Config.ALL, path) or config.excluded(name, path):
			continue

		var file := SourceFile.new(path)
		if not file.text().contains(LAYER_MARKER):
			continue

		var resource := file.resource()
		if not _is_layer(resource):
			continue

		var layer_name: StringName = resource.get(&"name")
		if not _layers.has(layer_name):
			_layers[layer_name] = {}

		_layers[layer_name][path] = _actions(resource)

	return _layers


## _is_layer returns whether resource is a named action set layer, which a set is not,
## since only a layer carries a `parent`.
func _is_layer(resource: Resource) -> bool:
	return (
		resource != null
		and &"parent" in resource
		and &"actions_digital" in resource
		and &"name" in resource
		and resource.get(&"name") != &""
	)


## _others returns every path in layers other than path, sorted.
func _others(layers: Dictionary, path: String) -> Array[String]:
	var found: Array[String] = []

	for other: String in layers:
		if other != path:
			found.append(other)

	found.sort()

	return found


## _sources returns the paths in layers under `addons/`, sorted.
func _sources(layers: Dictionary) -> Array[String]:
	var found: Array[String] = []

	for other: String in layers:
		if other.begins_with(ADDONS + "/"):
			found.append(other)

	found.sort()

	return found


## _subtract returns the entries of from that without does not hold.
func _subtract(
	from: PackedStringArray, without: PackedStringArray
) -> PackedStringArray:
	var found := PackedStringArray()

	for entry in from:
		if entry not in without:
			found.append(entry)

	return found
