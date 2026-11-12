##
## A script loading in its static initializers, which run while the script cache is
## locked, beside loads that run later and pass.
##

extends Node

static var data: Resource = load("res://preload/data.tres")

static var listed: Array[Resource] = [
	ResourceLoader.load("res://preload/data.tres"),
]

static var handlers := {
	"inline": func(): return load("res://preload/data.tres"),
	"named": _load_data,
}

var later: Resource = load("res://preload/data.tres")


static func _static_init() -> void:
	var status := ResourceLoader.load_threaded_get_status("res://preload/data.tres")
	assert(status != ResourceLoader.THREAD_LOAD_LOADED)


static func reload() -> void:
	data = load("res://preload/data.tres")


static func _load_data() -> Resource:
	return load("res://preload/data.tres")
