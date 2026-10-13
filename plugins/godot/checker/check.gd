##
## plugins/godot/checker/check.gd
##
## Checks project files for problems a normal boot or import does not surface, and
## repairs the ones it can. The `godot` plugin's edit hook runs it on each edited file,
## and `check-project.yaml` runs it over the whole project.
##
## NOTE: Every file here preloads others by relative path and declares no `class_name`.
## An error in any of them fails the run, whether it stops the run or a rule's check.
##
## Usage, from the project root:
##   godot --headless -s <checker>                       # every rule, every file
##   godot --headless -s <checker> -- a.gd b.tscn        # only the given files
##   godot --headless -s <checker> -- --fix a.tscn       # repair, then re-check
##   godot --headless -s <checker> -- --report=out.json  # also write it as JSON
##   godot --headless -s <checker> -- --list             # print the rule registry
##
## Reads `res://.gdcheckrc`, when present, for files to exclude and for the GDExtensions
## that may not load; see `core/config.gd`.
##
## The report holds what the summary prints: the files `checked`, how many `.gdcheckrc`
## `excluded`, the `problems` found, the files `fixed`, the files whose loading rules
## were `skipped`, and the GDExtensions `unloaded`. A problem holds its `path`, `line`
## (0 for none), `rule` and `message`.
##
## Exits 1 when a problem is found, a repair applied or the checker fails, and 0
## otherwise.
##

extends SceneTree

# -- DEPENDENCIES -------------------------------------------------------------------- #

const Config := preload("core/config.gd")
const Discovery := preload("core/discovery.gd")
const ErrorLog := preload("core/error_log.gd")
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

## REPORT opens the argument naming the file the report is written to.
const REPORT := "--report="

# -- INITIALIZATION ------------------------------------------------------------------ #

## _checker_dir is the directory holding this checker, which an error its own scripts
## raise is located in.
var _checker_dir: String = ""

## _finished is whether the run reached an exit of its own.
var _finished: bool = false

## _log records every error the engine raises during the run.
var _log := ErrorLog.new()

# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _initialize() -> void:
	# NOTE: An error in a script cuts this method short before it can quit, and the
	# engine then runs until stopped, so the run ends on the next frame unless it
	# finished.
	_stopped.call_deferred()

	_checker_dir = (get_script() as Script).resource_path.get_base_dir()
	OS.add_logger(_log)

	var args := OS.get_cmdline_user_args()
	var rules := _registry()

	var sections := {}
	for rule in rules:
		sections[rule.name] = rule.options()

	var config := Config.parse(sections)

	if not config.problems.is_empty():
		config.problems.append_array(_failures(0))

		for problem in config.problems:
			print("  ", problem.format())

		print("checked 0 file(s); fix %s first" % Config.PATH)
		_report(args, config.problems)
		_finish(1)
		return

	# A rule the project configures learns it here rather than in `_registry`, which
	# runs first because parsing the config needs the options each rule declares.
	for rule in rules:
		rule.configure(config.options(rule.name))

	if args.has("--list"):
		_list(rules)
		_finish(0)
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
			Discovery.scan(path, Discovery.file_extensions(rules), expanded)

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
	var fixed := {}
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

			var raised := _log.errors.size()
			var found := rule.check(file)

			if not found.is_empty() and should_fix and rule.fixable():
				if rule.fix(file):
					fixed[path] = true
					file.reset()
					found = rule.check(file)

			problems.append_array(found)
			problems.append_array(_failures(raised, path, rule.name))

		if held:
			skipped.append(path)

		file.release()

	problems.append_array(_failures(0))

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

	if not fixed.is_empty():
		print(
			(
				"fixed %d file(s); run `godot --import --headless` so they resolve"
				% fixed.size()
			)
		)

	_report(
		args,
		problems,
		{
			"checked": paths,
			"excluded": excluded,
			"fixed": fixed.keys(),
			"skipped": skipped,
			"unloaded": gate.missing.keys(),
		}
	)

	# NOTE: gdenv's `godot` shim reports every failing exit as 1 on Windows, so a
	# problem found and a repair applied both exit 1.
	_finish(1 if not problems.is_empty() or not fixed.is_empty() else 0)


# -- PRIVATE METHODS ----------------------------------------------------------------- #


## _failures returns a problem for each error the checker's own scripts raised from the
## log's since-th error on that no problem reports yet. An error raised while rule
## checked path is reported on path, and any other where the checker raised it.
func _failures(
	since: int, path: String = "", rule: StringName = &"checker"
) -> Array[Problem]:
	var failures: Array[Problem] = []

	for error in _log.errors.slice(since):
		if (
			error.get("reported", false)
			or not error.path.begins_with(_checker_dir + "/")
		):
			continue

		error.reported = true
		var at := "%s:%d" % [error.path.trim_prefix(_checker_dir + "/"), error.line]

		if path.is_empty():
			failures.append(Problem.new(at, 0, rule, error.message))
		else:
			var message := "the checker failed at %s: %s" % [at, error.message]
			failures.append(Problem.new(path, 0, rule, message))

	return failures


## _finish ends the run with code.
func _finish(code: int) -> void:
	_finished = true
	OS.remove_logger(_log)
	quit(code)


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


## _report writes problems and the rest of a run's findings as JSON to the file a
## `--report=<path>` argument names, if one does. A finding the run never reached is
## written empty.
func _report(
	args: PackedStringArray, problems: Array[Problem], findings: Dictionary = {}
) -> void:
	var path := ""
	for arg in args:
		if arg.begins_with(REPORT):
			path = arg.trim_prefix(REPORT)

	if path.is_empty():
		return

	var report := {
		"checked": [],
		"excluded": 0,
		"problems": problems.map(func(problem: Problem): return problem.to_dict()),
		"fixed": [],
		"skipped": [],
		"unloaded": [],
	}
	report.merge(findings, true)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var error := error_string(FileAccess.get_open_error())
		printerr("could not write the report to %s: %s" % [path, error])
		return

	file.store_string(JSON.stringify(report, "  ", false))
	file.close()


## _registry returns a new instance of every rule in `RULES`, in order.
func _registry() -> Array[Rule]:
	var rules: Array[Rule] = []

	for script in RULES:
		rules.append(script.new())

	return rules


## _stopped ends the run with code 1 unless it finished, which an error in a script
## prevents.
func _stopped() -> void:
	if not _finished:
		print("the checker stopped on an error before it finished")
		quit(1)
