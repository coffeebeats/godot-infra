extends SceneTree


func _fail(msg: String) -> void:
	push_error(msg)
	quit(1)


func _initialize() -> void:
	var path_export_presets := OS.get_environment("EXPORT_PRESETS_PATH")
	if not path_export_presets:
		path_export_presets = "export_presets.cfg"

	var cfg := ConfigFile.new()

	var err := cfg.load("res://" + path_export_presets)
	if err != OK:
		_fail("failed to load file: " + path_export_presets)
		return

	var args := OS.get_cmdline_user_args()

	if not args:
		_fail("missing required arguments: <OPERATION> <PRESET> <KEY> [VALUE]")
		return

	var op := args[0]
	if op != "get" and op != "set":
		_fail("unexpected operation; wanted 'get' or 'set', but was: %s" % args[0])
		return

	if args[0] == "get" and len(args) != 3:
		_fail("unexpected input; wanted <PRESET> <KEY>, but was: %s" % args.slice(1))
		return

	if args[0] == "set" and len(args) != 4:
		_fail("unexpected input; wanted <PRESET> <KEY> <VALUE>, but was: %s" % args.slice(1))
		return

	var preset := args[1]
	if not preset:
		_fail("missing argument: 'preset'")
		return

	var key := args[2]
	if not key:
		_fail("missing argument: 'key'")
		return

	var index := _find_preset_index(cfg, preset)
	if index == -1:
		_fail("failed to find preset: " + preset)
		return

	var section := "preset." + str(index)
	if key.begins_with("options."):
		section += ".options"
		key = key.trim_prefix("options.")

	match op:
		"get":
			var value: String = cfg.get_value(section, key, "")
			if value:
				print(value)

		"set":
			var value := args[3]

			cfg.set_value(section, key, value)

			if cfg.save("res://" + path_export_presets) != OK:
				_fail("failed to save file: " + path_export_presets)
				return


func _find_preset_index(cfg: ConfigFile, preset: String) -> int:
	for section in cfg.get_sections():
		if section.ends_with("options"):
			continue

		if cfg.get_value(section, "name") != preset:
			continue

		return int(section.trim_prefix("preset."))

	return -1
