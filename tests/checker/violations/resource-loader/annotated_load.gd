##
## A script declaring its own `load` after an annotation on the same line, so a bare
## call to it is still not the engine's.
##

extends RefCounted

var _path := ""


@warning_ignore("shadowed_global_identifier") func load(path: String) -> void:
	_path = path


func reload() -> void:
	load(_path)
