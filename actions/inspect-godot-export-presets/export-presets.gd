extends SceneTree

## USAGE maps each operation to the arguments it takes after its name.
const USAGE := {"get": "<PRESET> <KEY>", "set": "<PRESET> <KEY> <VALUE>"}


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

	var invalid := _validate(args)
	if invalid:
		_fail(invalid)
		return

	var op := args[0]
	var preset := args[1]
	var key := args[2]

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


## _validate returns what is wrong with the command-line arguments, or an empty string.
func _validate(args: PackedStringArray) -> String:
	if not args:
		return "missing required arguments: <OPERATION> <PRESET> <KEY> [VALUE]"

	if args[0] not in USAGE:
		return "unexpected operation; wanted 'get' or 'set', but was: %s" % args[0]

	var usage: String = USAGE[args[0]]
	if len(args) != usage.split(" ").size() + 1:
		return "unexpected input; wanted %s, but was: %s" % [usage, args.slice(1)]

	if not args[1]:
		return "missing argument: 'preset'"

	if not args[2]:
		return "missing argument: 'key'"

	return ""
