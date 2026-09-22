##
## plugins/godot/checker/rules/nodepath.gd
##
## `nodepath` reports NodePath exports that resolve to null on the instantiated scene.
## The usual cause is a path pointing at a node whose type does not match the export's
## declared type, which Godot resolves to null without complaint.
##

extends "../core/rule.gd"

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []

	var scene := file.resource() as PackedScene
	var root := file.instance()
	if scene == null or root == null:
		return problems

	var state := scene.get_state()

	for i in state.get_node_count():
		var node_path := state.get_node_path(i)
		var node := root.get_node_or_null(node_path)
		if node == null:
			continue

		for j in state.get_node_property_count(i):
			var value: Variant = state.get_node_property_value(i, j)
			if not (value is NodePath) or String(value) == "":
				continue

			var property := state.get_node_property_name(i, j)
			if node.get(property) != null:
				continue

			var message := (
				"node '%s' export `%s` points at '%s' but resolves to null"
				% [node_path, property, value]
			)
			problems.append(Problem.new(file.path, 0, name, message))

	return problems


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"nodepath"
	extensions = ["tscn"]
