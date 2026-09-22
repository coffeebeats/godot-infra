##
## plugins/godot/checker/lib/resource_text.gd
##
## ResourceText holds what the checker knows about the text of a scene or resource.
##
## NOTE: This 'Object' should *not* be instanced and/or added to the 'SceneTree'. It is
## a "static" library that can be imported at compile-time using 'preload'.
##

extends Object

# -- DEFINITIONS --------------------------------------------------------------------- #

## EXT_RESOURCE_PREFIX opens a dependency header, an `[ext_resource]` line.
const EXT_RESOURCE_PREFIX := "[ext_resource "

## REFERENCE_PATTERN matches one quoted `res://` or `uid://` string literal.
const REFERENCE_PATTERN := '"((?:res|uid)://[^"]*)"'
