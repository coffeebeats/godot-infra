extends SceneTree


func fail(msg: String):
	push_error(msg)
	quit(1)


func _initialize():
	var path_export_presets := OS.get_environment("EXPORT_PRESETS_PATH")
	if not path_export_presets:
		path_export_presets = "export_presets.cfg"

	var cfg := ConfigFile.new()

	var err := cfg.load("res://" + path_export_presets)
	if err != OK:
		return fail("failed to load file: " + path_export_presets)

	var args := OS.get_cmdline_user_args()

	if not args:
		return fail("missing required arguments: <OPERATION> <PRESET> <KEY> [VALUE]")

	match args[0]:
		"get":
			var get_args := args.slice(1)
			if len(get_args) != 2:
				return fail(
					"unexpected input; wanted <PRESET> <KEY>, but was: " + " ".join(get_args)
				)

			return _handle_get(cfg, get_args[0], get_args[1])

		"set":
			var set_args := args.slice(1)
			if len(set_args) != 3:
				return fail(
					(
						"unexpected input; wanted <PRESET> <KEY> <VALUE>, but was: "
						+ " ".join(set_args)
					)
				)

			return _handle_set(cfg, set_args[0], set_args[1], set_args[2])


func _handle_get(cfg: ConfigFile, preset: String, key: String):
	if not preset:
		return fail("missing argument: 'preset'")
	if not key:
		return fail("missing argument: 'key'")

	var index := _find_preset_index(cfg, preset)
	if index == -1:
		return fail("failed to find preset: " + preset)

	var section := "preset." + str(index)
	if key.begins_with("options."):
		section += ".options"
		key = key.trim_prefix("options.")

	var value: String = cfg.get_value(section, key, "")
	if value:
		print(value)


func _handle_set(cfg: ConfigFile, preset: String, key: String, value: String):
	if not preset:
		return fail("missing argument: 'preset'")
	if not key:
		return fail("missing argument: 'key'")

	var index := _find_preset_index(cfg, preset)
	if index == -1:
		return fail("failed to find preset: " + preset)

	var section := "preset." + str(index)
	if key.begins_with("options."):
		section += ".options"
		key = key.trim_prefix(".options")

	cfg.set_value(section, key, value)


func _find_preset_index(cfg: ConfigFile, preset: String) -> int:
	for section in cfg.get_sections():
		if section.ends_with("options"):
			continue

		if cfg.get_value(section, "name") != preset:
			continue

		return int(section.trim_prefix("preset."))

	return -1
