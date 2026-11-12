##
## A script preloading a script whose static initializer loads, by a path relative to
## `res://`, the scene whose root carries it.
##

extends Node

const Next := preload("chain_rel_next.gd")
