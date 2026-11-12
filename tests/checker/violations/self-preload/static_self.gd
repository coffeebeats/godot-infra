##
## A script loading, in a static initializer, a scene instancing one whose root
## carries it.
##

extends Node

static var scene: PackedScene = load("res://self-preload/static_outer.tscn")
