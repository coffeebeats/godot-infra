##
## Extends 3D-only scripts, itself and in inner classes, and an inner class of one,
## each loading one on parse.
##

extends "only_3d/scene.gd"


class Overlay extends "only_3d/scene.gd":
	pass


class Inline extends "./only_3d/scene.gd": pass


class Wrapper:
	extends "res://disable-3d/only_3d/scene.gd"

	class Nested extends "../disable-3d/layer_3d.gd":
		pass


class Deep extends "only_3d/scene.gd".Inner:
	pass
