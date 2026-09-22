##
## plugins/godot/checker/rules/export_ref.gd
##
## `export-ref` reports a file an export keeps whose dependency that same export drops.
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
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const ExportDeclaration := preload("../lib/export_declaration.gd")
const ResourceText := preload("../lib/resource_text.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## EXCLUDE_KEY is the declared key whose globs decide what an export leaves out.
const EXCLUDE_KEY := "exclude_filter"

## REFERRING_EXTENSIONS are the files carrying `[ext_resource]` headers.
const REFERRING_EXTENSIONS: Array[String] = ["tscn", "tres"]

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []

	var overrides := ExportDeclaration.read()
	if overrides == null:
		return problems

	# NOTE: `export-overrides` reports a presets file that does not parse.
	var presets := ConfigFile.new()
	if presets.load(file.path) != OK:
		return problems

	var tree := ExportDeclaration.tree()

	var dependencies := _dependencies(tree)
	if dependencies.is_empty():
		return problems

	var crossings := {}
	var names := ExportDeclaration.preset_names(presets)

	for section: String in names:
		var preset: String = names[section]
		var declared := ExportDeclaration.assemble(preset, overrides)
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

			var reported: PackedStringArray = crossings.get(index, PackedStringArray())
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


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"export-ref"
	extensions = ["cfg"]
	files = [ExportDeclaration.PRESETS_PATH]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _dependencies returns every `[ext_resource]` header in the project, as the file
## carrying it, the line it sits on and the file it loads.
func _dependencies(tree: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	for path in tree:
		if path.get_extension() not in REFERRING_EXTENSIONS:
			continue

		var lines := ExportDeclaration.lines("res://" + path)

		for i in lines.size():
			if not lines[i].begins_with(ResourceText.EXT_RESOURCE_PREFIX):
				continue

			var target := ResourceText.dependency(lines[i]).trim_prefix("res://")
			if target != "":
				out.append({&"file": path, &"line": i + 1, &"target": target})

	return out


## _excluded returns the files a set of globs drops, as a set, matching them against
## both the bare path and the `res://` one, as the exporter does.
static func _excluded(tree: PackedStringArray, globs: PackedStringArray) -> Dictionary:
	var out := {}

	for path in tree:
		for glob in globs:
			if path.matchn(glob) or ("res://" + path).matchn(glob):
				out[path] = true
				break

	return out
