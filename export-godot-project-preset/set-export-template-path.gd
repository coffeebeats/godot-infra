extends SceneTree


func _initialize():
	var config := ConfigFile.new()

	var cfg := {}

	for arg in OS.get_cmdline_args().slice(2):
		var parts := arg.lstrip("-").split("=")
		_assert(len(parts) == 2, "invalid argument received: " + arg)

		cfg[parts[0]] = parts[1]

	var path_export_presets: String = cfg.get("export-presets-path", "")
	if _assert(path_export_presets != "", "missing required flag: 'export-presets-path'"):
		return

	var preset: String = cfg.get("preset", "")
	if _assert(preset != "", "missing required flag: 'preset'"):
		return

	var template_path: String = cfg.get("template-path", "")
	if _assert(template_path != "", "missing required flag: 'template-path'"):
		return

	var err := config.load("res://" + path_export_presets)
	if _assert(err == OK, "failed to load file: " + path_export_presets):
		return

	for section in config.get_sections():
		if section.ends_with("options"):
			continue

		if config.get_value(section, "name") != preset:
			continue

		config.set_value(section + ".options", "custom_template/release", template_path)
		config.set_value(section + ".options", "custom_template/debug", template_path)

		err = config.save("res://" + path_export_presets)
		if _assert(err == OK, "failed to save file: " + path_export_presets):
			return

		break


func _assert(expr: bool, message: String) -> int:
	if expr:
		return OK

	if message:
		push_error(message)

	quit(1)
	return FAILED
