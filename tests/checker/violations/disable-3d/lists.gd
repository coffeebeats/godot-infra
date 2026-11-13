##
## Names every class the `disable-3d` rule's lists hold, as a type, so `compile` fails
## on an entry the engine lacks. The rule reports each root, while each allowed class
## passes.
##

extends Node

# -- ROOTS --

var root_fog_material: FogMaterial
var root_importer_mesh: ImporterMesh
var root_lightmap_gi_data: LightmapGIData
var root_lightmapper: Lightmapper
var root_mesh_library: MeshLibrary
var root_node3_d: Node3D
var root_panorama_sky_material: PanoramaSkyMaterial
var root_physical_sky_material: PhysicalSkyMaterial
var root_primitive_mesh: PrimitiveMesh
var root_procedural_sky_material: ProceduralSkyMaterial
var root_skin: Skin
var root_skin_reference: SkinReference
var root_voxel_gi_data: VoxelGIData
var root_world_environment: WorldEnvironment

# -- ALLOWED --

var allowed_a_star3_d: AStar3D
var allowed_compressed_texture3_d: CompressedTexture3D
var allowed_geometry3_d: Geometry3D
var allowed_image_texture3_d: ImageTexture3D
var allowed_noise_texture3_d: NoiseTexture3D
var allowed_placeholder_texture3_d: PlaceholderTexture3D
var allowed_texture3_d: Texture3D
var allowed_texture3_drd: Texture3DRD
var allowed_visual_shader_node_sample3_d: VisualShaderNodeSample3D
var allowed_visual_shader_node_texture3_d: VisualShaderNodeTexture3D
var allowed_visual_shader_node_texture3_d_parameter: VisualShaderNodeTexture3DParameter
