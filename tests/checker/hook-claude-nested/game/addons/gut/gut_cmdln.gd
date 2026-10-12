##
## A stand-in for GUT's command line that fails one test, echoing the tests the hook
## asked it to run.
##

extends SceneTree


func _initialize() -> void:
	var tests := ""
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest="):
			tests = arg

	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gjunit_xml_file="):
			var path := arg.trim_prefix("-gjunit_xml_file=")
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string('<testsuites><testsuite name="test/unit/test_sum.gd">')
			file.store_string('<testcase name="test_sum"><failure><![CDATA[ran with ')
			file.store_string(
				tests + "]]></failure></testcase></testsuite></testsuites>"
			)
			file.close()

	quit(1)
