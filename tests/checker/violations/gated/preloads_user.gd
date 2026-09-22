##
## A script preloading one that names an unloaded extension's API by its path, so the
## loading rules skip it too.
##

extends Node

const User := preload("uses_absent.gd")
