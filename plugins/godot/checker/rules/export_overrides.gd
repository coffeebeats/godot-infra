##
## plugins/godot/checker/rules/export_overrides.gd
##
## `export-overrides` reports export presets whose values differ from the ones
## `res://export_overrides.cfg` declares, and writes them. Each of its sections covers
## the presets its name globs, so one declaration serves every storefront, platform,
## component and architecture. A project without the file is left alone.
##
## NOTE: The editor caches presets at startup and writes them back when the export
## dialog opens or it exits, so run `--fix` with the editor closed.
##
## NOTE: The rule checks each glob against the files present, so a checkout without its
## submodules reports every addon glob as matching nothing.
##

extends "../core/rule.gd"

# -- DEPENDENCIES -------------------------------------------------------------------- #

const ExportDeclaration := preload("../lib/export_declaration.gd")

# -- INITIALIZATION ------------------------------------------------------------------ #

var _tree := PackedStringArray()
var _walked: bool = false

# -- PUBLIC METHODS (OVERRIDES) ------------------------------------------------------ #


func check(file: SourceFile) -> Array[Problem]:
	var problems: Array[Problem] = []

	if not FileAccess.file_exists(ExportDeclaration.OVERRIDES_PATH):
		return problems

	var overrides := ConfigFile.new()
	var err := overrides.load(ExportDeclaration.OVERRIDES_PATH)
	if err != OK:
		var message := "does not parse: %s" % error_string(err)
		problems.append(Problem.new(ExportDeclaration.OVERRIDES_PATH, 0, name, message))
		return problems

	var presets := ConfigFile.new()
	err = presets.load(file.path)
	if err != OK:
		var message := "does not parse: %s" % error_string(err)
		problems.append(Problem.new(file.path, 0, name, message))
		return problems

	var names := ExportDeclaration.preset_names(presets)

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
	var overrides := ExportDeclaration.read()
	if overrides == null:
		return false

	var text := file.text()
	var presets := ConfigFile.new()

	if presets.load(file.path) != OK or not _reproducible(text, presets):
		return false

	var names := ExportDeclaration.preset_names(presets)
	var changed := false

	for section: String in names:
		var declared := ExportDeclaration.assemble(names[section], overrides)

		for key: String in declared:
			var target_section := ExportDeclaration.target_section(section, key)
			var target_key := ExportDeclaration.target_key(key)

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


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init() -> void:
	name = &"export-overrides"
	extensions = ["cfg"]
	files = [ExportDeclaration.PRESETS_PATH]


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _check_globs reports each declared entry that names nothing in the project.
func _check_globs(overrides: ConfigFile) -> Array[Problem]:
	var problems: Array[Problem] = []
	var lines := ExportDeclaration.lines(ExportDeclaration.OVERRIDES_PATH)

	for section in overrides.get_sections():
		for key: String in ExportDeclaration.LIST_KEYS:
			if not overrides.has_section_key(section, key):
				continue

			var line := _line_of(lines, section, key)
			var value: Variant = overrides.get_value(section, key)

			if not Config.is_strings(value):
				var shape := "[%s] %s must be an array of strings" % [section, key]
				problems.append(Problem.new(ExportDeclaration.OVERRIDES_PATH, line, name, shape))
				continue

			for entry: String in value:
				var glob := ExportDeclaration.to_glob(entry)

				if glob == "":
					var missing := (
						"[%s] `%s` names no file or directory in the project"
						% [section, entry]
					)
					problems.append(
						Problem.new(ExportDeclaration.OVERRIDES_PATH, line, name, missing)
					)
					continue

				if not _matches_any(glob):
					var empty := "[%s] `%s` matches no file" % [section, entry]
					problems.append(Problem.new(ExportDeclaration.OVERRIDES_PATH, line, name, empty))

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
		var declared := ExportDeclaration.assemble(preset_name, overrides)

		for key: String in declared:
			var target_section := ExportDeclaration.target_section(section, key)
			var target_key := ExportDeclaration.target_key(key)

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
				% [preset_name, key, ExportDeclaration.OVERRIDES_PATH]
			)
			problems.append(Problem.new(file.path, line, name, message))

	return problems


## _check_sections reports each section whose glob names no preset.
func _check_sections(overrides: ConfigFile, names: Dictionary) -> Array[Problem]:
	var problems: Array[Problem] = []
	var lines := ExportDeclaration.lines(ExportDeclaration.OVERRIDES_PATH)

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
		problems.append(Problem.new(ExportDeclaration.OVERRIDES_PATH, line, name, message))

	return problems


## _coerced returns a declared value as the type the preset already holds, so an
## array written in the declaration stays the packed array the editor expects.
static func _coerced(current: Variant, declared: Variant) -> Variant:
	if current is PackedStringArray and declared is Array:
		return PackedStringArray(declared)

	return declared


## _files returns every file the exporter's walk reaches, without the scheme.
func _files() -> PackedStringArray:
	if not _walked:
		_walked = true
		ExportDeclaration.collect("res://", _tree)

	return _tree


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


## _matches_any reports whether any file matches a glob, trying it against both the
## bare path and the `res://` one, as the exporter does.
func _matches_any(glob: String) -> bool:
	for path in _files():
		if path.matchn(glob) or ("res://" + path).matchn(glob):
			return true

	return false


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


## _store writes text to a file, reporting whether it succeeded.
static func _store(path: String, text: String) -> bool:
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("%s: cannot write" % path)
		return false

	out.store_string(text)
	out.close()

	return true
