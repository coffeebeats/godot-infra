##
## A stand-in for GUT's command line given a test that does not compile. GUT skips the
## script, says nothing was run, and exits 0, while the engine reports the parse error
## on stderr.
##

extends SceneTree


func _initialize() -> void:
	print("---  GUT  ---")
	print(
		"[GUT WARNING]:  Ignoring script res://sum_test.gd because it does not extend GutTest"
	)
	print("[GUT ERROR]:  Nothing was run.")
	printerr(
		'SCRIPT ERROR: Parse Error: Identifier "Sum" not declared in the current scope.'
	)
	printerr("   at: GDScript::reload (res://sum_test.gd:7)")
	printerr("   GDScript backtrace (most recent call first):")
	printerr("       [0] _initialize (res://addons/gut/gut_cmdln.gd:12)")
	printerr(
		'ERROR: Failed to load script "res://sum_test.gd" with error "Parse error".'
	)
	printerr("   at: load (modules/gdscript/gdscript_resource_format.cpp:46)")
	quit(0)
