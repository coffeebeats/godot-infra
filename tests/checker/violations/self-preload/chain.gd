##
## A script preloading a script that preloads the scene whose root carries it. The
## scene's load reaches this script while it compiles.
##

extends Node

const Next := preload("chain_next.gd")
