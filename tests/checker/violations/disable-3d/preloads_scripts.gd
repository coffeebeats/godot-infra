##
## Preloads 3D-only scripts by each form of path: bare relative, `./`, `../`,
## `res://`, `uid://` and triple-quoted.
##

extends Node

const A := preload("only_3d/scene.gd")
const B := preload("./only_3d/scene.gd")
const C := preload("../disable-3d/layer_3d.gd")
const D := preload("res://disable-3d/layer_3d.gd")
const E := preload("uid://klnohlxtklqt")
const F := preload('''only_3d/scene.gd''')
