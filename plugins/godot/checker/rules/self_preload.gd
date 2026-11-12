##
## plugins/godot/checker/rules/self_preload.gd
##
## `self-preload` reports a script that preloads, or loads in a static initializer, a
## scene or resource that loads the script back, such as a scene whose root carries it.
## The scene's load reaches the script while it is still compiling. Whichever starts
## first, the scene is cached without its script or the script is left invalid, with
## no second thread involved.
##
## NOTE: `preload` reports these too. This is a rule of its own so that excluding a file
## from `preload` cannot turn it off.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const GDScriptText := preload("../lib/gdscript_text.gd")
const ScriptClosure := preload("../lib/script_closure.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## MESSAGE reports a target that loads the script back, named by the placeholder.
const MESSAGE := (
	"loads %s, which loads this script back while it compiles; export it and set it"
	+ " in the scene"
)

## STATIC_LOADS are the calls that load a resource, followed in a static initializer.
## `.load_now` is the method of that name on any receiver.
const STATIC_LOADS: PackedStringArray = [
	"load",
	"ResourceLoader.load",
	"ResourceLoader.load_threaded_request",
	"load_now",
	".load_now",
]

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []
	var text := file.text()
	var spans := GDScriptText.static_spans(text)

	var loads := GDScriptText.calls(text, ["preload"])

	for loaded in GDScriptText.calls(text, STATIC_LOADS):
		if _within(loaded.start, spans):
			loads.append(loaded)

	for loaded in loads:
		var parameters := GDScriptText.parameters(loaded.argument)
		if parameters.is_empty():
			continue

		var target := GDScriptText.literal(parameters[0])
		var resolved := ScriptClosure.resolve(file.path, target)

		if resolved.is_empty() or ScriptClosure.is_script(resolved):
			continue

		if file.path in ScriptClosure.closure(resolved):
			problems.append(
				Problem.new(file.path, loaded.line, name, MESSAGE % resolved)
			)

	return problems


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _within reports whether `offset` falls inside one of `spans`.
func _within(offset: int, spans: Array[Vector2i]) -> bool:
	for span in spans:
		if offset >= span.x and offset < span.y:
			return true

	return false


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"self-preload"
	extensions = ["gd"]
