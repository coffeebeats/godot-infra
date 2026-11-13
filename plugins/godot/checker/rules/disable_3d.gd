##
## plugins/godot/checker/rules/disable_3d.gd
##
## `disable-3d` reports a script that names a class an engine built with `disable_3d`
## does not register, or that loads a 3D-only script while it compiles. A 2D game's
## export template is often built that way, and the engine then fails to parse the
## script along with every script depending on it, while the editor, which keeps 3D,
## shows nothing.
##
## An engine class counts as 3D when its name holds `3D` or opens with one of
## `PREFIXES_3D`, or when it inherits from one of `ROOTS_3D`, unless `ALLOWED_3D` names
## it. A global class counts as 3D when its name holds `3D`, since the prefixes name
## engine modules, or when its script is 3D-only, meaning it matches one of the
## `scripts_3d` globs. A script loading a 3D-only script through `extends`,
## `preload` or a load in a static initializer is reported too, since each runs as the
## script compiles; any other `load()`, and a path held in a constant, runs later and is
## left alone.
##
## NOTE: The rule covers no file until `.gdcheckrc` sets `disallow_3d_classes`, since a
## 3D game names 3D classes everywhere. It skips the 3D-only scripts.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const GDScriptText := preload("../lib/gdscript_text.gd")
const ScriptClosure := preload("../lib/script_closure.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## ALLOWED_3D are the classes named with `3D` that an engine built with `disable_3d`
## still registers as of 4.7.2-stable, in the core, the `noise` and `visual_shader`
## modules, or outside the `_3D_DISABLED` blocks of `scene/register_scene_types.cpp`.
const ALLOWED_3D: Array[StringName] = [
	&"AStar3D",
	&"CompressedTexture3D",
	&"Geometry3D",
	&"ImageTexture3D",
	&"NoiseTexture3D",
	&"PlaceholderTexture3D",
	&"Texture3D",
	&"Texture3DRD",
	&"VisualShaderNodeSample3D",
	&"VisualShaderNodeTexture3D",
	&"VisualShaderNodeTexture3DParameter",
]

## MESSAGE_CLASS reports a 3D class, named by both placeholders.
const MESSAGE_CLASS := (
	"`%s` is absent from an engine built with `disable_3d`, which then fails to parse"
	+ " this script; name it only in a 3D-only script, or test a node with"
	+ ' `is_class(&"%s")`'
)

## MESSAGE_GLOBAL reports a project's 3D class, after its name and its script.
const MESSAGE_GLOBAL := (
	"`%s` is a 3D class, declared in %s, so an engine built with `disable_3d` fails to"
	+ " parse this script; name it only in a 3D-only script"
)

## MESSAGE_SCRIPT reports a 3D-only script, after how it loads and the path it loads.
const MESSAGE_SCRIPT := (
	"%s %s, a 3D-only script, so an engine built with `disable_3d` fails to parse"
	+ " this script too"
)

## NAME_PATTERN matches a name in code that is not a member or the tail of a longer
## name. Unlike `GDScriptText.NAME_BOUNDARY` it allows a `%` before a name, as in
## `5 %XRServer.x`, which takes a remainder; `_node_paths` rules out node path names.
const NAME_PATTERN := "(?<![\\w.$])[A-Za-z_]\\w*"

## NODE_PATH_PATTERN matches a node path written with `$` or `%`, such as `$A/B`,
## `$/root/A` or `%A/%B`, whose names `NAME_PATTERN` also matches and the check skips.
const NODE_PATH_PATTERN := "[$%]/?%?\\w*(?:/%?\\w+)*"

## OPERAND_END_PATTERN captures the word, closing bracket or quote a line of code ends
## in, past any blanks.
const OPERAND_END_PATTERN := "(\\w+|[)\\]}\\x22\\x27])[ \\t]*$"

## PREFIXES_3D begin the names of classes whose modules `disable_3d` leaves out; `gltf`
## and `fbx` build only without it, and XR, `openxr` included, goes with the
## `disable_xr` it implies (see the engine's `SConstruct` and `modules/*/config.py`).
const PREFIXES_3D: Array[String] = ["FBX", "GLTF", "OpenXR", "XR"]

## PREFIX_KEYWORDS are the keywords an expression may follow, so a `%` after one opens a
## node path rather than taking a remainder.
const PREFIX_KEYWORDS: Array[String] = [
	"and",
	"await",
	"elif",
	"else",
	"if",
	"in",
	"match",
	"not",
	"or",
	"return",
	"when",
	"while",
]

## ROOTS_3D are the classes `disable_3d` leaves out, each along with every class
## inheriting from it, whose families the name match misses in part; see the 4.7.2
## `_3D_DISABLED` blocks of the engine's `scene/register_scene_types.cpp`. A root an
## older engine lacks matches nothing.
const ROOTS_3D: Array[StringName] = [
	&"FogMaterial",
	&"ImporterMesh",
	&"LightmapGIData",
	&"Lightmapper",
	&"MeshLibrary",
	&"Node3D",
	&"PanoramaSkyMaterial",
	&"PhysicalSkyMaterial",
	&"PrimitiveMesh",
	&"ProceduralSkyMaterial",
	&"Skin",
	&"SkinReference",
	&"VoxelGIData",
	&"WorldEnvironment",
]

# -- INITIALIZATION ------------------------------------------------------------------ #

## _classes_3d maps the name of every 3D class to the script declaring it, or to an
## empty string for an engine class.
var _classes_3d: Dictionary = {}

var _name := RegEx.create_from_string(NAME_PATTERN)
var _node_path := RegEx.create_from_string(NODE_PATH_PATTERN)
var _operand_end := RegEx.create_from_string(OPERAND_END_PATTERN)

## _scripts_3d holds the globs of the scripts only a 3D game loads.
var _scripts_3d := PackedStringArray()

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	if _is_3d_only(file.path):
		return []

	var problems: Array[Problem] = []
	var text := file.text()
	var blanked := GDScriptText.blank(text)
	var lines := blanked.split("\n")
	var with_strings := GDScriptText.blank(text, true)
	var kept := with_strings.split("\n")

	for i in lines.size():
		var paths := _node_paths(kept[i])

		for found: RegExMatch in _name.search_all(lines[i]):
			var named := found.get_string()
			if named not in _classes_3d:
				continue

			if ScriptClosure.within(found.get_start(), paths):
				continue

			var declared: String = _classes_3d[named]
			var message := (
				MESSAGE_CLASS % [named, named]
				if declared.is_empty()
				else MESSAGE_GLOBAL % [named, declared]
			)
			problems.append(Problem.new(file.path, i + 1, name, message))

	for extended in ScriptClosure.extended_scripts(file.path, text):
		if _is_3d_only(extended.target):
			var message := MESSAGE_SCRIPT % ["extends", extended.target]
			problems.append(Problem.new(file.path, extended.line, name, message))

	for loaded in ScriptClosure.loads(text):
		var target := ScriptClosure.target_of(file.path, loaded)
		if not _is_3d_only(target):
			continue

		var how := "preloads" if loaded.name == "preload" else "loads while compiling"
		var message := MESSAGE_SCRIPT % [how, target]
		problems.append(Problem.new(file.path, loaded.line, name, message))

	problems.sort_custom(func(a: Problem, b: Problem) -> bool: return a.line < b.line)

	return problems


func configure(values: Dictionary) -> void:
	_scripts_3d.clear()

	for pattern: Variant in values["scripts_3d"]:
		if pattern is String:
			_scripts_3d.append(pattern)

	_classes_3d.clear()

	if not values["disallow_3d_classes"]:
		return

	extensions = ["gd"]

	for candidate in ClassDB.get_class_list():
		if _is_3d_name(candidate) or _inherits_3d(candidate):
			_classes_3d[String(candidate)] = ""

	# NOTE: A global class is tested by name and path only, since `ClassDB` raises an
	# error on a class it does not register.
	for entry in ProjectSettings.get_global_class_list():
		var global_name := String(entry["class"])
		if global_name.contains("3D") or _is_3d_only(entry["path"]):
			_classes_3d[global_name] = String(entry["path"])


func options() -> Dictionary:
	return {"disallow_3d_classes": false, "scripts_3d": []}


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"disable-3d"


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _inherits_3d reports whether an engine class inherits from one of `ROOTS_3D`, or is
## one, and `ALLOWED_3D` does not name it.
func _inherits_3d(candidate: StringName) -> bool:
	if candidate in ALLOWED_3D:
		return false

	for root in ROOTS_3D:
		if ClassDB.class_exists(root) and ClassDB.is_parent_class(candidate, root):
			return true

	return false


## _is_3d_name reports whether a class name holds `3D` or opens with one of
## `PREFIXES_3D`, and `ALLOWED_3D` does not name it.
##
## NOTE: The match errs broad, since a kept class it matches is reported at once and
## goes in `ALLOWED_3D`, while a dropped class it misses passes until an export breaks.
func _is_3d_name(candidate: String) -> bool:
	if StringName(candidate) in ALLOWED_3D:
		return false

	if candidate.contains("3D"):
		return true

	for prefix in PREFIXES_3D:
		if candidate.begins_with(prefix):
			return true

	return false


## _is_3d_only reports whether `path` names a script only a 3D game loads.
func _is_3d_only(path: String) -> bool:
	if not ScriptClosure.is_script(path):
		return false

	for pattern in _scripts_3d:
		if path.match(pattern):
			return true

	return false


## _node_paths returns each node path opening with `$` or `%` on `line`, a line of code
## whose strings are kept, as start and end offsets in a `Vector2i`.
##
## NOTE: A `%` after an operand is the modulo operator, as in `5 %count/XRServer.x`, so
## the search resumes past it.
func _node_paths(line: String) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var found := _node_path.search(line)

	while found != null:
		var start := found.get_start()

		if line[start] == "%" and _takes_remainder(line.substr(0, start)):
			found = _node_path.search(line, start + 1)
			continue

		spans.append(Vector2i(start, found.get_end()))
		found = _node_path.search(line, found.get_end())

	return spans


## _takes_remainder reports whether a `%` after `before`, the code ahead of it on its
## line, is the modulo operator, which follows an operand such as a name, a number, a
## string or a closing bracket. A keyword in `PREFIX_KEYWORDS` is no operand.
func _takes_remainder(before: String) -> bool:
	var found := _operand_end.search(before)
	if found == null:
		return false

	return found.get_string(1) not in PREFIX_KEYWORDS
