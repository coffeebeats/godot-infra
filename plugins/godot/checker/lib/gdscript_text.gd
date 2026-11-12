##
## plugins/godot/checker/lib/gdscript_text.gd
##
## GDScriptText holds what the checker knows about GDScript source as text, such as
## where code gives way to a comment or a string, where a name begins, and what a call
## passes.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEFINITIONS --------------------------------------------------------------------- #

## LEADING_ANNOTATIONS matches the annotations, such as `@warning_ignore(...)`, that may
## precede a declaration on its line.
const LEADING_ANNOTATIONS := "(?:@\\w+(?:\\([^)]*\\))?\\s*)*"

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

## STATIC_FUNC_PATTERN matches the line declaring `_static_init`, which runs as soon as
## the script compiles, while the script cache is still locked. Annotations may precede
## it on the same line.
const STATIC_FUNC_PATTERN := (
	"^" + LEADING_ANNOTATIONS + "static\\s+func\\s+_static_init\\s*\\("
)

## STATIC_VAR_PATTERN matches the line declaring a `static var`, whose initializer runs
## when `_static_init` does. Annotations may precede it on the same line.
const STATIC_VAR_PATTERN := "^" + LEADING_ANNOTATIONS + "static\\s+var\\b"

## STRING_LITERAL_PATTERN matches an expression that is one string literal, quoted
## either way, triple-quoted or raw, and captures its text as whichever of its four
## groups took part.
const STRING_LITERAL_PATTERN := (
	"^\\s*(?:r?\\x22{3}((?:(?!\\x22{3})[^\\\\])*)\\x22{3}"
	+ "|r?\\x27{3}((?:(?!\\x27{3})[^\\\\])*)\\x27{3}"
	+ "|r?\\x22([^\\x22\\\\\\n]*)\\x22|r?\\x27([^\\x27\\\\\\n]*)\\x27)\\s*$"
)

# -- INITIALIZATION ------------------------------------------------------------------ #

## _non_code is `NON_CODE_PATTERN`, compiled once for every caller.
static var _non_code := RegEx.create_from_string(NON_CODE_PATTERN)

## _non_newline matches one character other than a newline.
static var _non_newline := RegEx.create_from_string("[^\\n]")

## _static_func is `STATIC_FUNC_PATTERN`, compiled once for every caller.
static var _static_func := RegEx.create_from_string(STATIC_FUNC_PATTERN)

## _static_var is `STATIC_VAR_PATTERN`, compiled once for every caller.
static var _static_var := RegEx.create_from_string(STATIC_VAR_PATTERN)

## _string_literal is `STRING_LITERAL_PATTERN`, compiled once for every caller.
static var _string_literal := RegEx.create_from_string(STRING_LITERAL_PATTERN)

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## blank returns the source with every comment, and every string literal unless
## `keep_strings`, overwritten by spaces. Unlike `mask` it moves nothing, so an offset
## found in it points at the same character of the source once that source's line
## endings are normalized to `\n`.
static func blank(text: String, keep_strings: bool = false) -> String:
	var source := text.replace("\r\n", "\n")
	var blanked := ""
	var cursor := 0

	for found: RegExMatch in _non_code.search_all(source):
		var span := found.get_string()
		blanked += source.substr(cursor, found.get_start() - cursor)

		if keep_strings and not span.begins_with("#"):
			blanked += span
		else:
			blanked += _non_newline.sub(span, " ", true)

		cursor = found.get_end()

	return blanked + source.substr(cursor)


## calls returns each call to one of `names` in the source, outside comments and
## strings. A plain name, such as `load` or `ResourceLoader.load`, matches only where
## it is not itself a member or a declaration, and a name opening with `.`, such as
## `.load_now`, matches a method of that name on any receiver.
##
## Each call is a dictionary holding its `name` as listed, its `line`, the `argument`
## text between its parentheses as written, and the `start` and `end` offsets of the
## whole call in the source with line endings normalized to `\n`. A call whose
## parentheses never close is left out.
static func calls(text: String, names: PackedStringArray) -> Array[Dictionary]:
	var source := text.replace("\r\n", "\n")
	var blanked := blank(source)
	var alternatives := PackedStringArray()

	for call_name in names:
		var escaped := call_name.replace(".", "\\.")

		if call_name.begins_with("."):
			alternatives.append("(?<=[\\w)\\]])" + escaped)
		else:
			alternatives.append(NAME_BOUNDARY + "(?<!func )" + escaped)

	var pattern := RegEx.create_from_string("(%s)\\s*\\(" % "|".join(alternatives))

	var found: Array[Dictionary] = []

	for result: RegExMatch in pattern.search_all(blanked):
		var opening := result.get_end() - 1
		var closing := _closing(blanked, opening)
		if closing < 0:
			continue

		(
			found
			. append(
				{
					"name": result.get_string(1),
					"line": blanked.substr(0, result.get_start()).count("\n") + 1,
					"argument": source.substr(opening + 1, closing - opening - 1),
					"start": result.get_start(),
					"end": closing + 1,
				}
			)
		)

	return found


## literal returns the text of the string literal `expression` consists of, or an empty
## string when it is anything else, such as a constant or a concatenation. A comment
## beside the literal is ignored.
static func literal(expression: String) -> String:
	var found := _string_literal.search(blank(expression, true))
	if found == null:
		return ""

	for group in range(1, 5):
		if found.get_start(group) >= 0:
			return found.get_string(group)

	return ""


## mask returns the source with every comment and string literal blanked out, so a scan
## reads code alone while each line still sits where it does in the file.
static func mask(text: String) -> String:
	var source := text.replace("\r\n", "\n")
	var masked := ""
	var cursor := 0

	for found: RegExMatch in _non_code.search_all(source):
		masked += source.substr(cursor, found.get_start() - cursor)

		# A span collapses to the newlines it held, so a multi-line string shifts no
		# line below it.
		var length := found.get_end() - found.get_start()
		masked += "\n".repeat(source.substr(found.get_start(), length).count("\n"))

		cursor = found.get_end()

	return masked + source.substr(cursor)


## parameters returns the expressions an argument list separates with commas, each as
## written. A comma inside a string, a comment or brackets separates nothing.
static func parameters(argument: String) -> PackedStringArray:
	var source := argument.replace("\r\n", "\n")
	var blanked := blank(source)
	var found := PackedStringArray()
	var depth := 0
	var cursor := 0

	for i in blanked.length():
		var character := blanked[i]

		if character in "([{":
			depth += 1
		elif character in ")]}":
			depth -= 1
		elif character == "," and depth == 0:
			found.append(source.substr(cursor, i - cursor))
			cursor = i + 1

	var rest := source.substr(cursor)
	if not rest.strip_edges().is_empty():
		found.append(rest)

	return found


## static_spans returns where the source runs while the script cache is still locked,
## as each span's start and end offset in a `Vector2i`: every `static var` declaration
## and the body of `_static_init`. Offsets count in the source with line endings
## normalized to `\n`.
static func static_spans(text: String) -> Array[Vector2i]:
	var lines := blank(text).split("\n")
	var spans: Array[Vector2i] = []
	var offset := 0
	var i := 0

	while i < lines.size():
		var code := lines[i].strip_edges(true, false)
		var indent := lines[i].length() - code.length()
		var start := offset

		if _static_var.search(code) != null:
			# NOTE: A declaration ends where its brackets close, unless a backslash
			# continues it. A trailing `:` opens its accessors, which run later.
			var depth := 0

			while i < lines.size():
				var line := lines[i]
				for character in line:
					if character in "([{":
						depth += 1
					elif character in ")]}":
						depth -= 1

				offset += line.length() + 1
				i += 1

				if depth <= 0 and not line.strip_edges().ends_with("\\"):
					break

			spans.append(Vector2i(start, offset))
			continue

		offset += lines[i].length() + 1
		i += 1

		if _static_func.search(code) == null:
			continue

		while i < lines.size():
			var body := lines[i].strip_edges(true, false)
			if not body.is_empty() and lines[i].length() - body.length() <= indent:
				break

			offset += lines[i].length() + 1
			i += 1

		spans.append(Vector2i(start, offset))

	return spans


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _closing returns the offset of the parenthesis closing the one at `opening` in
## blanked source, or -1 when none does.
static func _closing(blanked: String, opening: int) -> int:
	var depth := 0

	for i in range(opening, blanked.length()):
		var character := blanked[i]

		if character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
			if depth == 0:
				return i

	return -1


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	assert(
		not OS.is_debug_build(),
		"Invalid config; this 'Object' should not be instantiated!"
	)
