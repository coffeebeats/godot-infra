##
## plugins/godot/checker/rules/load.gd
##
## `load` reports files that do not parse or instantiate, with the first error the
## engine raised, and scenes that instantiate unlike their declaration: a node missing,
## of another class than declared, or without its declared script.
##
## NOTE: A project boot is no substitute, since quitting mid-load prints parse errors
## for well-formed scenes; this rule loads synchronously.
##
## NOTE: Godot builds what it can of a scene and patches over the rest. A node of an
## unknown type becomes a placeholder, a script that does not compile or fit its node is
## left off, and a node whose parent is gone is dropped. The scene's `SceneState`
## decides whether a scene diverged, and the engine's errors only explain it, since
## GUT's own scene logs an error on every load and works.
##

extends "../core/rule.gd"

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	if file.resource() == null:
		return [Problem.new(file.path, 0, name, file.explained("failed to load"))]

	if file.path.get_extension() == "tres":
		return []

	var root := file.instance()
	if root == null:
		var reason := file.explained("failed to instantiate")
		return [Problem.new(file.path, 0, name, reason)]

	var divergences := _divergences((file.resource() as PackedScene).get_state(), root)

	# NOTE: The engine's errors do not say which node raised them, so only a scene that
	# diverges at a single node is explained.
	if divergences.size() == 1:
		return [Problem.new(file.path, 0, name, file.explained(divergences[0]))]

	var problems: Array[Problem] = []

	for divergence in divergences:
		problems.append(Problem.new(file.path, 0, name, divergence))

	return problems


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"load"
	extensions = ["tscn", "tres"]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _divergences describes each node the scene declares that root lacks, holds as another
## class than declared, or holds without its declared script, once per node and once
## per missing subtree.
func _divergences(state: SceneState, root: Node) -> PackedStringArray:
	var found := PackedStringArray()
	var missing := {}

	for i in state.get_node_count():
		var node_path := state.get_node_path(i)
		var node := root.get_node_or_null(node_path)

		if node == null:
			missing[node_path] = true

			# NOTE: A node is declared after its parent, so the descendants of a missing
			# node are passed over.
			if not missing.has(state.get_node_path(i, true)):
				found.append("node '%s' was not instantiated" % node_path)

			continue

		# NOTE: An instanced node, or one overriding an instance's, declares no type.
		var type := state.get_node_type(i)

		if type != &"" and not node.is_class(type):
			found.append(
				(
					"node '%s' is declared as %s but instantiated as %s"
					% [node_path, type, node.get_class()]
				)
			)
			continue

		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) != &"script":
				continue

			# NOTE: A value that is no script, such as the stub the editor saves for a
			# missing one, never attaches, and the node is left alone.
			var value: Variant = state.get_node_property_value(i, j)

			if value is Script and node.get_script() != value:
				found.append(
					(
						"node '%s' was instantiated without its script %s"
						% [node_path, (value as Script).resource_path]
					)
				)

	return found
