##
## plugins/godot/checker/rules/uid.gd
##
## `uid` reports scenes and resources whose header carries no uid, and can assign one.
##
## NOTE: The engine never assigns a uid headless, and a script process does not save
## the uid cache, so run `godot --import --headless` after a fix.
##

extends "../core/rule.gd"

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	if _has_uid(file):
		return []

	var message := "no uid in header; re-run with --fix to assign one"
	return [Problem.new(file.path, 1, name, message)]


func fix(file: SourceFile) -> bool:
	if _has_uid(file):
		return false

	# NOTE: The header line alone is rewritten; the rest of the file, line endings
	# included, is written back byte for byte.
	var text := file.text()
	var end := text.find("\n")
	var header := text if end < 0 else text.substr(0, end)
	var close := header.rfind("]")

	if not header.begins_with("[") or close < 0:
		push_error("%s: no resource header on the first line" % file.path)
		return false

	var uid := ResourceUID.id_to_text(ResourceUID.create_id_for_path(file.path))
	header = header.left(close) + ' uid="%s"' % uid + header.substr(close)

	var out := FileAccess.open(file.path, FileAccess.WRITE)
	if out == null:
		push_error("%s: cannot write" % file.path)
		return false

	out.store_string(header if end < 0 else header + text.substr(end))
	out.close()

	return true


func fixable() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"uid"
	extensions = ["tscn", "tres"]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


func _has_uid(file: SourceFile) -> bool:
	var lines := file.lines()
	return not lines.is_empty() and lines[0].contains(' uid="')
