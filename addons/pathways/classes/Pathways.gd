tool
extends Spatial
class_name Pathways, "res://addons/pathways/icons/pathways.png"

# Public properties
export(NodePath) var output_node : NodePath setget set_output_node
export var apply_tilt : bool = false setget set_apply_tilt

# Private properties
var _output_container : Spatial
var _input_network : PathwayNetwork
var _input_pieces : Array = []

var _generating : bool = false

func _ready() -> void:
	if (Engine.editor_hint):
		_create_output()
		_update_inputs()
		_generate_output()

func add_child(node: Node, legible_name: bool = false) -> void:
	if (node == _output_container):
		return
	
	.add_child(node, legible_name)
	if (Engine.editor_hint):
		_update_inputs()
		_generate_output()

func remove_child(node: Node) -> void:
	if (node == _output_container):
		return
	
	.remove_child(node)
	if (Engine.editor_hint):
		_update_inputs()
		_generate_output()

# Properties
func set_output_node(value: NodePath) -> void:
	output_node = value
	
	if (Engine.editor_hint):
		_destroy_output()
		_create_output()
		_generate_output()

func set_apply_tilt(value: bool) -> void:
	apply_tilt = value
	
	if (Engine.editor_hint):
		_generate_output()

# Helpers
func _create_output() -> void:
	if (!is_inside_tree()):
		return
	if (_output_container && is_instance_valid(_output_container)):
		return
	
	# If there is a user configured output, use it.
	if (!output_node.is_empty()):
		var outer_node = get_node_or_null(output_node)
		if (outer_node && is_instance_valid(outer_node)):
			_output_container = outer_node
			return
	
	# If not, create our own internally.
	var node = Spatial.new()
	node.name = "PathwayOutput"
	add_child(node)
	node.owner = self.owner
	
	output_node = get_path_to(node)
	_output_container = node

func _create_output_instance(mesh: ArrayMesh, node_name: String) -> void:
	var output = MeshInstance.new()
	output.name = node_name
	output.transform = _input_network.transform
	output.mesh = mesh
	output.set_meta("_edit_lock_", true)
	
	_output_container.add_child(output)
	output.owner = self.owner

func _destroy_output() -> void:
	if (!is_inside_tree()):
		return
	if (!_output_container || !is_instance_valid(_output_container)):
		return
	
	if (_output_container.get_parent() == self):
		remove_child(_output_container)
		_output_container.queue_free()
	
	_output_container = null

func _update_inputs() -> void:
	if (_input_network && is_instance_valid(_input_network)):
		_input_network.disconnect("curves_changed", self, "_generate_output")
	for piece_node in _input_pieces:
		if (piece_node && is_instance_valid(piece_node)):
			piece_node.disconnect("mesh_changed", self, "_generate_output")
	
	_input_network = null
	_input_pieces = []
	
	for child_node in get_children():
		if (child_node == _output_container):
			continue
		
		if (child_node is PathwayNetwork):
			_input_network = child_node
			_input_network.connect("curves_changed", self, "_generate_output")
			continue
		
		if (child_node is PathwayPiece):
			_input_pieces.append(child_node)
			child_node.connect("mesh_changed", self, "_generate_output")

func _clear_output() -> void:
	for child_node in _output_container.get_children():
		_output_container.remove_child(child_node)
		child_node.queue_free()

func _is_network_valid() -> bool:
	return (_input_network && is_instance_valid(_input_network))

func _are_pieces_valid() -> bool:
	# Only one needs to be valid.
	for piece_node in _input_pieces:
		if (piece_node && is_instance_valid(piece_node) && piece_node.has_mesh()):
			return true
	
	return false

func _generate_output() -> void:
	# Don't do anything at runtime!
	if (!Engine.editor_hint):
		return
	# Only one process at a time.
	if (_generating):
		return
	_generating = true
	
	# If there is no output node, forcefully create it.
	if (!_output_container || !is_instance_valid(_output_container)):
		_create_output()
	else:
		_clear_output()
	
	# Nothing to do if there is no network and there are no meshes.
	if (!_is_network_valid() || !_are_pieces_valid()):
		_generating = false
		return
	
	var straight_pieces := []
	var intersection_pieces := []
	for piece_node in _input_pieces:
		if (piece_node && is_instance_valid(piece_node) && piece_node.has_mesh()):
			if (piece_node.piece_type == piece_node.PieceType.STRAIGHT):
				straight_pieces.append(piece_node)
			elif (piece_node.piece_type == piece_node.PieceType.INTERSECTION):
				intersection_pieces.append(piece_node)
	
	_generate_straights(straight_pieces)
	_generate_intersections(intersection_pieces)
	_generating = false

func _generate_straights(straight_pieces: Array) -> void:
	if (straight_pieces.size() == 0):
		return
	
	# TODO: Add support for random appropriate meshes, either completely random,
	# or user-controllable in some way. For example, using some pattern setting.
	var source_piece = straight_pieces[0]
	var source_mesh = source_piece.get_mesh()
	
	for i in _input_network.get_baked_curve_count():
		var curve = _input_network.get_baked_curve(i)
		# Curve needs to be at least 2 points long.
		if curve.get_point_count() < 2:
			continue
		# The up vector has to be enabled for this to work properly.
		if not curve.is_up_vector_enabled():
			printerr("Unable to stretch mesh: Up vector is not enabled for the curve.")
			continue
		
		var curve_start := 0.0
		var curve_start_node = _input_network.get_baked_curve_start(i)
		if (_input_network.is_intersection(curve_start_node)):
			curve_start = _get_curve_point_offset(curve, 1)
		
		var curve_end := 1.0
		var curve_end_node = _input_network.get_baked_curve_end(i)
		if (_input_network.is_intersection(curve_end_node)):
			curve_end = _get_curve_point_offset(curve, curve.get_point_count() - 2)
		
		# Calculate how many additional segments we need to fill the entire path.
		var mesh_axis_length = source_mesh.get_aabb().size.z
		# We don't need the full size of the curve, only the part between the rendered nodes.
		var curve_length: float = curve.get_baked_length() * (curve_end - curve_start)
		var segment_count = floor(curve_length / mesh_axis_length)
		if (segment_count == 0):
			continue
		
		# Extrude the mesh by replicating it the necessary amount of times.
		var extruded_mesh = _extrude_mesh(source_mesh, mesh_axis_length, segment_count)
		# Stretch the mesh along the curve.
		var output_mesh = _stretch_mesh(extruded_mesh, curve, curve_start, curve_end)
		
		_create_output_instance(output_mesh, "PathwayCurveInstance")

func _generate_intersections(intersection_pieces: Array) -> void:
	if (intersection_pieces.size() == 0):
		return
	
	var piece_groups := {}
	for piece in intersection_pieces:
		if (!piece_groups.has(piece.intersection_type)):
			piece_groups[piece.intersection_type] = []
		
		piece_groups[piece.intersection_type].append(piece)
	
	for i in _input_network.get_intersection_count():
		var intersection_data = _input_network.get_intersection(i)
		var intersection_curves = _input_network.get_intersection_curves(i)
		var branch_count = _input_network.get_intersection_branch_count(i)
		
		var source_piece
		if (branch_count == 3):
			# TODO: Utilize T shapes where it seems more appropriate to keep a better shape.
			if (!piece_groups.has(PathwayPiece.IntersectionType.Y)):
				continue
			
			# TODO: Support picking random pieces, possibly make it user-controllable in some way.
			source_piece = piece_groups[PathwayPiece.IntersectionType.Y][0]
		elif (branch_count == 4):
			if (!piece_groups.has(PathwayPiece.IntersectionType.X)):
				continue
			
			# TODO: Support picking random pieces, possibly make it user-controllable in some way.
			source_piece = piece_groups[PathwayPiece.IntersectionType.X][0]
		
		if (!source_piece):
			continue
		
		var source_mesh = source_piece.get_mesh()
		var source_bones = source_piece.get_intersection_branches()
		var deformed_mesh = _deform_rigged_mesh(source_mesh, source_bones, intersection_curves, intersection_data)
		
		_create_output_instance(deformed_mesh, "PathwayIntersectionInstance")

func _extrude_mesh(mesh: ArrayMesh, vertex_offset: float, segments: int) -> ArrayMesh:
	# Prepare mesh for extrusion.
	var mesh_data_tool = MeshDataTool.new()
	mesh_data_tool.create_from_surface(mesh, 0)
	
	# We store the material to re-apply it later.
	var surface_material = mesh_data_tool.get_material()
	
	# We als store every aspect of every existing vertex for duplication.
	var pa_vertex := PoolVector3Array()
	var pa_normal := PoolVector3Array()
	var pa_tangent := PoolRealArray()
	var pa_color := PoolColorArray()
	var pa_tex_uv := PoolVector2Array()
	var pa_tex_uv2 := PoolVector2Array()
	var pa_faces := PoolIntArray()
	
	for v in mesh_data_tool.get_vertex_count():
		pa_vertex.append(mesh_data_tool.get_vertex(v))
		pa_normal.append(mesh_data_tool.get_vertex_normal(v))
		
		var tangent = mesh_data_tool.get_vertex_tangent(v)
		pa_tangent.append(tangent.x)
		pa_tangent.append(tangent.y)
		pa_tangent.append(tangent.z)
		pa_tangent.append(tangent.d)
		
		pa_color.append(mesh_data_tool.get_vertex_color(v))
		pa_tex_uv.append(mesh_data_tool.get_vertex_uv(v))
		pa_tex_uv2.append(mesh_data_tool.get_vertex_uv2(v))
	
	for f in mesh_data_tool.get_face_count():
		pa_faces.append(mesh_data_tool.get_face_vertex(f, 0))
		pa_faces.append(mesh_data_tool.get_face_vertex(f, 1))
		pa_faces.append(mesh_data_tool.get_face_vertex(f, 2))
	
	# Start building the new mesh using the collected data.
	var vertices := PoolVector3Array()
	var normals := PoolVector3Array()
	var tangents := PoolRealArray()
	var colors := PoolColorArray()
	var tex_uvs := PoolVector2Array()
	var tex_uv2s := PoolVector2Array()
	var indices := PoolIntArray()
	
	for i in segments:
		# Vertices are offset along the Z axis; everything else is copied as is.
		for p in pa_vertex:
			vertices.append(p + Vector3(0, 0, vertex_offset) * i)
		
		for n in pa_normal:
			normals.append(n)
		
		tangents.append_array(pa_tangent)
		colors.append_array(pa_color)
		tex_uvs.append_array(pa_tex_uv)
		tex_uv2s.append_array(pa_tex_uv2)
		
		# TODO: Deduplicate similar vertices.
		for v in pa_faces:
			indices.append(v + pa_vertex.size() * i)
	
	var arrays := []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_NORMAL] = normals
	arrays[ArrayMesh.ARRAY_TANGENT] = tangents
	arrays[ArrayMesh.ARRAY_COLOR] = colors
	arrays[ArrayMesh.ARRAY_TEX_UV] = tex_uvs
	arrays[ArrayMesh.ARRAY_TEX_UV2] = tex_uv2s
	arrays[ArrayMesh.ARRAY_INDEX] = indices
	
	# We need a temporary mesh to re-apply the stored material.
	var temp_mesh = ArrayMesh.new()
	temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Reapply the material and save the final result.
	var out_mesh = ArrayMesh.new()
	mesh_data_tool.create_from_surface(temp_mesh, 0)
	mesh_data_tool.set_material(surface_material)
	mesh_data_tool.commit_to_surface(out_mesh)
	
	return out_mesh

func _stretch_mesh(mesh: ArrayMesh, curve: Curve3D, start_offset: float = 0.0, end_offset: float = 1.0) -> ArrayMesh:
	# Prepare the mesh for stretching along the path.
	var mesh_data_tool = MeshDataTool.new()
	mesh_data_tool.create_from_surface(mesh, 0)
	
	# Use local-space AABB to figure out how far along the Z axis is each vertex.
	var mesh_aabb = mesh.get_aabb()
	var min_mesh_side = mesh_aabb.position.z
	var max_mesh_side = mesh_aabb.end.z
	
	for i in mesh_data_tool.get_vertex_count():
		var position = mesh_data_tool.get_vertex(i)
		var normal = mesh_data_tool.get_vertex_normal(i)
		# Don't forget that Z-forward is -Z, not +Z.
		var offset = 1.0 - (position.z - min_mesh_side) / (max_mesh_side - min_mesh_side)
		# Shorten the curve to avoid rendering around intersections.
		offset = range_lerp(offset, 0.0, 1.0, start_offset, end_offset)
		
		# Unset that offset so that we can replace it with the curve data.
		position.z = 0
		
		# Transform the vertex in place to apply rotation/scale from the corresponding
		# point on the curve.
		var curve_transform := _get_curve_transform(curve, offset, apply_tilt)
		position = curve_transform.xform(position)
		normal = curve_transform.xform(normal)
		
		# Move the vertex to the corresponding position to align with the curve, and store
		# the results.
		var curve_transition := _get_curve_transition(curve, offset)
		mesh_data_tool.set_vertex(i, position + curve_transition)
		mesh_data_tool.set_vertex_normal(i, normal)
	
	var output_mesh = ArrayMesh.new()
	mesh_data_tool.commit_to_surface(output_mesh)
	
	return output_mesh

func _deform_rigged_mesh(mesh: ArrayMesh, bone_handles: Array, curves: Array, intersection_data: Dictionary) -> ArrayMesh:
	# Prepare the mesh for deformation.
	var mesh_data_tool = MeshDataTool.new()
	mesh_data_tool.create_from_surface(mesh, 0)
	
	var target_offset: Vector3 = intersection_data.position
	var origin_rotation: float = intersection_data.origin_rotation
	var origin_radius: float = intersection_data.origin_radius
	
	for i in mesh_data_tool.get_vertex_count():
		var position = mesh_data_tool.get_vertex(i)
		var target_position = position + target_offset
		var normal = mesh_data_tool.get_vertex_normal(i)
		
		var projected_position = Vector2(position.x, position.z)
		var bones = mesh_data_tool.get_vertex_bones(i)
		var weights = mesh_data_tool.get_vertex_weights(i)
		
		# Compute the effect of each bone on the deformation.
		var weighted_positions := PoolVector3Array()
		var weighted_normals := PoolVector3Array()
		for bi in bones.size():
			var b = bones[bi]
			var w = weights[bi]
			
			# Bone 0 is reserved for the origin handle, currently unused.
			# Values close to zero have no practical effect and are ignored.
			if (b <= 0 || is_zero_approx(w)):
				continue
			
			# We don't have a valid handle or a valid curve to consider.
			if (bone_handles.size() < b || curves.size() < b):
				continue
			
			# Unset the bone rotation and squash along the Z axis every vertex.
			# We need this to properly stretch vertices along each curve.
			var ref_handle: Vector2 = bone_handles[b - 1]
			var ref_transform: Transform
			var unset_angle = ref_handle.angle_to(Vector2(0, -1))
			ref_transform = ref_transform.rotated(Vector3(0, 1, 0), -unset_angle)
			ref_transform = ref_transform.scaled(Vector3(1, 1, 0))
			
			var w_position = ref_transform.xform(position)
			var w_normal = ref_transform.xform(normal)
			
			# Apply curve transform to the vertex.
			var curve: Curve3D = curves[b - 1]
			var curve_transform: Transform = _get_curve_transform(curve, w, apply_tilt)
			var curve_transition: Vector3 = _get_curve_transition(curve, w)
			
			w_position = curve_transform.xform(w_position)
			w_normal = curve_transform.xform(w_normal)
			
			# Collect the data, don't apply it yet.
			weighted_positions.append(target_position.linear_interpolate(w_position + curve_transition, w))
			weighted_normals.append(normal.linear_interpolate(w_normal, w))
		
		# Final position would be computed from all the weighted values.
		var final_position = target_position
		var final_normal = normal
		
		if (weighted_positions.size() == 1):
			final_position = weighted_positions[0]
			final_normal = weighted_normals[0]
		
		elif (weighted_positions.size() > 1):
			# TODO: Improve weight logic, average value is meh.
			final_position = Vector3.ZERO
			for p in weighted_positions:
				final_position += p
			final_position /= weighted_positions.size()
			
			final_normal = Vector3.ZERO
			for n in weighted_normals:
				final_normal += n
			final_normal /= weighted_normals.size()
		
		# TODO: This is probably not the best way to apply the rotation, look into improving it.
		# This is likely going to be related to a better implementation of weights, because
		# rotated center is not different from all other deformations that we perform here.
		# Alternatively, it would make sense to pre-rotate vertices before doing the rest of
		# the transforms. As long as the endpoints align with the curves.
		
		# Apply additional rotation from the network to fix possible visual artifacts.
		if (origin_rotation != 0):
			var origin_handle = Vector2(target_offset.x, target_offset.z)
			var projected_final_position = Vector2(final_position.x, final_position.z)
			var origin_offset: float = clamp(projected_final_position.distance_to(origin_handle), 0.0, origin_radius)
			origin_offset = 1.0 - range_lerp(origin_offset, 0.0, origin_radius, 0.0, 1.0)
			
			# Unset the position to rotate around the point.
			var unset_transform: Transform
			unset_transform = unset_transform.translated(Vector3(-target_offset.x, 0, -target_offset.z))
			var r_position = unset_transform.xform(final_position)
			var r_normal = final_normal # Normals don't get translated.
			
			# Rotate.
			var rotation_transform: Transform
			rotation_transform = rotation_transform.rotated(Vector3(0, 1, 0), origin_rotation)
			r_position = rotation_transform.xform(r_position)
			r_normal = rotation_transform.xform(r_normal)
			
			# Set the position back after the rotation.
			var reset_transform: Transform
			reset_transform = reset_transform.translated(Vector3(target_offset.x, 0, target_offset.z))
			r_position = reset_transform.xform(r_position)
			
			final_position = final_position.linear_interpolate(r_position, origin_offset)
			final_normal = final_normal.linear_interpolate(r_normal, origin_offset)
		
		mesh_data_tool.set_vertex(i, final_position)
		mesh_data_tool.set_vertex_normal(i, final_normal)
	
	var output_mesh = ArrayMesh.new()
	mesh_data_tool.commit_to_surface(output_mesh)
	
	return output_mesh

func _get_curve_point_offset(curve: Curve3D, point_index: int) -> float:
	var curve_length: float = curve.get_baked_length()
	var point_position: Vector3 = curve.get_point_position(point_index)
	
	var curve_offset = curve.get_closest_offset(point_position)
	return curve_offset / curve_length

func _get_curve_transition(curve: Curve3D, offset: float) -> Vector3:
	var curve_length: float = curve.get_baked_length()
	offset = offset * curve_length
	return curve.interpolate_baked(offset)

func _get_curve_transform(curve: Curve3D, offset: float, apply_tilt: bool) -> Transform:
	var curve_length: float = curve.get_baked_length()
	offset = offset * curve_length
	var position_on_curve: Vector3 = curve.interpolate_baked(offset)

	var up: Vector3 = curve.interpolate_baked_up_vector(offset, apply_tilt)
	var position_look_at: Vector3

	if offset + 0.05 < curve_length:
		position_look_at = curve.interpolate_baked(offset + 0.05)
	else:
		position_look_at = curve.interpolate_baked(offset - 0.05)
		position_look_at += 2.0 * (position_on_curve - position_look_at)
	
	var curve_transform: Transform
	var look_at = position_look_at - position_on_curve
	curve_transform = curve_transform.looking_at(look_at, up)
	return curve_transform
