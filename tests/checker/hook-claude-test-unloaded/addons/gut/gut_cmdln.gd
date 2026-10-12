##
## A stand-in for GUT's command line given a test that does not extend `GutTest`, as GUT
## 9.7.1 runs it: GUT skips the script, says nothing was run, exports no suite for it,
## and exits 0.
##

extends SceneTree


func _initialize() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gjunit_xml_file="):
			var path := arg.trim_prefix("-gjunit_xml_file=")
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string('<?xml version="1.0" encoding="UTF-8"?>\n')
			file.store_string('<testsuites name="GutTests" failures="0" tests="0" >\n')
			file.store_string("  </testsuites>")
			file.close()

	print("---  GUT  ---")
	print(
		(
			"\u001b[33m[GUT WARNING]:  \u001b[0mIgnoring script res://sum_test.gd"
			+ " because it does not extend GutTest"
		)
	)
	print("[GUT ERROR]:  Nothing was run.")
	quit(0)
