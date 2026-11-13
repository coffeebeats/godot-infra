##
## A 3D-only script, by its directory, which the `disable-3d` rule skips. Its class
## counts as 3D, since only a 3D game declares it.
##

class_name FixtureDepthScene
extends Node

## root names a 3D class, which a 3D-only script may.
var root: Node3D = null


## Inner is a class inside this script, which `extends_script.gd` extends.
class Inner:
	extends Node
