##
## A script whose static initializer loads, by a path relative to `res://`, a scene
## whose root carries the script preloading this one.
##

extends RefCounted

static var scene: PackedScene = load("self-preload/chain_rel.tscn")
