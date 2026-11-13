##
## Names a 3D class of each kind the `disable-3d` rule reports: one named with `3D`,
## one inheriting from a root, an XR and a glTF class, and global classes 3D by name
## and by the directory their script sits in.
##

extends Node


func describe(child: Node) -> Array:
	if child is Node3D:
		return []

	var camera: Camera3D = null
	var mesh := BoxMesh.new()
	var doc := GLTFDocument.new()
	var tracking := XRServer.world_scale
	var environment: WorldEnvironment = null
	var layer := FixtureLayer3D.new()
	var depth: FixtureDepthScene = null
	var count := child.get_child_count()
	var share := 1.0/XRServer.world_scale
	var interfaces := 5 %count/XRServer.get_interface_count()
	return [camera, mesh, doc, tracking, environment, layer, depth, share, interfaces]


func remainders(count: int) -> Array:
	var modulo := 5 %XRServer.get_interface_count()
	var wrapped := (count) %Camera3D.PROJECTION_ORTHOGONAL
	return [modulo, wrapped]
