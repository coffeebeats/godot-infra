##
## A file a `disable_3d` template must load, carrying every name `disable-3d` has to let
## through. Those are the Variant types the flag keeps, a constant ending in `_3D`, and
## `Node3D` written in prose and in a string, neither of which the parser resolves.
##

extends Node

const OFFSET_3D := Vector3(0, 1, 0)


func _ready() -> void:
	var placement := Transform3D.IDENTITY.translated(OFFSET_3D)
	print("would be a Node3D at ", placement.origin)
