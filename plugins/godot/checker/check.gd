##
## plugins/godot/checker/check.gd
##
## Checks project files for problems a normal boot or import does not surface, and
## repairs the ones it can. The `godot` plugin's edit hook runs it on each edited file,
## and `check-project.yaml` runs it over the whole project.
##
## NOTE: The checker runs from outside the project, so its files preload one another by
## relative path and declare no `class_name`. A preloaded file that fails to compile
## hangs the engine or exits 0 having checked nothing, so run
## `scripts/test_project_checker.py` after changing any of them.
##
## Usage, from the project root:
##   godot --headless -s <checker>                       # every rule, every file
##   godot --headless -s <checker> -- a.gd b.tscn        # only the given files
##   godot --headless -s <checker> -- --fix a.tscn       # repair, then re-check
##   godot --headless -s <checker> -- --list             # print the rule registry
##
## Reads `res://.gdcheckrc`, when present, for files to exclude and for the GDExtensions
## that may not load; see `core/config.gd`.
##
## Exits 1 when a problem is found or a repair applied, and 0 otherwise.
##

extends SceneTree

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Config := preload("core/config.gd")
const Discovery := preload("core/discovery.gd")
const ExtensionGate := preload("core/extension_gate.gd")
const Problem := preload("core/problem.gd")
const Rule := preload("core/rule.gd")
const SourceFile := preload("core/source_file.gd")

# -- DEFINITIONS --------------------------------------------------------------------- #

## RULES holds every rule in the order they run; discovery, dispatch and `--list` all
## follow from it. `uid` runs ahead of the rules that load a scene, so `--fix` repairs
## the header first.
const RULES: Array[Script] = [
	preload("rules/compile.gd"),
	preload("rules/logging.gd"),
	preload("rules/uid.gd"),
	preload("rules/path_ref.gd"),
	preload("rules/load.gd"),
	preload("rules/script_order.gd"),
	preload("rules/nodepath.gd"),
	preload("rules/export_overrides.gd"),
	preload("rules/export_ref.gd"),
]

# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rules := _registry()

	var sections := {}
	for rule in rules:
		sections[rule.name] = rule.options()

	var config := Config.parse(sections)

	if not config.problems.is_empty():
		for problem in config.problems:
			print("  ", problem.format())

		print("checked 0 file(s); fix %s first" % Config.PATH)
		quit(1)
		return

	# A rule the project configures learns it here rather than in `_registry`, which runs
	# first because parsing the config needs the options each rule declares.
	for rule in rules:
		rule.configure(config.options(rule.name))

	if args.has("--list"):
		_list(rules)
		quit(0)
		return

	var should_fix := args.has("--fix")
	var gate := ExtensionGate.new(config)

	var paths: Array[String] = []
	var expanded := {}

	for arg in args:
		if arg.begins_with("--"):
			continue

		var path := Discovery.localize(arg)

		# A directory argument is expanded rather than checked, since a path no rule
		# applies to would otherwise be reported as clean.
		if DirAccess.dir_exists_absolute(path):
			Discovery.scan(path, Discovery.extensions(rules), expanded)

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
		paths = Discovery.discover(rules)

	# NOTE: A file excluded from every rule is dropped before checking, whether it was
	# discovered or named, so it is neither fixed nor counted.
	var excluded := 0
	var kept: Array[String] = []

	for path in paths:
		if config.excluded(Config.ALL, path):
			excluded += 1
		else:
			kept.append(path)

	paths = kept

	var problems: Array[Problem] = []
	var fixed := 0
	var skipped: Array[String] = []

	for path in paths:
		var file := SourceFile.new(path)
		var unloadable := gate.blocks(path)
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
		print("excluded %d file(s) through %s" % [excluded, Config.PATH])

	var unloaded := ", ".join(PackedStringArray(gate.missing.keys()))

	if not skipped.is_empty():
		print(
			(
				"skipped the loading rules for %d file(s): %s not loaded"
				% [skipped.size(), unloaded]
			)
		)

		for path in skipped:
			print("  ", path)

	if not problems.is_empty() and not gate.missing.is_empty():
		print(
			(
				(
					"note: %s is not loaded here; if a script above uses a name it"
					% unloaded
				)
				+ " defines, add the name under `extensions` in %s" % Config.PATH
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


## _list prints each rule with the files it covers and whether it can fix them.
func _list(rules: Array[Rule]) -> void:
	for rule in rules:
		var roots := Discovery.SCAN_ROOT if rule.roots.is_empty() else rule.roots
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


## _registry returns a new instance of every rule in `RULES`, in order.
func _registry() -> Array[Rule]:
	var rules: Array[Rule] = []

	for script in RULES:
		rules.append(script.new())

	return rules
