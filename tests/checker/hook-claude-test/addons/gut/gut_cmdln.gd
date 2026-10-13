##
## A stand-in for GUT's command line, printing and exporting what a failed run of GUT
## 9.7.1 does: each test's logging, the same script error once per test with its
## backtrace and its location indented as on Linux, and an error a test raised on
## purpose, then a JUnit file whose failures run past what a report keeps. The first
## failure echoes the options the hook passed.
##

extends SceneTree

const CASE := """
      <testcase name="%s" assertions="1" status="fail" classname="sum_test.gd" >
      <failure message="failed"><![CDATA[%s]]></failure></testcase>"""


func _initialize() -> void:
	var export := ""
	var options: Array[String] = []
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gjunit_xml_file="):
			export = arg.trim_prefix("-gjunit_xml_file=")
		elif arg.begins_with("-g"):
			options.append(arg)

	for i in 40:
		print("\u001b[36mDEBUG\u001b[0m sum: logged line %d" % i)

	for test in ["test_sum", "test_sum_negative", "test_sum_zero"]:
		printerr(
			"SCRIPT ERROR: Invalid call. Nonexistent function 'debug' in base 'Nil'."
		)
		printerr("          at: _log (res://sum.gd:9)")
		printerr("   GDScript backtrace (most recent call first):")
		printerr("       [0] _log (res://sum.gd:9)")
		printerr("       [1] %s (res://sum_test.gd:12)" % test)

	printerr("ERROR: a test raised this on purpose")
	printerr("   at: push_error (core/variant/variant_utility.cpp:1024)")

	var cases := CASE % ["test_sum", "ran with %s" % " ".join(options)]
	cases += (
		CASE
		% ["test_sum_negative", "Unexpected Errors:\n      [1] <engine-2>Invalid call."]
	)
	cases += CASE % ["test_sum_large", "[%s] expected to equal [0]" % "1, ".repeat(200)]
	for i in 120:
		var failure := (
			"[%d] expected to equal [%d]\n            at line %d" % [i, i + 1, i]
		)
		cases += CASE % ["test_sum_%d" % i, failure]

	var file := FileAccess.open(export, FileAccess.WRITE)
	file.store_string('<?xml version="1.0" encoding="UTF-8"?>\n')
	file.store_string('<testsuites name="GutTests" failures="123" tests="124" >\n')
	file.store_string('  <testsuite name="sum_test.gd" tests="124" failures="123" >')
	file.store_string(cases)
	file.store_string("\n  </testsuite>\n</testsuites>")
	file.close()

	quit(1)
