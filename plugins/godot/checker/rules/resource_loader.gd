##
## plugins/godot/checker/rules/resource_loader.gd
##
## `resource-loader` reports a load that bypasses the project's own loader. It reports:
##
## - a threaded load (`load_threaded_request`, `load_threaded_get` or
##   `load_threaded_get_status`) named in code or in a string, which also catches a
##   `Callable` or `call` naming it;
## - a bare `load()` or `ResourceLoader.load()`, which blocks the main thread beside
##   whatever the loader has in flight, where `StdLoader.load_now` reports a slow load
##   and never waits on an unrelated one.
##
## A file declaring its own `func load(` is spared only a bare `load()`, since a bare
## call there is its own method; its `ResourceLoader.load()` is still reported.
##
## NOTE: The rule covers no file until `.gdcheckrc` lists under `allow` the files that
## implement the loader, since a project with no loader has nothing to call instead.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const GDScriptText := preload("../lib/gdscript_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## DECLARES_LOAD_PATTERN matches a declaration of a method named `load`.
const DECLARES_LOAD_PATTERN := (
	"(?m)^\\s*"
	+ GDScriptText.LEADING_ANNOTATIONS
	+ "(?:static\\s+)?func\\s+load\\s*\\("
)

## MESSAGE_BLOCKING reports a blocking load, named by the placeholder.
const MESSAGE_BLOCKING := (
	"blocking `%s()`; call `StdLoader.load_now`, which never waits on an"
	+ " unrelated load"
)

## MESSAGE_THREADED reports a threaded load, named by the placeholder.
const MESSAGE_THREADED := "`%s` outside the loader; request it through `StdLoader`"

## THREADED_PATTERN matches the name of one of `ResourceLoader`'s threaded loads.
const THREADED_PATTERN := "\\bload_threaded_(?:request|get_status|get)\\b"

# -- INITIALIZATION ------------------------------------------------------------------ #

## _allow holds the globs of the files the loader is implemented in.
var _allow := PackedStringArray()

var _declares_load := RegEx.create_from_string(DECLARES_LOAD_PATTERN)
var _threaded := RegEx.create_from_string(THREADED_PATTERN)

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	for pattern in _allow:
		if file.path.match(pattern):
			return []

	var problems: Array[Problem] = []
	var text := file.text()
	var code := GDScriptText.blank(text, true)

	for found: RegExMatch in _threaded.search_all(code):
		var line := code.substr(0, found.get_start()).count("\n") + 1
		var message := MESSAGE_THREADED % found.get_string()
		problems.append(Problem.new(file.path, line, name, message))

	var blocking := PackedStringArray(["load", "ResourceLoader.load"])

	if _declares_load.search(GDScriptText.blank(text)) != null:
		blocking = PackedStringArray(["ResourceLoader.load"])

	for loaded in GDScriptText.calls(text, blocking):
		var message := MESSAGE_BLOCKING % loaded.name
		problems.append(Problem.new(file.path, loaded.line, name, message))

	problems.sort_custom(func(a: Problem, b: Problem) -> bool: return a.line < b.line)

	return problems


func configure(values: Dictionary) -> void:
	_allow.clear()

	for pattern: Variant in values["allow"]:
		if pattern is String:
			_allow.append(pattern)

	if not _allow.is_empty():
		extensions = ["gd"]


func options() -> Dictionary:
	return {"allow": []}


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"resource-loader"
