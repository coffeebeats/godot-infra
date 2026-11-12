##
## A script whose static initializer loads a scene whose root carries the script
## preloading this one.
##

extends RefCounted

static var scene: PackedScene = load("res://self-preload/chain_static.tscn")
