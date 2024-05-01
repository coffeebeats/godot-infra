extends SceneTree


func fail(msg: String):
	push_error(msg)
	quit(1)


func _initialize():
	var path_export_presets := OS.get_environment("EXPORT_PRESETS_PATH")
	if not path_export_presets:
		return fail("missing environment variable: 'EXPORT_PRESETS_PATH'")

	var preset := OS.get_environment("PRESET")
	if not preset:
		return fail("missing environment variable: 'PRESET'")

	var config := ConfigFile.new()

	var err := config.load("res://" + path_export_presets)
	if err != OK:
		return fail("failed to load file: " + path_export_presets)

	for section in config.get_sections():
		if section.ends_with("options"):
			continue

		if config.get_value(section, "name") != preset:
			continue

		var platform: String = config.get_value(section, "platform")
		if platform == "":
			return fail("missing required property: " + section + "/platform")

		match platform:
			"Linux/X11":
				print("linux")
				return
			"macOS":
				print("macos")
				return
			"Windows Desktop":
				print("windows")
				return

	fail("failed to find preset: " + preset)
