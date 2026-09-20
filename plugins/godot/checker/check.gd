##
## plugins/godot/checker/check.gd
##
## Checks project files for problems a normal boot or import does not surface, and
## repairs the ones it can. The `godot` plugin's edit hook runs it on each edited file,
## and `check-project.yaml` runs it over the whole project.
##
## NOTE: The checker runs from outside the project, so `preload` cannot reach its own
## files, and a preloaded script naming anything unresolved hangs the engine. Keep rules
## in this file, or load them by absolute path with `ResourceLoader.load`.
##
## Usage, from the project root:
##   godot --headless -s <checker>                       # every rule, every file
##   godot --headless -s <checker> -- a.gd b.tscn        # only the given files
##   godot --headless -s <checker> -- --fix a.tscn       # repair, then re-check
##   godot --headless -s <checker> -- --list             # print the rule registry
##
## Reads `res://.gdcheckrc`, when present, for files to exclude and for the GDExtensions
## that may not load; see `Config`.
##
## Exits 1 when a problem is found or a repair applied, and 0 otherwise.
##

extends SceneTree

# -- DEFINITIONS --------------------------------------------------------------------- #

## CONFIG_ALL names the config section that applies to every rule.
const CONFIG_ALL := "all"

## CONFIG_PATH is the project's checker config; see `Config`.
const CONFIG_PATH := "res://.gdcheckrc"

## DEPENDENCY_PATTERN captures the path an `[ext_resource]` header points at.
const DEPENDENCY_PATTERN := 'path="([^"]+)"'

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

## SCAN_ROOT is the fallback root for rules that declare none of their own.
const SCAN_ROOT: Array[String] = ["res://"]

## SCAN_EXCLUDE names the directories never scanned. Vendored addons are not ours to
## check, and script templates hold `_BASE_` placeholders that do not compile.
const SCAN_EXCLUDE: Array[String] = ["addons", "script_templates"]

## SCRIPT_DEPENDENCY_PATTERN captures the path a script `preload`s or `extends`.
const SCRIPT_DEPENDENCY_PATTERN := (
	"(?m)(?:\\bpreload\\s*\\(\\s*|^(?:class_name\\s+\\w+\\s+)?extends\\s+)"
	+ "[\\x22\\x27]([^\\x22\\x27]+)[\\x22\\x27]"
)

## _blocked_cache maps each file a walk has settled to whether it reaches a script using
## a name from an extension that did not load; see `_blocked`.
var _blocked_cache: Dictionary = {}

var _dependency := RegEx.create_from_string(DEPENDENCY_PATTERN)
var _non_code := RegEx.create_from_string(NON_CODE_PATTERN)
var _script_dependency := RegEx.create_from_string(SCRIPT_DEPENDENCY_PATTERN)


## Problem is one rule violation. It formats as `path:line: [rule] message` so a
## terminal and an editor can both link to it; `line` is 0 when the rule has no line to
## point at.
class Problem:
	extends RefCounted

	var path: String
	var line: int
	var rule: StringName
	var message: String

	func _init(
		file_path: String, file_line: int, rule_name: StringName, text: String
	) -> void:
		path = file_path
		line = file_line
		rule = rule_name
		message = text

	## format renders the problem as a single reportable line.
	func format() -> String:
		if line > 0:
			return "%s:%d: [%s] %s" % [path, line, rule, message]

		return "%s: [%s] %s" % [path, rule, message]


## Config is the project's `.gdcheckrc`, in `ConfigFile` syntax. Section `all` applies
## to every rule and any other section to the rule it names. `excludes` lists `res://`
## globs of files to skip; `extensions`, only under `all`, maps each GDExtension the
## project uses to the global names it defines. A project without the file has an
## empty config.
class Config:
	extends RefCounted

	## EXTENSIONS_SHAPE describes the value `extensions` must hold.
	const EXTENSIONS_SHAPE := "a dictionary of .gdextension paths to arrays of names"

	## excludes maps a section to the globs of the files it skips.
	var excludes: Dictionary = {}

	## extensions maps a `.gdextension` path to the global names it defines.
	var extensions: Dictionary = {}

	## problems holds every error found in the file.
	var problems: Array[Problem] = []

	## parse reads `CONFIG_PATH`, accepting `all` and each of `rule_names` as a section.
	static func parse(rule_names: PackedStringArray) -> Config:
		var config := Config.new()
		if not FileAccess.file_exists(CONFIG_PATH):
			return config

		var file := ConfigFile.new()
		var err := file.load(CONFIG_PATH)
		if err != OK:
			config._error("does not parse: %s" % error_string(err))
			return config

		for section in file.get_sections():
			if section != CONFIG_ALL and section not in rule_names:
				config._error("unknown section [%s]" % section)
				continue

			for key in file.get_section_keys(section):
				var value: Variant = file.get_value(section, key)

				if key == "excludes":
					config._parse_excludes(section, value)
				elif key == "extensions" and section == CONFIG_ALL:
					config._parse_extensions(value)
				elif key == "extensions":
					config._error("[%s] extensions belongs under [all]" % section)
				else:
					config._error("unknown key `%s` in [%s]" % [key, section])

		return config

	## excluded reports whether the given section skips the file.
	func excluded(section: String, file_path: String) -> bool:
		var patterns: PackedStringArray = excludes.get(section, PackedStringArray())

		for pattern in patterns:
			if file_path.match(pattern):
				return true

		return false

	func _error(message: String) -> void:
		problems.append(Problem.new(CONFIG_PATH, 0, &"config", message))

	func _parse_excludes(section: String, value: Variant) -> void:
		if not _is_strings(value):
			_error("[%s] excludes must be an array of strings" % section)
			return

		var patterns := PackedStringArray()

		for pattern: String in value:
			if not pattern.begins_with("res://"):
				_error("[%s] exclude must start with res://: %s" % [section, pattern])
				continue

			patterns.append(pattern)

		excludes[section] = patterns

	func _parse_extensions(value: Variant) -> void:
		if not (value is Dictionary):
			_error("[all] extensions must be %s" % EXTENSIONS_SHAPE)
			return

		var entries: Dictionary = value

		for extension: Variant in entries:
			var names: Variant = entries[extension]

			if not (extension is String) or not _is_strings(names):
				_error("[all] extensions must be %s" % EXTENSIONS_SHAPE)
				continue

			# NOTE: An empty list would compile to a pattern matching every script.
			if names.is_empty():
				_error("[all] extension defines no names: %s" % extension)
				continue

			for identifier: String in names:
				if not identifier.is_valid_ascii_identifier():
					_error("[all] not an identifier: %s" % identifier)

			extensions[extension] = PackedStringArray(names)

	## _is_strings reports whether a value is an array holding only strings.
	static func _is_strings(value: Variant) -> bool:
		if not (value is Array or value is PackedStringArray):
			return false

		for element: Variant in value:
			if not (element is String):
				return false

		return true


## SourceFile is the per-file context every rule shares. The text is read once and the
## resource loaded and instantiated at most once, so N rules cost one read and one load.
class SourceFile:
	extends RefCounted

	var path: String

	var _instance: Node = null
	var _instantiated: bool = false
	var _lines := PackedStringArray()
	var _loaded: bool = false
	var _read: bool = false
	var _resource: Resource = null
	var _text: String = ""

	func _init(file_path: String) -> void:
		path = file_path

	## text returns the file's contents verbatim, line endings included.
	func text() -> String:
		if not _read:
			_read = true

			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				_text = file.get_as_text()
				_lines = _text.replace("\r\n", "\n").split("\n")

		return _text

	## lines returns the contents split on newlines, with carriage returns normalized out.
	func lines() -> PackedStringArray:
		text()
		return _lines

	## resource returns the loaded resource, or null if it does not load.
	func resource() -> Resource:
		if not _loaded:
			_loaded = true
			_resource = ResourceLoader.load(
				path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
			)

		return _resource

	## instance returns the instantiated scene root, or null if this is not a scene or it
	## does not load.
	func instance() -> Node:
		if not _instantiated:
			_instantiated = true

			var scene := resource() as PackedScene
			if scene != null:
				_instance = scene.instantiate()

		return _instance

	## release frees the instantiated scene, if one was created.
	func release() -> void:
		if _instance != null:
			_instance.free()
			_instance = null

	## reset drops everything cached, so rules running after a fix see the new contents.
	func reset() -> void:
		release()

		_instantiated = false
		_lines = PackedStringArray()
		_loaded = false
		_read = false
		_resource = null
		_text = ""


## Rule is one check over one kind of file. Subclasses set `name`, `extensions` and
## optionally `roots` or `files` in `_init` and override `check`; only rules that can
## repair what they find override `fix` and `fixable`.
class Rule:
	extends RefCounted

	var name: StringName = &""
	var extensions: Array[String] = []

	## files limits the rule to these exact paths, whether or not a walk would reach
	## them; an empty list covers every file with a matching extension.
	var files: Array[String] = []

	## roots limits the rule to these directories; an empty list covers the whole scan.
	var roots: Array[String] = []

	## applies reports whether this rule covers the given file.
	func applies(path: String) -> bool:
		if not files.is_empty():
			return path in files

		if path.get_extension() not in extensions:
			return false

		if roots.is_empty():
			return true

		for root in roots:
			if path.begins_with(root + "/"):
				return true

		return false

	## check reports every problem this rule finds in the file.
	func check(_file: SourceFile) -> Array[Problem]:
		return []

	## fix repairs what `check` reported and returns whether the file changed.
	func fix(_file: SourceFile) -> bool:
		return false

	## fixable reports whether this rule implements `fix`.
	func fixable() -> bool:
		return false

	## loads_file reports whether this rule needs the engine to load the file, which
	## succeeds only when every GDExtension the file depends on is present.
	func loads_file() -> bool:
		return false


## CompileRule reports scripts that do not compile.
##
## NOTE: A script that fails to parse still loads as non-null, so compilation is judged
## by its native base type; `--check-only` and `reload()` both misreport it.
class CompileRule:
	extends Rule

	## self_path is this checker's own path, which `check` skips because re-loading the
	## running script hangs the engine.
	var self_path: String = ""

	func _init() -> void:
		name = &"compile"
		extensions = ["gd"]

	func loads_file() -> bool:
		return true

	func check(file: SourceFile) -> Array[Problem]:
		if file.path == self_path:
			return []

		var script: Script = ResourceLoader.load(
			file.path, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)

		if script != null and script.get_instance_base_type() != &"":
			return []

		return [Problem.new(file.path, 0, name, "does not compile")]


## UidRule reports scenes and resources whose header carries no uid, and can assign one.
##
## NOTE: The engine never assigns a uid headless, and a script process does not save
## the uid cache, so run `godot --import --headless` after a fix.
class UidRule:
	extends Rule

	func _init() -> void:
		name = &"uid"
		extensions = ["tscn", "tres"]

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

	func _has_uid(file: SourceFile) -> bool:
		var lines := file.lines()
		return not lines.is_empty() and lines[0].contains(' uid="')


## PathRefRule reports references in a scene or resource that do not resolve,
## `res://` strings that should be uid references, and a dependency whose `path`
## names a different file than its `uid`.
##
## NOTE: A move rewrites `ext_resource` headers but not `res://` strings in properties,
## which then point at nothing, while a `uid://` reference survives it. A move made
## outside the editor rewrites neither, and the uid then hides the path left behind.
##
## NOTE: A scene with a missing `[ext_resource]` target still loads, so `load` never
## catches it.
class PathRefRule:
	extends Rule

	## EXT_RESOURCE_PREFIX marks a dependency header, whose `path` this rule rewrites
	## to agree with its uid, and whose uid it leaves alone.
	const EXT_RESOURCE_PREFIX := "[ext_resource "

	## REFERENCE_PATTERN matches one quoted `res://` or `uid://` string literal.
	const REFERENCE_PATTERN := '"((?:res|uid)://[^"]*)"'

	## SELF_HEADER_PREFIXES mark the file's own header, which the `uid` rule owns.
	const SELF_HEADER_PREFIXES: Array[String] = ["[gd_resource ", "[gd_scene "]

	var _reference := RegEx.create_from_string(REFERENCE_PATTERN)

	func _init() -> void:
		name = &"path-ref"
		extensions = ["tscn", "tres"]

	func check(file: SourceFile) -> Array[Problem]:
		var problems: Array[Problem] = []
		var lines := file.lines()

		for i in lines.size():
			var line := lines[i]

			if _is_self_header(line):
				continue

			if line.begins_with(EXT_RESOURCE_PREFIX):
				var broken := _describe_dependency(line)
				if broken != "":
					problems.append(Problem.new(file.path, i + 1, name, broken))

				continue

			for found in _reference.search_all(line):
				var message := _describe(found.get_string(1))
				if message != "":
					problems.append(Problem.new(file.path, i + 1, name, message))

		return problems

	func fix(file: SourceFile) -> bool:
		# NOTE: The raw text is split on newlines alone, so a carriage return rides along
		# at the end of its line and the file is written back with its endings intact.
		var lines := file.text().split("\n")
		var changed := false

		for i in lines.size():
			var line: String = lines[i]
			if _is_self_header(line):
				continue

			var replaced := line

			if line.begins_with(EXT_RESOURCE_PREFIX):
				# NOTE: Only the path moves. The uid is what the engine reads, so rewriting
				# it would repoint the dependency rather than correct how it reads.
				var drift := _drift(line)
				if not drift.is_empty():
					replaced = line.replace('"%s"' % drift[0], '"%s"' % drift[1])
			else:
				for found in _reference.search_all(line):
					var ref := found.get_string(1)
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

	## _describe returns what is wrong with a reference, or an empty string if it is fine.
	func _describe(ref: String) -> String:
		if ref.begins_with("uid://"):
			return _describe_uid(ref)

		return _describe_path(ref)

	## _describe_dependency returns what is wrong with an `[ext_resource]` header, or an
	## empty string. One resolving reference on the line is enough for the dependency to
	## load, since the engine falls back from the uid to the path; a header that loads
	## can still name two different files.
	func _describe_dependency(line: String) -> String:
		var references := PackedStringArray()
		var resolved := false

		for found in _reference.search_all(line):
			var ref := found.get_string(1)
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

	## _drift returns the stale `res://` path a dependency header carries and the path
	## its uid resolves to, in that order, or an empty array when the header carries no
	## uid, no path, or two that already agree.
	func _drift(line: String) -> PackedStringArray:
		var carried := ""
		var resolved := ""

		for found in _reference.search_all(line):
			var ref := found.get_string(1)

			if ref.begins_with("uid://"):
				resolved = _uid_path(ref)
			elif ref.begins_with("res://"):
				carried = ref

		if carried == "" or resolved == "" or carried == resolved:
			return PackedStringArray()

		return PackedStringArray([carried, resolved])

	## _uid_path returns the file a `uid://` reference resolves to, or an empty string
	## when it resolves to nothing. A uid naming a missing file is `_describe_uid`'s to
	## report, so it is not drift.
	func _uid_path(ref: String) -> String:
		var id := ResourceUID.text_to_id(ref)
		if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
			return ""

		var target := ResourceUID.get_id_path(id)

		return target if FileAccess.file_exists(target) else ""

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


## LoadRule reports files that do not parse or instantiate.
##
## NOTE: A project boot is no substitute, since quitting mid-load prints parse errors
## for well-formed scenes; this rule loads synchronously.
class LoadRule:
	extends Rule

	func _init() -> void:
		name = &"load"
		extensions = ["tscn", "tres"]

	func loads_file() -> bool:
		return true

	func check(file: SourceFile) -> Array[Problem]:
		if file.resource() == null:
			return [Problem.new(file.path, 0, name, "failed to load")]

		if file.path.get_extension() == "tres":
			return []

		if file.instance() == null:
			return [Problem.new(file.path, 0, name, "failed to instantiate")]

		return []


## ScriptOrderRule reports script-declared properties assigned ahead of `script =` in
## the same block, which Godot silently drops. Base-type properties are exempt, since
## they apply regardless of the script.
##
## NOTE: `[resource]` and `[sub_resource]` blocks are covered as well as `[node]`,
## since a hand-written `.tres` can carry a script and its exports too.
class ScriptOrderRule:
	extends Rule

	## PROPERTY_PATTERN matches a top-level property assignment, skipping continuation
	## lines of a multi-line value.
	const PROPERTY_PATTERN := "^([A-Za-z_][A-Za-z0-9_/]*) = "

	## SCRIPT_VALUE_PATTERN captures the ext_resource id a `script =` line references.
	const SCRIPT_VALUE_PATTERN := '^script = ExtResource\\("([^"]+)"\\)'

	## SCRIPT_RESOURCE_PATTERN captures the path and id of a declared script resource.
	const SCRIPT_RESOURCE_PATTERN := 'type="Script".*path="([^"]+)".*id="([^"]+)"'

	var _property := RegEx.create_from_string(PROPERTY_PATTERN)
	var _script_resource := RegEx.create_from_string(SCRIPT_RESOURCE_PATTERN)
	var _script_value := RegEx.create_from_string(SCRIPT_VALUE_PATTERN)

	func _init() -> void:
		name = &"script-order"
		extensions = ["tscn", "tres"]

	func loads_file() -> bool:
		return true

	func check(file: SourceFile) -> Array[Problem]:
		var problems: Array[Problem] = []
		var scripts := _script_resources(file)

		var in_block := false
		var preceding := PackedStringArray()
		var lines := file.lines()

		for i in lines.size():
			var line := lines[i]

			if line.begins_with("["):
				in_block = (
					line.begins_with("[node ")
					or line.begins_with("[resource")
					or line.begins_with("[sub_resource ")
				)
				preceding.clear()
				continue

			if not in_block:
				continue

			var found := _property.search(line)
			if found == null:
				continue

			var property := found.get_string(1)
			if property != "script":
				preceding.append(property)
				continue

			in_block = false

			if preceding.is_empty():
				continue

			var id := _script_value.search(line)
			if id == null:
				continue

			var exports := _script_exports(scripts.get(id.get_string(1), ""))
			var dropped := PackedStringArray()

			for candidate in preceding:
				if candidate in exports:
					dropped.append(candidate)

			if dropped.is_empty():
				continue

			var message := (
				"%s assigned before `script =`; silently dropped" % ", ".join(dropped)
			)
			problems.append(Problem.new(file.path, i + 1, name, message))

		return problems

	## _script_resources maps ext_resource ids to script paths for the given file.
	func _script_resources(file: SourceFile) -> Dictionary:
		var scripts := {}

		for line in file.lines():
			if not line.begins_with("[ext_resource "):
				continue

			var found := _script_resource.search(line)
			if found != null:
				scripts[found.get_string(2)] = found.get_string(1)

		return scripts

	## _script_exports returns the names of the properties a script itself declares.
	func _script_exports(script_path: String) -> PackedStringArray:
		var names := PackedStringArray()
		if script_path == "":
			return names

		var script: Script = ResourceLoader.load(script_path, "Script")
		if script == null:
			return names

		for property in script.get_script_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names.append(property.name)

		return names


## NodePathRule reports NodePath exports that resolve to null on the instantiated scene.
## The usual cause is a path pointing at a node whose type does not match the export's
## declared type, which Godot resolves to null without complaint.
class NodePathRule:
	extends Rule

	func _init() -> void:
		name = &"nodepath"
		extensions = ["tscn"]

	func loads_file() -> bool:
		return true

	func check(file: SourceFile) -> Array[Problem]:
		var problems: Array[Problem] = []

		var scene := file.resource() as PackedScene
		var root := file.instance()
		if scene == null or root == null:
			return problems

		var state := scene.get_state()

		for i in state.get_node_count():
			var node_path := state.get_node_path(i)
			var node := root.get_node_or_null(node_path)
			if node == null:
				continue

			for j in state.get_node_property_count(i):
				var value: Variant = state.get_node_property_value(i, j)
				if not (value is NodePath) or String(value) == "":
					continue

				var property := state.get_node_property_name(i, j)
				if node.get(property) != null:
					continue

				var message := (
					"node '%s' export `%s` points at '%s' but resolves to null"
					% [node_path, property, value]
				)
				problems.append(Problem.new(file.path, 0, name, message))

		return problems


## Disable3DRule reports a file naming a 3D type although the game ships on a template
## built with `disable_3d`, which defines none of them. Such a script fails to parse in
## the shipped game and takes everything depending on it down with it, while the editor,
## this checker and the tests all pass, since none of them runs on that engine.
##
## NOTE: A file declares itself 3D-only by name or directory, and the consts below say
## which. A project that is 3D throughout excludes `res://*` under `[disable-3d]`.
class Disable3DRule:
	extends Rule

	## DECLARED_3D_DIR is the directory name under which a 3D-only file may live.
	const DECLARED_3D_DIR := "3d"

	## DECLARED_3D_SUFFIX marks a 3D-only file by name.
	const DECLARED_3D_SUFFIX := "_3d"

	## EDITOR_DIR is the directory name for code an export leaves behind, which a
	## template therefore never loads whatever it names.
	const EDITOR_DIR := "editor"

	## STRIPPED_NAMES are the classes the flag removes whose names do not end in `3D`.
	## They are the registrations guarded by `_3D_DISABLED` in Godot 4.7.2, taken from
	## the engine source, since nothing in a running editor reports them.
	const STRIPPED_NAMES := [
		"BoxMesh",
		"CapsuleMesh",
		"CylinderMesh",
		"Decal",
		"FogMaterial",
		"FogVolume",
		"GridMap",
		"GridMapEditorPlugin",
		"ImporterMesh",
		"LightmapGI",
		"LightmapGIData",
		"LightmapProbe",
		"Lightmapper",
		"LightmapperRD",
		"MeshLibrary",
		"Node3DGizmo",
		"PanoramaSkyMaterial",
		"PhysicalSkyMaterial",
		"PlaneMesh",
		"PointMesh",
		"PrimitiveMesh",
		"PrismMesh",
		"ProceduralSkyMaterial",
		"QuadMesh",
		"ReflectionProbe",
		"RibbonTrailMesh",
		"RootMotionView",
		"Skin",
		"SkinReference",
		"SphereMesh",
		"TextMesh",
		"TorusMesh",
		"TubeTrailMesh",
		"VoxelGI",
		"VoxelGIData",
		"WorldEnvironment",
	]

	## STRIPPED_SUFFIX_PATTERN captures a class name ending in `3D`, as the other 122 the
	## flag removes all are. `Transform3D` is a Variant type it keeps, and no class name
	## carries an underscore, so a constant like `TEMPLATE_3D` reads as a name.
	const STRIPPED_SUFFIX_PATTERN := "(?!Transform3D)[A-Z][A-Za-z0-9]*3D"

	## TEST_SUFFIX marks a test script, which every export excludes and which is the one
	## place a 2D game exercises a 3D type.
	const TEST_SUFFIX := "_test"

	## TYPE_PATTERN captures the class a scene or resource header names as a node's, a
	## sub-resource's or a dependency's type. Nothing else in such a file resolves to a
	## class, so a node named `Player3D` is a label rather than a use.
	const TYPE_PATTERN := 'type="([^"]+)"'

	var _non_code := RegEx.create_from_string(NON_CODE_PATTERN)
	var _stripped: RegEx = null
	var _type := RegEx.create_from_string(TYPE_PATTERN)

	func _init() -> void:
		name = &"disable-3d"
		extensions = ["gd", "tscn", "tres"]

		var alternatives := (
			"%s|%s" % [STRIPPED_SUFFIX_PATTERN, "|".join(STRIPPED_NAMES)]
		)
		_stripped = RegEx.create_from_string(NAME_BOUNDARY + "(%s)\\b" % alternatives)

	func applies(path: String) -> bool:
		if not super(path):
			return false

		if path.get_file().get_basename().ends_with(TEST_SUFFIX):
			return false

		return not _unshipped(path)

	func check(file: SourceFile) -> Array[Problem]:
		var problems: Array[Problem] = []
		var lines := _code(file)

		for i in lines.size():
			for found in _stripped.search_all(lines[i]):
				var message := (
					"names `%s`, which a `disable_3d` template does not define"
					% found.get_string(1)
				)
				problems.append(Problem.new(file.path, i + 1, name, message))

		return problems

	## _code returns the names a stripped template has to resolve. A script's comments
	## and string literals are blanked, since a type named in prose resolves to nothing,
	## and a scene or resource keeps only the types its headers declare.
	func _code(file: SourceFile) -> PackedStringArray:
		if file.path.get_extension() != "gd":
			return _declared(file.lines())

		var text := file.text().replace("\r\n", "\n")
		var code := ""
		var last := 0

		# NOTE: Each stripped run leaves its newlines behind, so a problem still reports
		# the line it was found on.
		for found in _non_code.search_all(text):
			var start := found.get_start()
			var run := text.substr(start, found.get_end() - start)

			code += text.substr(last, start - last)
			code += "\n".repeat(run.count("\n"))

			last = found.get_end()

		code += text.substr(last)

		return code.split("\n")

	## _declared returns the types each line's headers name, joined, one entry per line.
	func _declared(lines: PackedStringArray) -> PackedStringArray:
		var out := PackedStringArray()

		for line in lines:
			var names := PackedStringArray()

			for found in _type.search_all(line):
				names.append(found.get_string(1))

			out.append(" ".join(names))

		return out

	## _unshipped reports whether a file's name or location says a stripped template
	## never has to load it, because it is 3D-only or editor-only.
	static func _unshipped(path: String) -> bool:
		if path.get_file().get_basename().ends_with(DECLARED_3D_SUFFIX):
			return true

		var directories := path.get_base_dir().split("/")

		return DECLARED_3D_DIR in directories or EDITOR_DIR in directories


## ExportOverridesRule reports export presets whose values differ from the ones
## `res://export_overrides.cfg` declares, and writes them. Each of its sections covers
## the presets its name globs, so one declaration serves every storefront, platform,
## component and architecture. A project without the file is left alone.
##
## NOTE: The editor caches presets at startup and writes them back when the export
## dialog opens or it exits, so run `--fix` with the editor closed.
##
## NOTE: The rule checks each glob against the files present, so a checkout without its
## submodules reports every addon glob as matching nothing.
class ExportOverridesRule:
	extends Rule

	## LIST_KEYS name the preset keys declared as a list and accumulated across every
	## section matching a preset, which is every key holding a comma-separated glob.
	const LIST_KEYS := ["exclude_filter", "include_filter"]

	## OPTIONS_PREFIX marks a declared key belonging to a preset's options block.
	const OPTIONS_PREFIX := "options/"

	const OVERRIDES_PATH := "res://export_overrides.cfg"
	const PRESETS_PATH := "res://export_presets.cfg"

	var _tree := PackedStringArray()
	var _walked: bool = false

	func _init() -> void:
		name = &"export-overrides"
		extensions = ["cfg"]
		files = [PRESETS_PATH]

	func check(file: SourceFile) -> Array[Problem]:
		var problems: Array[Problem] = []

		if not FileAccess.file_exists(OVERRIDES_PATH):
			return problems

		var overrides := ConfigFile.new()
		var err := overrides.load(OVERRIDES_PATH)
		if err != OK:
			var message := "does not parse: %s" % error_string(err)
			problems.append(Problem.new(OVERRIDES_PATH, 0, name, message))
			return problems

		var presets := ConfigFile.new()
		err = presets.load(file.path)
		if err != OK:
			var message := "does not parse: %s" % error_string(err)
			problems.append(Problem.new(file.path, 0, name, message))
			return problems

		var names := _preset_names(presets)

		problems.append_array(_check_sections(overrides, names))
		problems.append_array(_check_globs(overrides))

		var differences := _check_presets(file, presets, overrides, names)
		problems.append_array(differences)

		# NOTE: Reported only alongside a difference, since a file the rule never needs
		# to write is fine in any form.
		if not differences.is_empty() and not _reproducible(file.text(), presets):
			var message := (
				"not in the form the editor writes, so --fix would drop part of it;"
				+ " open the export dialog once, save, and run it again"
			)
			problems.append(Problem.new(file.path, 0, name, message))

		return problems

	func fix(file: SourceFile) -> bool:
		var overrides := _declaration()
		if overrides == null:
			return false

		var text := file.text()
		var presets := ConfigFile.new()

		if presets.load(file.path) != OK or not _reproducible(text, presets):
			return false

		var names := _preset_names(presets)
		var changed := false

		for section: String in names:
			var declared := _assemble(names[section], overrides)

			for key: String in declared:
				var target_section := _target_section(section, key)
				var target_key := _target_key(key)

				if not presets.has_section_key(target_section, target_key):
					continue

				var current: Variant = presets.get_value(target_section, target_key)
				var wanted: Variant = _coerced(current, declared[key])

				if typeof(wanted) != typeof(current) or current == wanted:
					continue

				presets.set_value(target_section, target_key, wanted)
				changed = true

		if not changed:
			return false

		return _store(file.path, _render(text, presets.encode_to_text()))

	func fixable() -> bool:
		return true

	## _assemble returns every key the sections matching a preset name declare for it,
	## each `LIST_KEYS` entry accumulated into the glob string the preset holds.
	static func _assemble(preset_name: String, overrides: ConfigFile) -> Dictionary:
		var declared := {}
		var lists := {}

		for section in overrides.get_sections():
			if not preset_name.match(section):
				continue

			for key in overrides.get_section_keys(section):
				var value: Variant = overrides.get_value(section, key)

				if key not in LIST_KEYS:
					declared[key] = value
					continue

				if not Config._is_strings(value):
					continue

				var globs: PackedStringArray = lists.get(key, PackedStringArray())

				for entry: String in value:
					var glob := _to_glob(entry)
					if glob != "" and glob not in globs:
						globs.append(glob)

				lists[key] = globs

		for key: String in lists:
			declared[key] = ",".join(lists[key])

		return declared

	## _check_globs reports each declared entry that names nothing in the project.
	func _check_globs(overrides: ConfigFile) -> Array[Problem]:
		var problems: Array[Problem] = []
		var lines := _lines(OVERRIDES_PATH)

		for section in overrides.get_sections():
			for key: String in LIST_KEYS:
				if not overrides.has_section_key(section, key):
					continue

				var line := _line_of(lines, section, key)
				var value: Variant = overrides.get_value(section, key)

				if not Config._is_strings(value):
					var shape := "[%s] %s must be an array of strings" % [section, key]
					problems.append(Problem.new(OVERRIDES_PATH, line, name, shape))
					continue

				for entry: String in value:
					var glob := _to_glob(entry)

					if glob == "":
						var missing := (
							"[%s] `%s` names no file or directory in the project"
							% [section, entry]
						)
						problems.append(
							Problem.new(OVERRIDES_PATH, line, name, missing)
						)
						continue

					if not _matches_any(glob):
						var empty := "[%s] `%s` matches no file" % [section, entry]
						problems.append(Problem.new(OVERRIDES_PATH, line, name, empty))

		return problems

	## _check_presets reports each preset key whose value differs from the declared one,
	## and each declared key the preset does not carry.
	func _check_presets(
		file: SourceFile, presets: ConfigFile, overrides: ConfigFile, names: Dictionary
	) -> Array[Problem]:
		var problems: Array[Problem] = []
		var lines := file.lines()

		for section: String in names:
			var preset_name: String = names[section]
			var declared := _assemble(preset_name, overrides)

			for key: String in declared:
				var target_section := _target_section(section, key)
				var target_key := _target_key(key)

				# NOTE: The editor writes every key its platform defines and drops the
				# rest on load, so a key it does not carry is never written here.
				if not presets.has_section_key(target_section, target_key):
					var absent := (
						"%s: carries no `%s`; check the key against the platform"
						% [preset_name, key]
					)
					problems.append(Problem.new(file.path, 0, name, absent))
					continue

				var current: Variant = presets.get_value(target_section, target_key)
				var wanted: Variant = _coerced(current, declared[key])
				var line := _line_of(lines, target_section, target_key)

				# NOTE: Writing a value of another type would leave the preset holding
				# something the editor cannot read back, so it is reported instead.
				if typeof(wanted) != typeof(current):
					var mismatch := (
						"%s: `%s` is declared as %s but the preset holds %s"
						% [
							preset_name,
							key,
							type_string(typeof(wanted)),
							type_string(typeof(current)),
						]
					)
					problems.append(Problem.new(file.path, line, name, mismatch))
					continue

				if current == wanted:
					continue

				var message := (
					"%s: `%s` differs from %s; re-run with --fix"
					% [preset_name, key, OVERRIDES_PATH]
				)
				problems.append(Problem.new(file.path, line, name, message))

		return problems

	## _check_sections reports each section whose glob names no preset.
	func _check_sections(overrides: ConfigFile, names: Dictionary) -> Array[Problem]:
		var problems: Array[Problem] = []
		var lines := _lines(OVERRIDES_PATH)

		for section in overrides.get_sections():
			var matched := false

			for preset_name: String in names.values():
				if preset_name.match(section):
					matched = true
					break

			if matched:
				continue

			var message := "[%s] matches no preset" % section
			var line := _line_of(lines, section, "")
			problems.append(Problem.new(OVERRIDES_PATH, line, name, message))

		return problems

	## _files returns every file the exporter's walk reaches, without the scheme.
	func _files() -> PackedStringArray:
		if not _walked:
			_walked = true
			_collect("res://", _tree)

		return _tree

	## _matches_any reports whether any file matches a glob, trying it against both the
	## bare path and the `res://` one, as the exporter does.
	func _matches_any(glob: String) -> bool:
		for path in _files():
			if path.matchn(glob) or ("res://" + path).matchn(glob):
				return true

		return false

	## _collect appends every file under a directory, passing over the directories the
	## exporter ignores, those named with a leading period and those holding a
	## `.gdignore`.
	static func _collect(dir_path: String, found: PackedStringArray) -> void:
		var dir := DirAccess.open(dir_path)
		if dir == null or dir.file_exists(".gdignore"):
			return

		dir.list_dir_begin()

		var entry := dir.get_next()
		while entry != "":
			var path := dir_path.path_join(entry)

			if dir.current_is_dir():
				if not entry.begins_with("."):
					_collect(path, found)
			else:
				found.append(path.trim_prefix("res://"))

			entry = dir.get_next()

		dir.list_dir_end()

	## _declaration returns the project's declaration, or null when it is absent or does
	## not parse. `check` reports a declaration that does not parse.
	static func _declaration() -> ConfigFile:
		if not FileAccess.file_exists(OVERRIDES_PATH):
			return null

		var overrides := ConfigFile.new()
		if overrides.load(OVERRIDES_PATH) != OK:
			return null

		return overrides

	## _store writes text to a file, reporting whether it succeeded.
	static func _store(path: String, text: String) -> bool:
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out == null:
			push_error("%s: cannot write" % path)
			return false

		out.store_string(text)
		out.close()

		return true

	## _coerced returns a declared value as the type the preset already holds, so an
	## array written in the declaration stays the packed array the editor expects.
	static func _coerced(current: Variant, declared: Variant) -> Variant:
		if current is PackedStringArray and declared is Array:
			return PackedStringArray(declared)

		return declared

	## _line_of returns the 1-based line a key sits on within a section, or the section's
	## own header when `key` is empty, and 0 when neither is there.
	static func _line_of(lines: PackedStringArray, section: String, key: String) -> int:
		var header := "[%s]" % section
		var within := false

		for i in lines.size():
			var line := lines[i].strip_edges()

			if line.begins_with("["):
				within = line == header

				if within and key == "":
					return i + 1

				continue

			if within and line.begins_with(key + "="):
				return i + 1

		return 0

	## _lines returns a file's contents split on newlines, carriage returns removed.
	static func _lines(path: String) -> PackedStringArray:
		return FileAccess.get_file_as_string(path).replace("\r\n", "\n").split("\n")

	## _preset_names maps each preset's section to the name it carries.
	static func _preset_names(presets: ConfigFile) -> Dictionary:
		var names := {}

		for section in presets.get_sections():
			if section.ends_with(".options"):
				continue

			var preset_name: String = presets.get_value(section, "name", "")
			if preset_name != "":
				names[section] = preset_name

		return names

	## _render returns an encoded config under the line ending the file already uses.
	static func _render(text: String, encoded: String) -> String:
		var normalized := encoded.replace("\r\n", "\n")

		if not text.contains("\r\n"):
			return normalized

		return normalized.replace("\n", "\r\n")

	## _reproducible reports whether writing the config back would reproduce the file
	## byte for byte, which is what proves a write would drop nothing the file holds and
	## would carry its line ending exactly.
	static func _reproducible(text: String, presets: ConfigFile) -> bool:
		return _render(text, presets.encode_to_text()) == text

	## _target_key returns the preset key a declared key names.
	static func _target_key(key: String) -> String:
		return key.trim_prefix(OPTIONS_PREFIX)

	## _target_section returns the preset section a declared key belongs in.
	static func _target_section(section: String, key: String) -> String:
		return section + ".options" if key.begins_with(OPTIONS_PREFIX) else section

	## _to_glob returns the exporter glob an entry names, recursive for a directory and
	## as written for a file or a pattern, or an empty string when it names nothing.
	static func _to_glob(entry: String) -> String:
		if entry.contains("*") or entry.contains("?"):
			return entry

		var path := entry if entry.begins_with("res://") else "res://" + entry

		if DirAccess.dir_exists_absolute(path):
			return entry.trim_suffix("/") + "/*"

		if FileAccess.file_exists(path):
			return entry

		return ""


## ExportRefRule reports a file an export keeps whose dependency that same export drops.
## An excluded implementation is reachable only by a string the engine resolves when the
## build allows it, such as a `uid://` on a condition loader, and never by an
## `[ext_resource]` header, which the loader follows the moment the file is opened.
##
## NOTE: Keyed on `export_presets.cfg`, so the `godot` plugin's edit hook runs it when
## the presets change rather than on each edited scene. A crossing introduced by a scene
## edit is caught by the whole-project run.
##
## NOTE: A glob naming a file the exporter force-exports, such as the project icon,
## excludes nothing; a crossing reported into one is a dead glob rather than a broken
## reference.
class ExportRefRule:
	extends Rule

	## EXCLUDE_KEY is the declared key whose globs decide what an export leaves out.
	const EXCLUDE_KEY := "exclude_filter"

	## REFERRING_EXTENSIONS are the files carrying `[ext_resource]` headers.
	const REFERRING_EXTENSIONS: Array[String] = ["tscn", "tres"]

	var _reference := RegEx.create_from_string(PathRefRule.REFERENCE_PATTERN)

	func _init() -> void:
		name = &"export-ref"
		extensions = ["cfg"]
		files = [ExportOverridesRule.PRESETS_PATH]

	func check(file: SourceFile) -> Array[Problem]:
		var problems: Array[Problem] = []

		var overrides := ExportOverridesRule._declaration()
		if overrides == null:
			return problems

		# NOTE: `export-overrides` reports a presets file that does not parse.
		var presets := ConfigFile.new()
		if presets.load(file.path) != OK:
			return problems

		var tree := PackedStringArray()
		ExportOverridesRule._collect("res://", tree)

		var dependencies := _dependencies(tree)
		if dependencies.is_empty():
			return problems

		var crossings := {}
		var names := ExportOverridesRule._preset_names(presets)

		for section: String in names:
			var preset: String = names[section]
			var declared := ExportOverridesRule._assemble(preset, overrides)
			var globs: String = declared.get(EXCLUDE_KEY, "")
			if globs == "":
				continue

			var excluded := _excluded(tree, globs.split(",", false))
			if excluded.is_empty():
				continue

			for index in dependencies.size():
				var dependency := dependencies[index]

				if dependency[&"file"] in excluded:
					continue

				if dependency[&"target"] not in excluded:
					continue

				var reported: PackedStringArray = crossings.get(
					index, PackedStringArray()
				)
				reported.append(preset)
				crossings[index] = reported

		for index: int in crossings:
			var dependency := dependencies[index]
			var message := (
				"dependency is excluded from %s: res://%s"
				% [", ".join(crossings[index]), dependency[&"target"]]
			)
			problems.append(
				Problem.new(
					"res://" + dependency[&"file"], dependency[&"line"], name, message
				)
			)

		return problems

	## _dependencies returns every `[ext_resource]` header in the project, as the file
	## carrying it, the line it sits on and the file it points at.
	func _dependencies(tree: PackedStringArray) -> Array[Dictionary]:
		var out: Array[Dictionary] = []

		for path in tree:
			if path.get_extension() not in REFERRING_EXTENSIONS:
				continue

			var lines := ExportOverridesRule._lines("res://" + path)

			for i in lines.size():
				if not lines[i].begins_with(PathRefRule.EXT_RESOURCE_PREFIX):
					continue

				var target := _target(lines[i])
				if target != "":
					out.append({&"file": path, &"line": i + 1, &"target": target})

		return out

	## _target returns the file a dependency header points at, without the scheme, or an
	## empty string when it points at nothing. A uid that resolves wins, since that is
	## what the engine loads.
	func _target(line: String) -> String:
		var carried := ""

		for found in _reference.search_all(line):
			var ref := found.get_string(1)

			if ref.begins_with("uid://"):
				var id := ResourceUID.text_to_id(ref)
				if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
					return ResourceUID.get_id_path(id).trim_prefix("res://")
			elif ref.begins_with("res://"):
				carried = ref.trim_prefix("res://")

		return carried

	## _excluded returns the files a set of globs drops, as a set, matching them against
	## both the bare path and the `res://` one, as the exporter does.
	static func _excluded(
		tree: PackedStringArray, globs: PackedStringArray
	) -> Dictionary:
		var out := {}

		for path in tree:
			for glob in globs:
				if path.matchn(glob) or ("res://" + path).matchn(glob):
					out[path] = true
					break

		return out


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rules := _registry()

	var rule_names := PackedStringArray()
	for rule in rules:
		rule_names.append(rule.name)

	var config := Config.parse(rule_names)

	if not config.problems.is_empty():
		for problem in config.problems:
			print("  ", problem.format())

		print("checked 0 file(s); fix %s first" % CONFIG_PATH)
		quit(1)
		return

	if args.has("--list"):
		_list(rules)
		quit(0)
		return

	var should_fix := args.has("--fix")
	var missing := _missing_extensions(config)
	var blocking := _blocking_pattern(missing)

	var paths: Array[String] = []
	var expanded := {}

	for arg in args:
		if arg.begins_with("--"):
			continue

		var path := _localize(arg)

		# A directory argument is expanded rather than checked, since a path no rule
		# applies to would otherwise be reported as clean.
		if DirAccess.dir_exists_absolute(path):
			_scan(path, _extensions(rules), expanded)

			var prefix := path if path.ends_with("/") else path + "/"

			for rule in rules:
				for rule_file: String in rule.files:
					if (
						rule_file.begins_with(prefix)
						and FileAccess.file_exists(rule_file)
					):
						expanded[rule_file] = true

			continue

		paths.append(path)

	if not expanded.is_empty():
		var found: Array[String] = []
		found.append_array(expanded.keys())
		found.sort()
		paths.append_array(found)

	if paths.is_empty():
		paths = _discover(rules)

	# NOTE: A file excluded from every rule is dropped before checking, whether it was
	# discovered or named, so it is neither fixed nor counted.
	var excluded := 0
	var kept: Array[String] = []

	for path in paths:
		if config.excluded(CONFIG_ALL, path):
			excluded += 1
		else:
			kept.append(path)

	paths = kept

	var problems: Array[Problem] = []
	var fixed := 0
	var skipped: Array[String] = []

	for path in paths:
		var file := SourceFile.new(path)
		var unloadable := blocking != null and _blocked(path, blocking)
		var held := false

		for rule in rules:
			if not rule.applies(path) or config.excluded(rule.name, path):
				continue

			if unloadable and rule.loads_file():
				held = true
				continue

			var found := rule.check(file)

			if not found.is_empty() and should_fix and rule.fixable():
				if rule.fix(file):
					fixed += 1
					file.reset()
					found = rule.check(file)

			problems.append_array(found)

		if held:
			skipped.append(path)

		file.release()

	for problem in problems:
		print("  ", problem.format())

	print("checked %d file(s), %d problem(s)" % [paths.size(), problems.size()])

	if excluded > 0:
		print("excluded %d file(s) through %s" % [excluded, CONFIG_PATH])

	var unloaded := ", ".join(PackedStringArray(missing.keys()))

	if not skipped.is_empty():
		print(
			(
				"skipped the loading rules for %d file(s): %s not loaded"
				% [skipped.size(), unloaded]
			)
		)

		for path in skipped:
			print("  ", path)

	if not problems.is_empty() and not missing.is_empty():
		print(
			(
				(
					"note: %s is not loaded here; if a script above uses a name it"
					% unloaded
				)
				+ " defines, add the name under `extensions` in %s" % CONFIG_PATH
			)
		)

	if fixed > 0:
		print(
			"fixed %d file(s); run `godot --import --headless` so they resolve" % fixed
		)

	# NOTE: `SceneTree.quit()` collapses every non-zero code to 1 under `-s`, so a problem
	# found and a repair applied both exit 1.
	quit(1 if not problems.is_empty() or fixed > 0 else 0)


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _blocked reports whether a file is a script using a name `names` matches, or depends
## on one to any depth; see `_dependencies`.
##
## NOTE: A scene naming a blocked script in a header still loads and instantiates, so
## without the walk every rule would pass it unchecked.
func _blocked(path: String, names: RegEx) -> bool:
	var visited := {}

	if _reaches_blocked(path, names, visited):
		return true

	# NOTE: A walk that finds nothing proves every file it visited clean. One that finds a
	# blocked script stops early, so only the files on the way to it are settled.
	for visited_path: String in visited:
		_blocked_cache[visited_path] = false

	return false


## _blocking_pattern returns a pattern matching a use of any name a missing extension
## defines, or null when no extension is missing.
func _blocking_pattern(missing: Dictionary) -> RegEx:
	if missing.is_empty():
		return null

	var names := PackedStringArray()

	for extension: String in missing:
		names.append_array(missing[extension])

	return RegEx.create_from_string(NAME_BOUNDARY + ("(?:%s)\\b" % "|".join(names)))


## _dependencies returns the files a file needs in order to load: the `[ext_resource]`
## headers of a scene or resource, and the paths a script `preload`s or `extends`.
##
## NOTE: A script referring to another only by its `class_name` is not followed.
func _dependencies(path: String, text: String) -> PackedStringArray:
	var found := PackedStringArray()

	if path.get_extension() == "gd":
		for result: RegExMatch in _script_dependency.search_all(text):
			var target := result.get_string(1)

			if not target.contains("://"):
				target = path.get_base_dir().path_join(target).simplify_path()

			found.append(target)

		return found

	for line in text.split("\n"):
		if not line.begins_with("[ext_resource "):
			continue

		var result := _dependency.search(line)
		if result != null:
			found.append(result.get_string(1))

	return found


## _discover returns every file any rule covers, sorted and free of duplicates.
func _discover(rules: Array[Rule]) -> Array[String]:
	var seen := {}

	for rule in rules:
		if not rule.files.is_empty():
			for rule_file in rule.files:
				if FileAccess.file_exists(rule_file):
					seen[rule_file] = true

			continue

		for rule_root in rule.roots if not rule.roots.is_empty() else SCAN_ROOT:
			_scan(rule_root, rule.extensions, seen)

	var found: Array[String] = []
	found.append_array(seen.keys())
	found.sort()

	return found


## _extensions returns every extension covered by any rule, free of duplicates.
func _extensions(rules: Array[Rule]) -> Array[String]:
	var found: Array[String] = []

	for rule in rules:
		if not rule.files.is_empty():
			continue

		for extension in rule.extensions:
			if extension not in found:
				found.append(extension)

	return found


## _list prints each rule with the files it covers and whether it can fix them.
func _list(rules: Array[Rule]) -> void:
	for rule in rules:
		var roots := SCAN_ROOT if rule.roots.is_empty() else rule.roots
		print(
			(
				"%-16s %-12s %-45s %s"
				% [
					rule.name,
					" ".join(PackedStringArray(rule.extensions)),
					(
						" ".join(PackedStringArray(rule.files))
						if not rule.files.is_empty()
						else " ".join(PackedStringArray(roots))
					),
					"fixable" if rule.fixable() else "",
				]
			)
		)


## _localize turns a relative or native absolute command-line path into a `res://` path.
func _localize(path: String) -> String:
	if path.begins_with("res://"):
		return path.simplify_path()

	if path.is_absolute_path():
		return ProjectSettings.localize_path(path)

	return "res://" + path.simplify_path()


## _missing_extensions returns each extension in the config that this process did not
## load, mapped to the names it defines. An extension absent from the checkout, such as
## an uninitialized submodule, counts as not loaded.
##
## NOTE: A GDExtension with no binary for the platform does not load, so scripts naming
## its API fail to parse. GodotSteam ships no Linux binary.
func _missing_extensions(config: Config) -> Dictionary:
	var missing := {}

	for extension: String in config.extensions:
		if not GDExtensionManager.is_extension_loaded(extension):
			missing[extension] = config.extensions[extension]

	return missing


## _reaches_blocked walks a file's dependencies depth-first, settling each file it finds
## to reach a blocked script.
func _reaches_blocked(path: String, names: RegEx, visited: Dictionary) -> bool:
	if path in _blocked_cache:
		return _blocked_cache[path]

	if path in visited:
		return false

	visited[path] = true

	var extension := path.get_extension()
	if extension not in ["gd", "tscn", "tres"]:
		return false

	var text := FileAccess.get_file_as_string(path)

	if extension == "gd" and names.search(_non_code.sub(text, " ", true)) != null:
		_blocked_cache[path] = true
		return true

	for dependency in _dependencies(path, text):
		if _reaches_blocked(dependency, names, visited):
			_blocked_cache[path] = true
			return true

	return false


## _registry returns every rule in the order they run; discovery, dispatch and `--list`
## all follow from it. `uid` runs ahead of the rules that load a scene, so `--fix`
## repairs the header first.
func _registry() -> Array[Rule]:
	var compile := CompileRule.new()
	compile.self_path = get_script().resource_path

	var rules: Array[Rule] = []
	rules.append(compile)
	rules.append(UidRule.new())
	rules.append(PathRefRule.new())
	rules.append(LoadRule.new())
	rules.append(ScriptOrderRule.new())
	rules.append(NodePathRule.new())
	rules.append(ExportOverridesRule.new())
	rules.append(ExportRefRule.new())
	rules.append(Disable3DRule.new())

	return rules


## _scan records every file under a directory carrying one of the given extensions.
##
## NOTE: Hidden directories are skipped outright, since `.git` alone holds ~11k files,
## and so is any directory holding a `.gdignore`, which the engine never imports.
func _scan(dir_path: String, extensions: Array[String], seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	if dir.file_exists(".gdignore"):
		return

	dir.list_dir_begin()

	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)

		if dir.current_is_dir():
			if not entry.begins_with(".") and entry not in SCAN_EXCLUDE:
				_scan(path, extensions, seen)
		elif entry.get_extension() in extensions:
			seen[path] = true

		entry = dir.get_next()

	dir.list_dir_end()
