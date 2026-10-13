##
## plugins/godot/checker/rules/compile.gd
##
## `compile` reports each error the engine raised at a line of a script that does not
## compile, or the first error it raised when none names a line of the script.
##
## NOTE: A script that fails to parse still loads as non-null, so compilation is judged
## by its native base type; `--check-only` and `reload()` both misreport it.
##

extends "../core/rule.gd"

# -- INITIALIZATION ------------------------------------------------------------------ #

## _checker_dir is the directory holding this checker, whose files `check` skips because
## re-loading the running script hangs the engine.
var _checker_dir: String = ""

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	if file.path.begins_with(_checker_dir + "/"):
		return []

	var script := file.resource() as Script
	if script != null and script.get_instance_base_type() != &"":
		return []

	var problems: Array[Problem] = []
	var seen := {}

	for error in file.errors():
		var key := "%d %s" % [error.line, error.message]
		if error.path == file.path and not seen.has(key):
			seen[key] = true
			problems.append(Problem.new(file.path, error.line, name, error.message))

	if problems.is_empty():
		problems.append(
			Problem.new(file.path, 0, name, file.explained("does not compile"))
		)

	return problems


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"compile"
	extensions = ["gd"]
	_checker_dir = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
