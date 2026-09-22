##
## A script preloading one that names an unloaded extension's API by its uid, so the
## loading rules skip it too. Loaded anyway, it fails to compile, since the script it
## calls into did not parse.
##

extends Node

const User := preload("uid://dls4cxavked10")


func _ready() -> void:
	User.start()
