##
## plugins/godot/checker/rules/preload.gd
##
## `preload` reports a script whose compile can wait on the resource loader. A compile
## holds the script cache's lock throughout, and Godot 4.6 to 4.8 deadlocks when the
## load it waits for runs on another thread and needs that lock. A `preload` of a scene
## or resource carrying a script is the usual way in. It reports:
##
## - a `preload` of anything but one string literal, which cannot be followed;
## - a `preload` of a file whose closure carries a script, a script itself excepted,
##   since a script comes from the script cache rather than the loader;
## - a load of any kind in a `static var` initializer or in `_static_init`, which run
##   before the lock is released;
## - a scene or resource holding a built-in script, which compiles on whichever thread
##   loads it and cannot be checked here.
##
## NOTE: A script compiled only at boot, such as an autoload, is reported too, though no
## load can be in flight then. An export set in the scene is the fix either way.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const GDScriptText := preload("../lib/gdscript_text.gd")
const ScriptClosure := preload("../lib/script_closure.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## MESSAGE_BUILT_IN reports a built-in script.
const MESSAGE_BUILT_IN := "holds a built-in script; save it as a .gd file"

## MESSAGE_NON_LITERAL reports a `preload` of anything but one string literal.
const MESSAGE_NON_LITERAL := "preload of a non-literal; preload one string literal"

## MESSAGE_SCRIPT_BEARING reports a `preload` of a file carrying a script, named by the
## placeholder.
const MESSAGE_SCRIPT_BEARING := (
	"preloads %s, which carries a script, so compiling this script can wait on"
	+ " another thread's load; export it and set it in the scene"
)

## MESSAGE_STATIC_LOAD reports a load in a static initializer, named by the placeholder.
const MESSAGE_STATIC_LOAD := (
	"`%s()` in a static initializer, which runs while the script cache is locked;"
	+ " preload a script-free file or load it later"
)

## STATIC_LOADS are the calls that load a resource, reported in a static initializer
## whatever they load. `.load_now` is the method of that name on any receiver.
const STATIC_LOADS: PackedStringArray = [
	"load",
	"ResourceLoader.load",
	"ResourceLoader.load_threaded_get",
	"ResourceLoader.load_threaded_get_status",
	"ResourceLoader.load_threaded_request",
	"load_now",
	".load_now",
]

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	if file.path.get_extension() != "gd":
		return _check_resource(file)

	var problems: Array[Problem] = []
	var text := file.text()

	for preloaded in GDScriptText.calls(text, ["preload"]):
		var target := GDScriptText.literal(preloaded.argument)

		if target.is_empty():
			problems.append(
				Problem.new(file.path, preloaded.line, name, MESSAGE_NON_LITERAL)
			)
			continue

		var resolved := ScriptClosure.resolve(file.path, target, true)
		if resolved.is_empty() or ScriptClosure.is_script(resolved):
			continue

		if ScriptClosure.is_script_bearing(resolved):
			var message := MESSAGE_SCRIPT_BEARING % resolved
			problems.append(Problem.new(file.path, preloaded.line, name, message))

	var spans := GDScriptText.static_spans(text)

	for loaded in GDScriptText.calls(text, STATIC_LOADS):
		if _within(loaded.start, spans):
			var message := MESSAGE_STATIC_LOAD % String(loaded.name).trim_prefix(".")
			problems.append(Problem.new(file.path, loaded.line, name, message))

	return problems


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _check_resource reports each built-in script a scene or resource holds.
func _check_resource(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []
	var lines := file.lines()

	for i in lines.size():
		if lines[i].begins_with(ScriptClosure.BUILT_IN_SCRIPT):
			problems.append(Problem.new(file.path, i + 1, name, MESSAGE_BUILT_IN))

	return problems


## _within reports whether `offset` falls inside one of `spans`.
func _within(offset: int, spans: Array[Vector2i]) -> bool:
	for span in spans:
		if offset >= span.x and offset < span.y:
			return true

	return false


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"preload"
	extensions = ["gd", "tscn", "tres"]
