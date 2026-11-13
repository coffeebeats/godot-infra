##
## Loads a 3D-only script in a static initializer, which runs as the script compiles.
##

extends Node

static var _scene: Script = load("res://disable-3d/only_3d/scene.gd")
