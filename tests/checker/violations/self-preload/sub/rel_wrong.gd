##
## A script whose static initializer loads a script-free scene by a path relative to
## `res://`. The same path relative to this folder names a scene carrying this script.
##

extends Node

static var scene: PackedScene = load("self-preload/rel_target.tscn")
