##
## A script naming the API of an extension that did not load. The loading rules skip it
## rather than report it.
##

extends Node


## start takes the extension's own type, as a wrapper around a storefront's API would.
static func start(api: AbsentApi = null) -> void:
	api.start()


## Inner is a class inside this script, which `extends_inner.gd` extends.
class Inner:
	extends Node
