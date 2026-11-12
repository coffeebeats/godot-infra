##
## A script whose static initializer loads, by a path relative to `res://`, the scene
## whose root carries it.
##

extends Node

static var scene: PackedScene = load("self-preload/rel_self.tscn")
