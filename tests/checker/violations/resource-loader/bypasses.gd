##
## A script loading around the project's loader: a threaded load named in code and in a
## string, and blocking loads, beside calls that only look like them.
##

extends Node

const Data := preload("res://preload/data.tres")


func _ready() -> void:
	ResourceLoader.load_threaded_request("res://preload/data.tres")
	var getter := Callable(ResourceLoader, "load_threaded_get")
	var loaded := load("res://preload/data.tres")
	var again := ResourceLoader.load("res://preload/data.tres")

	var config := ConfigFile.new()
	config.load("user://settings.cfg")

	# load("res://preload/data.tres") in a comment is not a call.
	assert(getter.is_valid() and loaded == again)
