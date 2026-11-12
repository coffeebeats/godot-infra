##
## The project's loader, which `.gdcheckrc` allows to call the engine's loads.
##

extends Node


func request(path: String) -> void:
	ResourceLoader.load_threaded_request(path)


func load_now(path: String) -> Resource:
	return ResourceLoader.load(path)
