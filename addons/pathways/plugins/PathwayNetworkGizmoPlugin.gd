extends EditorSpatialGizmoPlugin

# Private properties
var _editor_plugin : EditorPlugin
var _edited_network : PathwayNetwork

var _node_ids : PoolIntArray
var _intersection_ids : PoolIntArray
var _control_handles : Array = []
var _branching_id : int = -1

var _preview_placement : bool = false
var _node_handle_clicked : int = -1
var _control_handle_clicked : int = -1

const CLICK_DISTANCE : int = 10
const RAY_DISTANCE : int = 4096

func _init(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin
	var base_control = _editor_plugin.get_editor_interface().get_base_control()
	
	create_material("network_lines", base_control.get_color("network_lines", "PathwaysPlugin"))
	create_material("control_lines", base_control.get_color("control_lines", "PathwaysPlugin"))
	create_material("intersection_lines", base_control.get_color("intersection_lines", "PathwaysPlugin"))
	create_material("baked_lines", base_control.get_color("baked_lines", "PathwaysPlugin"))
	_create_custom_handle_material("node_handles", base_control.get_icon("node_handle", "PathwaysPlugin"), -3)
	_create_custom_handle_material("node_selected_handles", base_control.get_icon("node_handle_selected", "PathwaysPlugin"), 0)
	_create_custom_handle_material("node_branch_handles", base_control.get_icon("node_handle_add", "PathwaysPlugin"), -4)
	_create_custom_handle_material("control_handles", base_control.get_icon("control_handle", "PathwaysPlugin"), -5)
	_create_custom_handle_material("intersection_handles", base_control.get_icon("intersection_handle", "PathwaysPlugin"), -5)

# Public methods
func get_name() -> String:
	return "PathwayNetwork"

func has_gizmo(spatial: Spatial) -> bool:
	return spatial is PathwayNetwork

func edit_network(edited_network: PathwayNetwork) -> void:
	_edited_network = edited_network

# Implementation
func get_handle_name(gizmo: EditorSpatialGizmo, index: int) -> String:
	var network = gizmo.get_spatial_node() as PathwayNetwork
	var gizmo_node = _get_gizmo_node(index)
	
	if (gizmo_node.is_control):
		return "Node %d Control %d" % [ gizmo_node.node_id, gizmo_node.control_index ]
	
	if (gizmo_node.is_branch):
		return "Node %d Branching" % [ gizmo_node.node_id ]
	
	return "Node %d" % [ gizmo_node.node_id ]

func get_handle_value(gizmo: EditorSpatialGizmo, index: int):
	var network = gizmo.get_spatial_node() as PathwayNetwork
	var gizmo_node = _get_gizmo_node(index)
	if (gizmo_node.node_id < 0):
		return {}
	
	var node_data = network.network_nodes[gizmo_node.node_id]
	return node_data.duplicate(true)

func set_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	var network = gizmo.get_spatial_node() as PathwayNetwork
	# Determine which node we are editing, regardless of which handle (main or control) was used.
	var gizmo_node = _get_gizmo_node(index)
	if (gizmo_node.node_id < 0):
		return
	
	# Get relevant node data.
	var node_data = network.network_nodes[gizmo_node.node_id]
	
	# When Control is pressed, we branch from the node instead of moving it.
	var control_pressed = Input.is_key_pressed(KEY_CONTROL)
	if (control_pressed && !gizmo_node.is_control):
		# Find the intersection from the camera and mouse position.
		var next_position = _intersect_screen_space(camera, point, node_data.position + node_data.branch_control)
		if (next_position):
			next_position = network.to_local(next_position)
			node_data.branch_control = next_position - node_data.position
		
		redraw(gizmo)
		return
	
	# When Shift is pressed, we forcefully operate on control handles.
	var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if (shift_pressed && !gizmo_node.is_control):
		gizmo_node.is_control = true
		gizmo_node.control_index = 0 # Even if it doesn't exist, it shouldn't fail.
	
	# Use the appropriate reference position.
	var position_origin = node_data.position
	if (gizmo_node.is_control):
		position_origin = node_data.position + network.get_node_control(gizmo_node.node_id, gizmo_node.control_index)
	
	# Find the spatial position from the camera and mouse position.
	var next_position = _intersect_screen_space(camera, point, position_origin)
	if (next_position):
		next_position = network.to_local(next_position)
		
		if (gizmo_node.is_control):
			if (shift_pressed):
				network.spread_node_controls(gizmo_node.node_id, gizmo_node.control_index, next_position - node_data.position)
			else:
				network.set_node_control(gizmo_node.node_id, gizmo_node.control_index, next_position - node_data.position)
		elif (gizmo_node.is_intersection):
			var relative_position = next_position - node_data.position
			# Results are signed, so use the X axis to figure out the sign.
			var rotation_angle = Vector3(0, 0, -1).angle_to(relative_position) * sign(relative_position.x)
			
			network.set_node_origin(gizmo_node.node_id, -rotation_angle, relative_position.length())
		else:
			node_data.position = next_position
	
	redraw(gizmo)

func commit_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:
	var network = gizmo.get_spatial_node() as PathwayNetwork
	var gizmo_node = _get_gizmo_node(index)
	if (gizmo_node.node_id < 0):
		return
	
	var current_value = get_handle_value(gizmo, index)
	var node_id = gizmo_node.node_id
	
	if (cancel):
		network.set_node_position(node_id, restore.position, restore.in_controls, restore.out_controls)
	else:
		var undo_redo = _editor_plugin.get_undo_redo()
		
		# If branch handle has been moved, we need to spawn a new node (but no more than 3 children per node).
		if (current_value.branch_control != Vector3.ZERO):
			var next_node_id = network.get_next_id()
			var next_node_position = current_value.position + current_value.branch_control
			
			if (!network.try_add_node(next_node_position, node_id)):
				return
			
			var affected_nodes = network.get_affected_nodes()
			undo_redo.create_action("Branch Pathway Network Node")
			undo_redo.add_do_method(network, "add_node", next_node_position, node_id)
			undo_redo.add_undo_method(network, "restore_node_states", affected_nodes)
			undo_redo.commit_action()
		else:
			# If nothing has been changed as a result of the interaction, it is just a click. 
			if (
				current_value.position == restore.position
				&& network.are_controls_equal(current_value.in_controls, restore.in_controls)
				&& network.are_controls_equal(current_value.out_controls, restore.out_controls)
				&& current_value.origin_rotation == restore.origin_rotation
				&& current_value.origin_radius == restore.origin_radius
			):
				# If it's the same selected node, do nothing.
				if (network.selected_node == node_id):
					return
				
				# When control is held, we are in creation mode, so we try to connect the nodes
				var control_pressed = Input.is_key_pressed(KEY_CONTROL)
				if (control_pressed):
					if (!network.try_connect_path(network.selected_node, node_id)):
						return
					
					var affected_nodes = network.get_affected_nodes()
					undo_redo.create_action("Connect a Pathway Network segment")
					undo_redo.add_do_method(network, "connect_path", network.selected_node, node_id)
					undo_redo.add_undo_method(network, "restore_node_states", affected_nodes)
					undo_redo.commit_action()
				# Just select the node otherwise.
				else:
					network.select_node(node_id)
			# If there are changes, we commit them.
			else:
				if (current_value.origin_rotation != restore.origin_rotation || current_value.origin_radius != restore.origin_radius):
					undo_redo.create_action("Adjust Pathway Network Intersection")
					undo_redo.add_do_method(network, "set_node_origin", node_id, current_value.origin_rotation, current_value.origin_radius)
					undo_redo.add_undo_method(network, "set_node_origin", node_id, restore.origin_rotation, restore.origin_radius)
					undo_redo.commit_action()
					network.select_node(node_id)
				else:
					undo_redo.create_action("Adjust Pathway Network Node")
					undo_redo.add_do_method(network, "set_node_position", node_id, current_value.position, current_value.in_controls, current_value.out_controls)
					undo_redo.add_undo_method(network, "set_node_position", node_id, restore.position, restore.in_controls, restore.out_controls)
					undo_redo.commit_action()
					network.select_node(node_id)

func redraw(gizmo: EditorSpatialGizmo) -> void:
	gizmo.clear()
	var network = gizmo.get_spatial_node() as PathwayNetwork
	var gizmo_data = _get_gizmo_data(network)
	if (gizmo_data.empty()):
		return
	
	# Cache gizmo data
	_node_ids = gizmo_data.node_ids
	_intersection_ids = gizmo_data.intersection_ids
	_branching_id = gizmo_data.branching_id
	_control_handles = gizmo_data.control_handles
	
	# Draw order (but only draw most of it if we are actively editing it)
	if (network == _edited_network):
		gizmo.add_lines(gizmo_data.network_lines, get_material("network_lines", gizmo))
		gizmo.add_lines(gizmo_data.control_lines, get_material("control_lines", gizmo))
		gizmo.add_lines(gizmo_data.intersection_lines, get_material("intersection_lines", gizmo))
		gizmo.add_lines(gizmo_data.branch_lines, get_material("network_lines", gizmo))
	
	gizmo.add_lines(gizmo_data.baked_lines, get_material("baked_lines", gizmo))
	
	if (network == _edited_network):
		if (gizmo_data.pre_selected_handles.size() > 0):
			gizmo.add_handles(gizmo_data.pre_selected_handles, get_material("node_handles", gizmo))
		if (gizmo_data.selected_handles.size() > 0):
			gizmo.add_handles(gizmo_data.selected_handles, get_material("node_selected_handles", gizmo))
		if (gizmo_data.post_selected_handles.size() > 0):
			gizmo.add_handles(gizmo_data.post_selected_handles, get_material("node_handles", gizmo))
		
		for control_handles in gizmo_data.control_handles:
			if (control_handles.size() > 0):
				gizmo.add_handles(control_handles, get_material("control_handles", gizmo))
		
		if (gizmo_data.intersection_handles.size() > 0):
			gizmo.add_handles(gizmo_data.intersection_handles, get_material("intersection_handles", gizmo))
		
		if (gizmo_data.branch_handles.size() > 0):
			gizmo.add_handles(gizmo_data.branch_handles, get_material("node_branch_handles", gizmo))
	
	# Enable selecting the node by the curve.
	gizmo.add_collision_segments(gizmo_data.baked_lines)

# Spatial Editor handlers
func draw_over_viewport(overlay: Control) -> void:
	if (!_preview_placement):
		return
	
	var base_control = _editor_plugin.get_editor_interface().get_base_control()
	var handle_icon = base_control.get_icon("node_handle_add", "PathwaysPlugin")
	if (!handle_icon):
		return
	
	var position = overlay.get_local_mouse_position()
	overlay.draw_texture(handle_icon, position - handle_icon.get_size() / 2, Color(1, 1, 1, 0.25))

func handle_gui_input(camera: Camera, event: InputEvent) -> bool:
	if (!_edited_network || !is_instance_valid(_edited_network)):
		return false
	
	var mb = event as InputEventMouseButton
	if (mb):
		if (!mb.pressed):
			_node_handle_clicked = -1
			return false
		
		var gt = _edited_network.global_transform
		var it = gt.affine_inverse()
		
		# Ctrl + Left Click - Create a new point, either by splitting the path or by adding to the end of it.
		if (mb.button_index == BUTTON_LEFT && mb.control):
			# Clicked on an existing node, skipping.
			var existing_id = _get_node_at_position(camera, mb.position)
			if (existing_id >= 0):
				_node_handle_clicked = existing_id
				return false
			
			# Clicked on an existing path, split it.
			var path = _get_path_at_position(camera, mb.position)
			if (path.size() == 3):
				var next_node_id = _edited_network.get_next_id()
				
				if (!_edited_network.try_split_path(path[0], path[1], path[2])):
					return false
				
				var affected_nodes = _edited_network.get_affected_nodes()
				var undo_redo = _editor_plugin.get_undo_redo()
				undo_redo.create_action("Split a Pathway Network segment")
				undo_redo.add_do_method(_edited_network, "split_path", path[0], path[1], path[2])
				undo_redo.add_undo_method(_edited_network, "restore_node_states", affected_nodes)
				undo_redo.commit_action()
				
				return true
			
			# Clicked on an empty space, find the relevant 3D space position and add a node there.
			var origin = _edited_network.transform.origin
			var last_node_id = -1
			if (_edited_network.network_nodes.size() > 0):
				last_node_id = _edited_network.network_nodes.keys()[-1]
				var last_node = _edited_network.network_nodes[last_node_id]
				origin = gt.xform(last_node.position)
			
			var intersects = _intersect_screen_space(camera, mb.position, origin)
			if (intersects):
				var next_node_id = _edited_network.get_next_id()
				var next_node_position = it.xform(intersects)
				
				if (!_edited_network.try_add_node(next_node_position, _edited_network.selected_node)):
					return false
				
				var affected_nodes = _edited_network.get_affected_nodes()
				var undo_redo = _editor_plugin.get_undo_redo()
				undo_redo.create_action("Add Node to Pathway Network")
				undo_redo.add_do_method(_edited_network, "add_node", next_node_position, _edited_network.selected_node)
				undo_redo.add_undo_method(_edited_network, "restore_node_states", affected_nodes)
				undo_redo.commit_action()
			
				return true
		
		# Right Click - Remove an existing point.
		elif (mb.button_index == BUTTON_RIGHT):
			# Clicked on an existing node, remove it.
			var node_id = _get_node_at_position(camera, mb.position, true)
			if (node_id >= 0):
				var node_data = _edited_network.network_nodes[node_id].duplicate(true)
				
				var undo_redo = _editor_plugin.get_undo_redo()
				if (_control_handle_clicked >= 0):
					undo_redo.create_action("Remove Smoothing from Pathway Network Node")
					undo_redo.add_do_method(_edited_network, "set_control_position", node_id, _control_handle_clicked, Vector3.ZERO)
					undo_redo.add_undo_method(_edited_network, "set_control_position", node_id, _control_handle_clicked, _edited_network.get_node_control(node_id, _control_handle_clicked))
					undo_redo.commit_action()
				else:
					if (!_edited_network.try_remove_node(node_id)):
						return false
					
					var affected_nodes = _edited_network.get_affected_nodes()
					undo_redo.create_action("Remove Node from Pathway Network")
					undo_redo.add_do_method(_edited_network, "remove_node", node_id)
					undo_redo.add_undo_method(_edited_network, "restore_node_states", affected_nodes)
					undo_redo.commit_action()
				
				return true
			
			# Clicked on an existing path, remove it.
			var path = _get_path_at_position(camera, mb.position)
			if (path.size() == 3):
				var next_node_id = _edited_network.get_next_id()
				
				if (!_edited_network.try_remove_path(path[0], path[1])):
					return false
				
				var affected_nodes = _edited_network.get_affected_nodes()
				var undo_redo = _editor_plugin.get_undo_redo()
				undo_redo.create_action("Remove a Pathway Network segment")
				undo_redo.add_do_method(_edited_network, "remove_path", path[0], path[1])
				undo_redo.add_undo_method(_edited_network, "restore_node_states", affected_nodes)
				undo_redo.commit_action()
				
				return true
	
	var mm = event as InputEventMouseMotion
	if (mm):
		if (_get_node_at_position(camera, mm.position) >= 0):
			_preview_placement = false
		else:
			_preview_placement = mm.control
		_editor_plugin.update_overlays()
	
	return false

# Helpers
func _get_gizmo_data(network: PathwayNetwork) -> Dictionary:
	if (network.network_nodes.size() == 0):
		return {}
	
	var node_ids := PoolIntArray()
	var intersection_ids := PoolIntArray()
	var branching_id := -1
	
	var pre_selected_handles := PoolVector3Array()
	var selected_handles := PoolVector3Array()
	var post_selected_handles := PoolVector3Array()
	
	var control_handles := []
	var intersection_handles := PoolVector3Array()
	var branch_handles := PoolVector3Array()
	var control_lines := PoolVector3Array()
	var intersection_lines := PoolVector3Array()
	var branch_lines := PoolVector3Array()
	
	var network_lines := PoolVector3Array()
	var baked_lines := PoolVector3Array()
	
	# Node-related data.
	var fill_pre := true
	for node_id in network.network_nodes:
		var node_data = network.network_nodes[node_id]
		node_ids.append(node_id)
		
		# Build the sequence of node handles. We want to render the selected node
		# differently, and we can only add groups of nodes to the gizmo. Therefore,
		# we build 3 lists: before selected, after selected, and the selected itself.
		if (network.selected_node >= 0 && network.selected_node == node_id):
			selected_handles.append(node_data.position)
			fill_pre = false
		elif (fill_pre):
			pre_selected_handles.append(node_data.position)
		else:
			post_selected_handles.append(node_data.position)
		
		# Collect available control handles in sub-arrays to map them back to
		# node indices later.
		var node_control_handles := PoolVector3Array()
		for in_control in node_data.in_controls:
			node_control_handles.append(node_data.position + in_control)
		for out_control in node_data.out_controls:
			node_control_handles.append(node_data.position + out_control)
		control_handles.append(node_control_handles)
		
		for control_handle in node_control_handles:
			if (control_handle != node_data.position):
				control_lines.append(node_data.position)
				control_lines.append(control_handle)
		
		# Collect the origin information for the intersection nodes.
		if (network.is_intersection(node_id)):
			intersection_ids.append(node_id)
			
			var ref_handle = Vector3(0, 0, -node_data.origin_radius)
			var intersection_handle = ref_handle.rotated(Vector3(0, 1, 0), node_data.origin_rotation)
			intersection_handles.append(node_data.position + intersection_handle)
			
			# Add a connecting line from center to handle.
			intersection_lines.append(node_data.position)
			intersection_lines.append(node_data.position + intersection_handle)
			
			# Then draw a circle for the radius.
			var c = 0.0
			var c_step := TAU / 24
			while (c <= TAU):
				intersection_lines.append(node_data.position + ref_handle)
				ref_handle = ref_handle.rotated(Vector3(0, 1, 0), -c_step)
				intersection_lines.append(node_data.position + ref_handle)
				c += c_step
		
		# Only add one branch handle, for the currently branching node.
		if (node_data.branch_control != Vector3.ZERO):
			branching_id = node_id
			
			branch_handles.append(node_data.position + node_data.branch_control)
			branch_lines.append(node_data.position)
			branch_lines.append(node_data.position + node_data.branch_control)
	
	# Network-related data.
	network.start_node_iterating()
	
	# Keep iterating until there are no starting/head nodes left (at which point every node should have been looked at).
	var head_id = network.get_next_head()
	while (head_id >= 0):
		var head_data = network.network_nodes[head_id]
		
		var branch_id = network.get_next_branch()
		while (branch_id >= 0):
			# Lines are pairs of points, so always store the first node
			network_lines.append(head_data.position)
			
			var node_id = branch_id
			while (node_id >= 0):
				# Close the current line by adding the next node.
				var node_data = network.network_nodes[node_id]
				network_lines.append(node_data.position)
				
				# Follow the path to the next node.
				node_id = network.get_next_node()
				
				# If there is the next node, add the current node to start the line.
				# It will be closed on the next iteration.
				if (node_id >= 0):
					network_lines.append(node_data.position)
			
			# Move to the next branch.
			branch_id = network.get_next_branch()
			
		head_id = network.get_next_head()
	
	# Generated curve data.
	for curve in network.baked_curves:
		curve = curve as Curve3D
		var curve_points = curve.tessellate()
		
		for i in curve_points.size() - 1:
			baked_lines.append(curve_points[i])
			baked_lines.append(curve_points[i + 1])
	
	return {
		"node_ids": node_ids,
		"intersection_ids": intersection_ids,
		"branching_id": branching_id,
		
		"pre_selected_handles": pre_selected_handles,
		"selected_handles": selected_handles,
		"post_selected_handles": post_selected_handles,
		
		"control_handles": control_handles,
		"intersection_handles": intersection_handles,
		"branch_handles": branch_handles,
		"control_lines": control_lines,
		"intersection_lines": intersection_lines,
		"branch_lines": branch_lines,
		
		"network_lines": network_lines,
		"baked_lines": baked_lines,
	}

func _get_gizmo_node(index: int) -> Dictionary:
	var data := {
		"node_id": -1,
		"is_control": false,
		"control_index": -1,
		"is_intersection": false,
		"is_branch": false,
	}
	
	# Main node handles.
	var node_count = _node_ids.size()
	if (index < node_count):
		data.node_id = _node_ids[index]
		return data
	
	# Shift the index by the inspected range.
	index = index - node_count
	
	# Control handles.
	# In the stored data we have an array of control handles for every node.
	# This array can be empty, just so that we have a correct node index in
	# the end. We also need to convert the common index from the input data
	# to the per-node index, when we do find the appropriate control.
	
	var i := 0
	var control_offset := 0
	for node_control_handles in _control_handles:
		if (node_control_handles.size() == 0):
			i += 1
			continue
		
		# We compare in a similar way to the main node handles. For that we need
		# to determine where the next collection ends, so we increment the offset.
		# If the index is within the current offset, we found our collection.
		control_offset += node_control_handles.size()
		if (index < control_offset):
			data.node_id = _node_ids[i]
			data.is_control = true
			data.control_index = node_control_handles.size() - (control_offset - index)
			return data
		
		# If not, continue to the next set of handles.
		i += 1
	
	# Shift the index by the inspected range.
	index = index - control_offset
	
	# Intersection handles.
	var intersection_count = _intersection_ids.size()
	if (index < intersection_count):
		data.node_id = _intersection_ids[index]
		data.is_intersection = true
		return data
	
	# Shift the index by the inspected range.
	index = index - intersection_count
	
	# Branch handles.
	data.node_id = _branching_id
	data.is_branch = true
	return data

func _get_node_at_position(camera: Camera, position: Vector2, with_controls: bool = false) -> int:
	_control_handle_clicked = -1
	var gt = _edited_network.global_transform
	
	for node_id in _edited_network.network_nodes:
		var node_data = _edited_network.network_nodes[node_id]
		
		var distance = camera.unproject_position(gt.xform(node_data.position)).distance_to(position)
		if (distance < CLICK_DISTANCE):
			return node_id
		
		if (with_controls):
			var control_index := 0
			for in_control in node_data.in_controls:
				var in_distance = camera.unproject_position(gt.xform(node_data.position + in_control)).distance_to(position)
				if (in_distance < CLICK_DISTANCE):
					_control_handle_clicked = control_index
					return node_id
				
				control_index += 1
			
			for out_control in node_data.out_controls:
				var out_distance = camera.unproject_position(gt.xform(node_data.position + out_control)).distance_to(position)
				if (out_distance < CLICK_DISTANCE):
					_control_handle_clicked = control_index
					return node_id
				
				control_index += 1
	
	return -1

func _get_path_at_position(camera: Camera, position: Vector2) -> Array:
	var curve_clicked := false
	var closest_position = Vector3.ZERO
	var closest_distance = 1e20
	var segment_start_point = Vector3.ZERO
	var segment_end_point = Vector3.ZERO
	
	var gt = _edited_network.global_transform
	var it = gt.affine_inverse()
	
	# Check every curve in order and find the closest we could've clicked to one of them.
	for curve in _edited_network.baked_curves:
		var curve_points = curve.tessellate()
		for i in curve.get_point_count() - 1:
			var prev_position = curve.get_point_position(i)
			var next_position = curve.get_point_position(i + 1)
			
			var j = 0
			while (j < curve_points.size() && next_position != curve_points[j]):
				var j_from = curve_points[j] as Vector3
				var j_to = curve_points[j + 1] as Vector3
				var j_distance = j_from.distance_to(j_to)
				
				if (j_distance > 0):
					j_from = gt.xform(j_from)
					j_to = gt.xform(j_to)
					
					var segment_from = camera.unproject_position(j_from)
					var segment_to = camera.unproject_position(j_to)
					var segment_point = Geometry.get_closest_point_to_segment_2d(position, segment_from, segment_to)
					var click_distance = segment_point.distance_to(position)
					
					if (click_distance < CLICK_DISTANCE && click_distance < closest_distance):
						curve_clicked = true
						closest_distance = click_distance
						segment_start_point = prev_position
						segment_end_point = next_position
						
						var ray_from = camera.project_ray_origin(position)
						var ray_direction = camera.project_ray_normal(position)
						var ray_results = Geometry.get_closest_points_between_segments(ray_from, ray_from + ray_direction * RAY_DISTANCE, j_from, j_to)
						
						closest_position = it.xform(ray_results[1])
				
				j += 1
	
	var undo_redo = _editor_plugin.get_undo_redo()
	if (curve_clicked):
		# If a curve click was detected, find the related nodes on the network.
		var start_node := -1
		var end_node := -1
		
		for node_id in _edited_network.network_nodes:
			var node_data = _edited_network.network_nodes[node_id]
			# Node would have exactly the same position.
			if (node_data.position == segment_start_point):
				start_node = node_id
			elif (node_data.position == segment_end_point):
				end_node = node_id
			
			if (start_node != -1 && end_node != -1):
				return [ start_node, end_node, closest_position ]
	
	return []

func _intersect_with_colliders(camera: Camera, screen_point: Vector2): # Vector3 or null
	var from = camera.project_ray_origin(screen_point)
	var dir = camera.project_ray_normal(screen_point)
	
	var space_state = _edited_network.get_world().direct_space_state
	var result = space_state.intersect_ray(from, from + dir * RAY_DISTANCE)
	
	if result:
		return result.position
	return null

func _intersect_with_plane(camera: Camera, screen_point: Vector2) -> Vector3:
	var from = camera.project_ray_origin(screen_point)
	var dir = camera.project_ray_normal(screen_point)
	
	var t = _edited_network.get_global_transform()
	var a = t.basis.x
	var b = t.basis.z
	var c = a + b
	var o = t.origin
	var plane = Plane(a + o, b + o, c + o)
	
	return plane.intersects_ray(from, dir)

func _intersect_screen_space(camera: Camera, screen_point: Vector2, from_origin: Vector3) -> Vector3:
	var from = camera.project_ray_origin(screen_point)
	var dir = camera.project_ray_normal(screen_point)
	
	var gt = _edited_network.get_global_transform()
	var point: Vector3 = gt.xform(from_origin)
	var camera_basis: Basis = camera.get_transform().basis
	var plane := Plane(point, point + camera_basis.x, point + camera_basis.y)
	
	return plane.intersects_ray(from, dir)

func _create_custom_handle_material(name: String, icon: Texture, priority: int = 0, billboard: bool = false) -> void:
	var material = SpatialMaterial.new()
	
	material.flags_unshaded = true
	material.flags_use_point_size = true
	
	material.params_point_size = icon.get_width()
	material.albedo_texture = icon
	material.albedo_color = Color.white
	
	material.flags_transparent = true
	material.vertex_color_use_as_albedo = true
	material.flags_albedo_tex_force_srgb = true
	material.flags_no_depth_test = true
	material.render_priority = SpatialMaterial.RENDER_PRIORITY_MAX + priority
	
	if (billboard):
		material.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
	
	add_material(name, material)
