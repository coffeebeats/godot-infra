##
## A script declaring its own `load`, so a bare call to it is not the engine's. A
## threaded load is still reported.
##

extends RefCounted

var _path := ""


func load(path: String) -> void:
	_path = path


func reload() -> void:
	load(_path)


func status() -> int:
	return ResourceLoader.load_threaded_get_status(_path)
