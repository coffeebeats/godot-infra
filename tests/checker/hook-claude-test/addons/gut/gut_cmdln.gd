## Stands in for GUT's command line, printing what a failed run prints: each test's
## logging, the same engine error once per test with its backtrace, an error a test
## raised on purpose, then the run summary, in color where GUT colors it. The summary
## opens with the options the hook passed and runs past what a report keeps.
extends SceneTree


func _initialize() -> void:
	for i in 40:
		print("\u001b[36mDEBUG\u001b[0m sum: logged line %d" % i)

	for test in ["test_sum", "test_sum_negative", "test_sum_zero"]:
		printerr(
			"SCRIPT ERROR: Invalid call. Nonexistent function 'debug' in base 'Nil'."
		)
		printerr("   at: _log (res://sum.gd:9)")
		printerr("   GDScript backtrace (most recent call first):")
		printerr("       [0] _log (res://sum.gd:9)")
		printerr("       [1] %s (res://sum_test.gd:12)" % test)

	printerr("ERROR: a test raised this on purpose")
	printerr("   at: push_error (core/variant/variant_utility.cpp:1024)")

	print("==============================================")
	print("= Run Summary")
	print("==============================================")
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-g"):
			print("ran with ", arg)

	for test in ["test_sum", "test_sum_negative", "test_sum_zero"]:
		print("- %s" % test)
		for i in 30:
			print("    [Failed]:  Unexpected Errors: [%d]" % i)

	print("\u001b[31m---- 3 failing tests ----\u001b[0m")
	quit(1)
