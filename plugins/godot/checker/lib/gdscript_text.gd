##
## plugins/godot/checker/lib/gdscript_text.gd
##
## GDScriptText holds what the checker knows about GDScript source as text: where code
## gives way to a comment or a string, and where a name begins.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEFINITIONS --------------------------------------------------------------------- #

## NAME_BOUNDARY keeps a name from matching as a member, a node path, or the tail of a
## longer identifier.
const NAME_BOUNDARY := "(?<![\\w.$%])"

## NON_CODE_PATTERN matches a comment or a string literal. A string matches from its
## opening quote, so a `#` inside one is never taken for a comment.
const NON_CODE_PATTERN := (
	"(?s)\\x22{3}(?:\\\\.|[^\\\\])*?\\x22{3}|\\x27{3}(?:\\\\.|[^\\\\])*?\\x27{3}"
	+ "|\\x22(?:\\\\.|[^\\x22\\\\\\n])*\\x22|\\x27(?:\\\\.|[^\\x27\\\\\\n])*\\x27"
	+ "|#[^\\n]*"
)

# -- INITIALIZATION ------------------------------------------------------------------ #

static var _non_code := RegEx.create_from_string(NON_CODE_PATTERN)

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## mask returns the source with every comment and string literal blanked out, so a scan
## reads code alone while each line still sits where it does in the file.
static func mask(text: String) -> String:
	var source := text.replace("\r\n", "\n")
	var masked := ""
	var cursor := 0

	for found: RegExMatch in _non_code.search_all(source):
		masked += source.substr(cursor, found.get_start() - cursor)

		# A span collapses to the newlines it held, so a multi-line string shifts
		# nothing reported below it.
		var length := found.get_end() - found.get_start()
		masked += "\n".repeat(source.substr(found.get_start(), length).count("\n"))

		cursor = found.get_end()

	return masked + source.substr(cursor)


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	assert(
		not OS.is_debug_build(),
		"Invalid config; this 'Object' should not be instantiated!"
	)
