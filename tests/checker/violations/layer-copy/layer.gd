## Stands in for an action set layer, which the rule knows only by its properties.
extends Resource

@export var name: StringName
@export var parent: Resource
@export var actions_digital: Array[StringName] = []
@export var actions_analog_1d: Array[StringName] = []
@export var actions_analog_2d: Array[StringName] = []
