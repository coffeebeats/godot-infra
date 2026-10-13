##
## A stand-in for GUT's command line that fails a test, which the hook leaves out of its
## report once the checker finds the test does not compile.
##

extends SceneTree


func _initialize() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gjunit_xml_file="):
			var path := arg.trim_prefix("-gjunit_xml_file=")
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string('<testsuites><testsuite name="sum_test.gd">')
			file.store_string('<testcase name="test_sum"><failure><![CDATA[a report')
			file.store_string(" the checker's makes redundant]]></failure></testcase>")
			file.store_string("</testsuite></testsuites>")
			file.close()

	quit(1)
