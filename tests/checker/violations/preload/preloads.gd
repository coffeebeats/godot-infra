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

# const Commented := preload("scene.tscn")
var quoted := 'preload("scene.tscn")'
