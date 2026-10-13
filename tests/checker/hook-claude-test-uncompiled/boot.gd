##
## An autoload that logs at boot, as a project's own do. The checker boots it too; the
## hook's report leaves out what it prints and keeps the warning it raises, as it keeps
## any the engine raises.
##

extends Node


func _ready() -> void:
	print("platform/module INFO Loaded kit module. module=storefront")
	push_warning("a warning a project raises at boot")
