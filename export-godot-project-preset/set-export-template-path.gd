extends SceneTree


func fail(msg: String):
	push_error(msg)
	quit(1)


func _initialize():
	var config := ConfigFile.new()

	var path_export_presets := OS.get_environment("EXPORT_PRESETS_PATH")
	if not path_export_presets:
		return fail("missing environment variable: 'EXPORT_PRESETS_PATH'")

	var preset := OS.get_environment("PRESET")
	if not preset:
		return fail("missing environment variable: 'PRESET'")

	var path_template := OS.get_environment("TEMPLATE_PATH")
	if not path_template:
		return fail("missing environment variable: 'TEMPLATE_PATH'")

	var err := config.load("res://" + path_export_presets)
	if err != OK:
		return fail("failed to load file: " + path_export_presets)

	for section in config.get_sections():
		if section.ends_with("options"):
			continue

		if config.get_value(section, "name") != preset:
			continue

		config.set_value(section + ".options", "custom_template/release", path_template)
		config.set_value(section + ".options", "custom_template/debug", path_template)

		err = config.save("res://" + path_export_presets)
		if err != OK:
			return fail("failed to save file: " + path_export_presets)

		break
