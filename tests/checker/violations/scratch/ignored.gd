##
## A script `.gdcheckrc` excludes under `[all]`, so its bare call is neither reported nor
## counted as checked.
##

extends Node


func _ready() -> void:
	print("excluded")
