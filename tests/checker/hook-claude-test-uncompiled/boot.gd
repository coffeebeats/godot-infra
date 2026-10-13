##
## An autoload that logs at boot, as a project's own do. The checker boots it too, and
## the hook's report leaves what it logs out.
##

extends Node


func _ready() -> void:
	print("platform/module INFO Loaded kit module. module=storefront")
	push_warning("a warning a project raises at boot")
