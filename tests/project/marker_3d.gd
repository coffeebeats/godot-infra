##
## A file named `*_3d` is 3D-only, so `disable-3d` leaves the types it names alone.
##

extends Node


func _ready() -> void:
	var marker := Node3D.new()
	add_child(marker)
