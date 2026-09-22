##
## plugins/godot/checker/rules/compile.gd
##
## `compile` reports scripts that do not compile.
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

	var script: Script = ResourceLoader.load(
		file.path, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP
	)

	if script != null and script.get_instance_base_type() != &"":
		return []

	return [Problem.new(file.path, 0, name, "does not compile")]


func loads_file() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"compile"
	extensions = ["gd"]
	_checker_dir = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
