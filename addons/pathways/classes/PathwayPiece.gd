tool
extends Spatial
class_name PathwayPiece, "res://addons/pathways/icons/pathway-piece.png"

enum PieceType {
	STRAIGHT,
	INTERSECTION,
}
enum IntersectionType {
	Y,
	T,
	X,
}

# Public properties
export var mesh_node : NodePath setget set_mesh_node
export(PieceType) var piece_type : int = PieceType.STRAIGHT setget set_piece_type

# Dynamically defined properties
## Intersection properties
var intersection_type : int = IntersectionType.Y setget set_intersection_type
var intersection_branch_length : float = 1.0 setget set_intersection_branch_length
var intersection_branch_radius : float = 1.0 setget set_intersection_branch_radius
var intersection_origin_point : Vector2 = Vector2.ZERO setget set_intersection_origin

## Mesh adjustments
var mesh_axis : String = "X" setget set_mesh_axis
var mesh_up_axis : String = "Y" setget set_mesh_up_axis
var mesh_rotation_degrees : float  = 0.0 setget set_mesh_rotation

# Private properties
var _mesh_reference : ArrayMesh
var _intersection_branches : Array = []

# Helper references
const ExportUtils := preload("../utils/ExportUtils.gd")

signal mesh_changed()

func _ready() -> void:
	_update_mesh()

func _get_property_list() -> Array:
	var properties := []
	
	var intersection_usage := PROPERTY_USAGE_NOEDITOR
	if (piece_type == PieceType.INTERSECTION):
		intersection_usage = PROPERTY_USAGE_DEFAULT
	
	# Intersection piece properties.
	properties.append({
		"name": "Intersection",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": "intersection_",
	})
	properties.append({
		"name": "intersection_type",
		"type": TYPE_INT,
		"usage": intersection_usage,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ExportUtils.get_enum_export_hint(IntersectionType),
	})
	properties.append({
		"name": "intersection_branch_length",
		"type": TYPE_REAL,
		"usage": intersection_usage,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.0,5.0,0.01,or_greater",
	})
	properties.append({
		"name": "intersection_branch_radius",
		"type": TYPE_REAL,
		"usage": intersection_usage,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.0,5.0,0.01,or_greater",
	})
	properties.append({
		"name": "intersection_origin_point",
		"type": TYPE_VECTOR2,
		"usage": intersection_usage,
	})
	
	# Mesh adjustment properties to align the mesh for further use.
	properties.append({
		"name": "Mesh Adjustments",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": "mesh_",
	})
	properties.append({
		"name": "mesh_axis",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "X,Y,Z",
	})
	properties.append({
		"name": "mesh_up_axis",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "X,Y,Z,-X,-Y,-Z",
	})
	properties.append({
		"name": "mesh_rotation_degrees",
		"type": TYPE_REAL,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "-180,180,0.1",
	})
	
	return properties

# Properties
func set_mesh_node(value: NodePath) -> void:
	mesh_node = value
	_update_mesh()
	emit_signal("mesh_changed")

func set_piece_type(value: int) -> void:
	piece_type = value
	_update_mesh()
	emit_signal("mesh_changed")
	property_list_changed_notify()

func set_intersection_type(value: int) -> void:
	intersection_type = value
	_update_branches()
	_update_mesh()
	emit_signal("mesh_changed")

func set_intersection_branch_length(value: float) -> void:
	intersection_branch_length = value
	_update_branches()
	_update_mesh()
	emit_signal("mesh_changed")

func set_intersection_branch_radius(value: float) -> void:
	intersection_branch_radius = value
	_update_branches()
	_update_mesh()
	emit_signal("mesh_changed")

func set_intersection_origin(value: Vector2) -> void:
	intersection_origin_point = value
	_update_mesh()
	emit_signal("mesh_changed")

func set_mesh_axis(value: String) -> void:
	mesh_axis = value
	_update_mesh()
	emit_signal("mesh_changed")

func set_mesh_up_axis(value: String) -> void:
	mesh_up_axis = value
	_update_mesh()
	emit_signal("mesh_changed")

func set_mesh_rotation(value: float) -> void:
	mesh_rotation_degrees = value
	_update_mesh()
	emit_signal("mesh_changed")

# Public methods
func has_mesh() -> bool:
	return (_mesh_reference != null)

func get_mesh() -> ArrayMesh:
	return _mesh_reference

func get_intersection_branches() -> Array:
	return _intersection_branches

# Helpers
func _update_branches() -> void:
	_intersection_branches = []
	
	# Follow the clockwise direction.
	
	if (intersection_type == IntersectionType.T):
		_intersection_branches.append(Vector2(0, -intersection_branch_length))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(90)))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(-90)))
	
	elif (intersection_type == IntersectionType.Y):
		_intersection_branches.append(Vector2(0, -intersection_branch_length))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(120)))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(-120)))
	
	elif (intersection_type == IntersectionType.X):
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(45)))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(135)))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(-135)))
		_intersection_branches.append(Vector2(0, -intersection_branch_length).rotated(deg2rad(-45)))

func _update_mesh() -> void:
	if (!is_inside_tree()):
		return
	
	_mesh_reference = null
	if (mesh_node.is_empty()):
		return
	
	var mesh_instance = get_node_or_null(mesh_node) as MeshInstance
	if (!mesh_instance || !is_instance_valid(mesh_instance)):
		return
	
	# Prepare the input mesh for easier deformations later.
	var array_mesh: ArrayMesh
	
	# PrimitiveMesh is not supported, so convert it.
	if mesh_instance.mesh is PrimitiveMesh:
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.get_mesh_arrays())
	else:
		array_mesh = mesh_instance.mesh
	
	# Using the piece type pre-transform the mesh to align with the Z axis.
	if (piece_type == PieceType.STRAIGHT):
		array_mesh = _pretransform_straight(array_mesh)
	elif (piece_type == PieceType.INTERSECTION):
		array_mesh = _pretransform_intersection(array_mesh)
	
	_mesh_reference = array_mesh

func _pretransform_straight(input_mesh: ArrayMesh) -> ArrayMesh:
	var mesh_data_tool = MeshDataTool.new()
	mesh_data_tool.create_from_surface(input_mesh, 0)
	
	# Make the mesh properly oriented.
	var pre_transform = _get_pre_transform()
	for i in mesh_data_tool.get_vertex_count():
		var position = mesh_data_tool.get_vertex(i)
		var normal = mesh_data_tool.get_vertex_normal(i)
		
		position = pre_transform.xform(position)
		normal = pre_transform.xform(normal)
		mesh_data_tool.set_vertex(i, position)
		mesh_data_tool.set_vertex_normal(i, normal)
	
	# Save the new mesh.
	var output_mesh := ArrayMesh.new()
	var arrays = Array()
	arrays.resize(ArrayMesh.ARRAY_MAX)
	mesh_data_tool.commit_to_surface(output_mesh)
	
	return output_mesh

func _pretransform_intersection(input_mesh: ArrayMesh) -> ArrayMesh:
	var mesh_data_tool = MeshDataTool.new()
	mesh_data_tool.create_from_surface(input_mesh, 0)
	
	# Make the mesh properly oriented.
	var pre_transform = _get_pre_transform()
	for i in mesh_data_tool.get_vertex_count():
		var position = mesh_data_tool.get_vertex(i)
		var normal = mesh_data_tool.get_vertex_normal(i)
		
		position = pre_transform.xform(position)
		normal = pre_transform.xform(normal)
		mesh_data_tool.set_vertex(i, position)
		mesh_data_tool.set_vertex_normal(i, normal)
	
	# Calculate weights of every intersection branch (represented by a vertex bone).
	for i in mesh_data_tool.get_vertex_count():
		var position = mesh_data_tool.get_vertex(i)
		var projection_position = Vector2(position.x, position.z)
		
		var bones := PoolIntArray()
		var weights := PoolRealArray()
		
		for b in _intersection_branches.size():
			var branch_handle = _intersection_branches[b]
			var branch_distance = projection_position.distance_to(branch_handle)
			if (branch_distance <= intersection_branch_radius):
				bones.append(b + 1)
				weights.append(_get_branch_weight(projection_position, branch_handle))
		
		# We need exactly 4 bones and weights (otherwise Godot crashes).
		if (bones.size() > 4):
			bones.resize(4)
			weights.resize(4)
		else:
			while (bones.size() < 4):
				bones.append(-1)
				weights.append(0.0)
		
		mesh_data_tool.set_vertex_bones(i, bones)
		mesh_data_tool.set_vertex_weights(i, weights)
	
	# Save the new mesh.
	var output_mesh := ArrayMesh.new()
	var arrays = Array()
	arrays.resize(ArrayMesh.ARRAY_MAX)
	mesh_data_tool.commit_to_surface(output_mesh)
	
	return output_mesh

func _get_pre_transform() -> Transform:
	var rotation_angle = deg2rad(mesh_rotation_degrees)
	var rotation_axis = Vector2(cos(rotation_angle), sin(rotation_angle))
	
	var pre_look_at = Vector3.ZERO
	var axis_lower = mesh_axis.to_lower()
	match (axis_lower):
		"x":
			pre_look_at = Vector3(-rotation_axis.x, 0, rotation_axis.y)
		"y":
			pre_look_at = Vector3(rotation_axis.x, rotation_axis.y, 0)
		"z":
			pre_look_at = Vector3(0, rotation_axis.y, -rotation_axis.x)
	
	var pre_up = Vector3.ZERO
	var up_axis_lower = mesh_up_axis.to_lower()
	match (up_axis_lower):
		"x":
			pre_up = Vector3(1, 0, 0)
		"y":
			pre_up = Vector3(0, 1, 0)
		"z":
			pre_up = Vector3(0, 0, 1)
		"-x":
			pre_up = Vector3(-1, 0, 0)
		"-y":
			pre_up = Vector3(0, -1, 0)
		"-z":
			pre_up = Vector3(0, 0, -1)
	
	var pre_transform: Transform
	pre_transform = pre_transform.looking_at(pre_look_at, pre_up)
	return pre_transform

func _get_branch_weight(vertex_position: Vector2, branch_handle: Vector2) -> float:
	# Weight of each branch depends on how far along the "bone" of the branch is the given vertex.
	# Vertices close to the origin are limited by 0.0, and vertices close to the branch handle
	# are limited by 1.0.
	
	# While each branch has a radil area of affect defined by the radius from the branch handle,
	# the weight is linear and corresponds to how far along the "bone" the vertex is. To get that
	# value we want to project the 2D position of the vector onto the branch "bone". That creates
	# a right-angle triangle, and we are using that fact to calculate the distance, which corresponds
	# to the weight when normalized.
	
	# Take the angle between two vectors: origin-to-vertex-2d-position and origin-to-branch-handle.
	var origin_angle = (vertex_position - intersection_origin_point).angle_to(branch_handle - intersection_origin_point)
	# Measure the distance from the vertex to the origin.
	var origin_length = vertex_position.distance_to(intersection_origin_point)
	# Use the cosine of the angle and the distance (basically, hypotenuse) to find the distance on the
	# "bone" (basically, cathetus).
	var offset_length = cos(origin_angle) * origin_length
	
	# Normalize the distance to get a value between 0.0 and 1.0.
	var normalized_weight = clamp(offset_length / branch_handle.distance_to(intersection_origin_point), 0.0, 1.0)
	return normalized_weight

func _ease_quart_inout(x: float) -> float:
	if (x < 0.5):
		return 8 * x * x * x * x
	return 1 - pow(-2 * x + 2, 4) / 2
