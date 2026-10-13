##
## plugins/godot/checker/rules/load.gd
##
## `load` reports files that do not parse or instantiate, with the first error the
## engine raised.
##
## NOTE: A project boot is no substitute, since quitting mid-load prints parse errors
## for well-formed scenes; this rule loads synchronously.
##

extends "../core/rule.gd"

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	if file.resource() == null:
		return [Problem.new(file.path, 0, name, file.explained("failed to load"))]

	if file.path.get_extension() == "tres":
		return []

	if file.instance() == null:
		var reason := file.explained("failed to instantiate")
		return [Problem.new(file.path, 0, name, reason)]

	return []


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"load"
	extensions = ["tscn", "tres"]
