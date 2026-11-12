##
## plugins/godot/checker/rules/self_preload.gd
##
## `self-preload` reports a script that preloads, or loads in a static initializer, a
## file leading to a scene or resource that loads the script back, such as a scene whose
## root carries it or a script preloading that scene. The scene's load reaches the
## script while it is still compiling. Whichever starts first, the scene is cached
## without its script or the script is left invalid, with no second thread involved.
## Scripts that only preload one another are fine, since the script cache allows that.
##
## NOTE: `preload` reports the same line too, unless the loop starts at a preloaded
## script, which `preload` skips.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const ScriptClosure := preload("../lib/script_closure.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## MESSAGE reports a target that loads the script back, named by the placeholder.
const MESSAGE := (
	"loads %s, which loads this script back while it compiles; export it and set it"
	+ " in the scene"
)

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []

	for loaded in ScriptClosure.loads(file.text()):
		var resolved := ScriptClosure.target_of(file.path, loaded)

		if resolved.is_empty():
			continue

		if ScriptClosure.closure(resolved).get(file.path, false):
			problems.append(
				Problem.new(file.path, loaded.line, name, MESSAGE % resolved)
			)

	return problems


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"self-preload"
	extensions = ["gd"]
