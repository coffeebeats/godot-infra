##
## A script naming the API of an extension that did not load. The loading rules skip it
## rather than report it.
##

extends Node


func _ready() -> void:
	AbsentApi.start()
