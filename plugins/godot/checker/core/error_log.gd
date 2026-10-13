##
## plugins/godot/checker/core/error_log.gd
##
## ErrorLog records the errors the engine raises while `OS.add_logger` registers it,
## which `SourceFile` does around each load.
##
## NOTE: The engine calls a logger from whichever thread raised the error.
##

extends Logger

# -- INITIALIZATION ------------------------------------------------------------------ #

## errors holds each error in the order raised, shaped as `SourceFile.errors` says.
var errors: Array[Dictionary] = []

var _mutex := Mutex.new()

# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _log_error(
	_function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	var error := {
		"path": "",
		"line": 0,
		"message": rationale if rationale else code,
		"warning": error_type == ERROR_TYPE_WARNING,
	}

	# An error a script did not raise names a line of the engine's own source.
	if error_type == ERROR_TYPE_SCRIPT and file.begins_with("res://"):
		error.path = file
		error.line = line

	_mutex.lock()
	errors.append(error)
	_mutex.unlock()
