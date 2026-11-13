##
## A file the `disable-3d` rule must report nothing in. It names 3D classes only in
## comments, strings and node paths, and 3D-only scripts only where nothing loads them
## as this script compiles, and a global class opening with an engine module's prefix.
## Node3D in a doc comment.
##
## NOTE: A report against this file shows up as a new line in `expected.txt`, while
## `names_classes.gd` and `preloads_scripts.gd` beside it prove the rule still reports
## real uses.
##

extends Node

# preload("only_3d/scene.gd")

## See "res://disable-3d/layer_3d.gd".
const LAYER_PATH := "res://disable-3d/layer_3d.gd"

const BANNER := """
Node3D in a multi-line string, and a "# not a comment".
	extends "only_3d/scene.gd"
class Hidden extends "only_3d/scene.gd": pass
"""

const FLAT := preload("flat_scene.gd")
const SCENE := preload("only_3d/scene.tscn")

var data := {"Camera3D": 1}
var scanner: XRayScanner = null


func describe(node: Node) -> Array:
	var is_3d := node.is_class(&"Node3D")  # Node3D in a comment
	var paths := [
		$Camera3D,
		%Camera3D,
		$A/Camera3D,
		$/root/Camera3D,
		$A/%Camera3D,
		%A/Camera3D,
		$A/B/Camera3D,
		$A/Camera3D.name,
		[%A/Camera3D],
	]
	var named := ^"only_3d/scene"
	var flat := FixtureFlatScene.new()
	return [is_3d, paths, named, flat, data.Camera3D, BANNER, LAYER_PATH, FLAT, SCENE]


func load_later() -> Script:
	return load("res://disable-3d/only_3d/scene.gd")


func unique(flag: bool) -> Node:
	if not %A/Camera3D.visible:
		return %A/Camera3D
	return $A if flag else %A/Camera3D
