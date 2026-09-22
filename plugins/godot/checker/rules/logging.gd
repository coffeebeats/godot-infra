##
## plugins/godot/checker/rules/logging.gd
##
## `logging` reports a call to one of the engine's own output functions in a project
## that logs through something else. Such a call carries no logger name, no level and
## no timestamp, and nothing can filter or route it.
##
## NOTE: The rule covers no file until `.gdcheckrc` sets `disallow_engine_output`, since
## "never call `print()`" does not hold for a project with nothing to call instead.
##
## NOTE: `Node.print_tree()` and `print_orphan_nodes()` are callable bare too, but they
## dump engine state rather than emit a log line and have no logger equivalent.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const GDScriptText := preload("../lib/gdscript_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## CALL_PATTERN matches a call to an output function of `@GlobalScope` or `@GDScript`.
## The trailing `(` keeps `print` from matching the head of `print_rich`, NAME_BOUNDARY
## drops anything dotted, such as the logger's own `print` method, and `func ` drops a
## declaration that shadows one of these names.
const CALL_PATTERN := (
	GDScriptText.NAME_BOUNDARY
	+ "(?<!func )"
	+ "(print|printerr|printraw|print_rich|print_verbose|printt|prints"
	+ "|print_debug|print_stack|push_warning|push_error)\\s*\\("
)

# -- INITIALIZATION ------------------------------------------------------------------ #

var _call := RegEx.create_from_string(CALL_PATTERN)

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []
	var lines := GDScriptText.mask(file.text()).split("\n")

	for i in lines.size():
		for found: RegExMatch in _call.search_all(lines[i]):
			var fn := found.get_string(1)
			var message := "bare `%s()`; log through the project's logger" % fn
			problems.append(Problem.new(file.path, i + 1, name, message))

	return problems


func configure(config: Config) -> void:
	if config.disallow_engine_output:
		extensions = ["gd"]


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = Config.LOGGING
