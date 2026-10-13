##
## A script that does not compile, which `compile` reports once for each line the engine
## raised an error at, though it raises two at the last.
##

extends Node


func _ready() -> void:
	undeclared_function()
	undeclared_function(undeclared_function())
