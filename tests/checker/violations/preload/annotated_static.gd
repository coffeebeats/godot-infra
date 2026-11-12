##
## A script whose static initializers follow an annotation on the same line. They still
## run while the script cache is locked.
##

extends Node

@warning_ignore("unused_private_class_variable") static var _data := load("res://preload/data.tres")


@warning_ignore("unused_variable") static func _static_init() -> void:
	var data := load("res://preload/data.tres")
