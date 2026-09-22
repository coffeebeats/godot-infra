##
## plugins/godot/checker/rules/path_ref.gd
##
## `path-ref` reports references in a scene or resource that do not resolve, `res://`
## strings that should be uid references, and a dependency whose `path` names a
## different file than its `uid`.
##
## NOTE: A move rewrites `ext_resource` headers but not `res://` strings in properties,
## which then point at nothing, while a `uid://` reference survives it. A move made
## outside the editor rewrites neither, and the uid then hides the path left behind.
##
## NOTE: A scene with a missing `[ext_resource]` target still loads, so `load` never
## catches it.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const ResourceText := preload("../lib/resource_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## SELF_HEADER_PREFIXES mark the file's own header, which the `uid` rule owns.
const SELF_HEADER_PREFIXES: Array[String] = ["[gd_resource ", "[gd_scene "]

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []
	var lines := file.lines()

	for i in lines.size():
		var line := lines[i]

		if _is_self_header(line):
			continue

		if line.begins_with(ResourceText.EXT_RESOURCE_PREFIX):
			var broken := _describe_dependency(line)
			if broken != "":
				problems.append(Problem.new(file.path, i + 1, name, broken))

			continue

		for ref in ResourceText.references(line):
			var message := _describe(ref)
			if message != "":
				problems.append(Problem.new(file.path, i + 1, name, message))

	return problems


func fix(file: SourceFile) -> bool:
	# NOTE: The raw text is split on newlines alone, so a carriage return rides along at
	# the end of its line and the file is written back with its endings intact.
	var lines := file.text().split("\n")
	var changed := false

	for i in lines.size():
		var line: String = lines[i]
		if _is_self_header(line):
			continue

		var replaced := line

		if line.begins_with(ResourceText.EXT_RESOURCE_PREFIX):
			# NOTE: Only the path moves. The uid is what the engine reads, so rewriting
			# it would repoint the dependency rather than correct how it reads.
			var drift := _drift(line)
			if not drift.is_empty():
				replaced = line.replace('"%s"' % drift[0], '"%s"' % drift[1])
		else:
			for ref in ResourceText.references(line):
				var uid := _preferred_uid(ref)
				if uid != "":
					replaced = replaced.replace('"%s"' % ref, '"%s"' % uid)

		if replaced != line:
			lines[i] = replaced
			changed = true

	if not changed:
		return false

	var out := FileAccess.open(file.path, FileAccess.WRITE)
	if out == null:
		push_error("%s: cannot write" % file.path)
		return false

	out.store_string("\n".join(lines))
	out.close()

	return true


func fixable() -> bool:
	return true


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"path-ref"
	extensions = ["tscn", "tres"]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _describe returns what is wrong with a reference, or an empty string if it is fine.
func _describe(ref: String) -> String:
	if ref.begins_with("uid://"):
		return _describe_uid(ref)

	return _describe_path(ref)


## _describe_dependency returns what is wrong with an `[ext_resource]` header, or an
## empty string. One resolving reference on the line is enough for the dependency to
## load, since the engine falls back from the uid to the path; a header that loads can
## still name two different files.
func _describe_dependency(line: String) -> String:
	var references := PackedStringArray()
	var resolved := false

	for ref in ResourceText.references(line):
		if _resolves(ref):
			resolved = true

		references.append(ref)

	if references.is_empty():
		return ""

	if not resolved:
		return "dependency does not resolve: %s" % " ".join(references)

	var drift := _drift(line)
	if drift.is_empty():
		return ""

	return "path names %s but uid resolves to %s" % [drift[0], drift[1]]


## _drift returns the stale `res://` path a dependency header carries and the path its
## uid resolves to, in that order, or an empty array when the header carries no uid, no
## path, or two that already agree.
func _drift(line: String) -> PackedStringArray:
	var carried := ""
	var resolved := ""

	for ref in ResourceText.references(line):
		if ref.begins_with("uid://"):
			resolved = ResourceText.uid_path(ref)
		elif ref.begins_with("res://"):
			carried = ref

	if carried == "" or resolved == "" or carried == resolved:
		return PackedStringArray()

	return PackedStringArray([carried, resolved])


## _describe_path returns what is wrong with a `res://` reference, or an empty string.
func _describe_path(ref: String) -> String:
	if not _resolves(ref):
		return "path does not exist"

	var uid := _preferred_uid(ref)
	if uid == "":
		return ""

	return "reference this as %s; a res:// string is dropped on a move" % uid


## _describe_uid returns what is wrong with a `uid://` reference, or an empty string.
func _describe_uid(ref: String) -> String:
	var id := ResourceUID.text_to_id(ref)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return "unknown uid; if its target is new, run `godot --import --headless`"

	var target := ResourceUID.get_id_path(id)
	if not FileAccess.file_exists(target):
		return "uid resolves to a missing file: %s" % target

	return ""


## _is_self_header reports whether the line is the file's own resource header.
func _is_self_header(line: String) -> bool:
	for prefix in SELF_HEADER_PREFIXES:
		if line.begins_with(prefix):
			return true

	return false


## _preferred_uid returns the uid a `res://` reference should use, or an empty string
## when there is none, as for an unimported file, a directory, or a file with no uid.
func _preferred_uid(ref: String) -> String:
	if not ref.begins_with("res://"):
		return ""

	var id := ResourceLoader.get_resource_uid(ref)
	if id == ResourceUID.INVALID_ID:
		return ""

	return ResourceUID.id_to_text(id)


## _resolves reports whether a reference points at something that exists.
func _resolves(ref: String) -> bool:
	if ref.begins_with("uid://"):
		return _describe_uid(ref) == ""

	return FileAccess.file_exists(ref) or DirAccess.dir_exists_absolute(ref)
