##
## plugins/godot/checker/core/problem.gd
##
## Problem is one rule violation. It formats as `path:line: [rule] message` so a
## terminal and an editor can both link to it; `line` is 0 when the rule has no line to
## point at.
##

extends RefCounted

# -- CONFIGURATION ------------------------------------------------------------------- #

var path: String
var line: int
var rule: StringName
var message: String

# -- PUBLIC METHODS ------------------------------------------------------------------ #


## format renders the problem as a single reportable line.
func format() -> String:
	if line > 0:
		return "%s:%d: [%s] %s" % [path, line, rule, message]

	return "%s: [%s] %s" % [path, rule, message]


# -- ENGINE METHODS (OVERRIDES) ------------------------------------------------------ #


func _init(
	file_path: String, file_line: int, rule_name: StringName, text: String
) -> void:
	path = file_path
	line = file_line
	rule = rule_name
	message = text
