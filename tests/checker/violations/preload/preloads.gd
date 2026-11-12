##
## A script preloading what it may and what it must not. A script, a script-free
## resource and an imported texture pass. A scene with a script, a scene instancing it
## by uid, a custom resource and an imported scene each carry one, and a constant
## cannot be followed. A call in a comment or a string is not a call.
##

extends Node

const PATH := "res://preload/data.tres"

const Leaf := preload("leaf.gd")
const Data := preload("data.tres")
const Icon := preload("res://preload/icon.svg")
const Scene := preload("scene.tscn")
const Outer := preload("uid://dscir2zjhrbz")
const Custom := preload(
	"custom.tres"
)
const Model := preload("model.gltf")
const ByConstant := preload(PATH)
const Remarked := preload(
	"scene.tscn"  # a comment beside the literal does not hide it
)

# A binary scene or resource cannot be shown script-free without loading it, and a
# resource can carry a scene holding a built-in script.
const Binary := preload("binary.res")
const BinaryScene := preload("binary.scn")
const WrapsBuiltIn := preload("wraps_built_in.tres")

# A raw string, a triple-quoted one and one holding the other quote are each one
# literal.
const Raw := preload(r"scene.tscn")
const Triple := preload("""scene.tscn""")
const Apostrophe := preload("it's.tscn")

# const Commented := preload("scene.tscn")
var quoted := 'preload("scene.tscn")'
