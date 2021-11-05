tool
extends Spatial
class_name PathwayNetwork, "res://addons/pathways/icons/pathway-network.png"

# Public properties
var network_nodes : Dictionary = {}
var selected_node : int = -1
var baked_curves : Array = []
var curve_endpoints : Array = []
var intersection_nodes : Array = []
var intersection_curves : Array = []

var split_curves : bool = false setget set_split_curves
var split_size : int = 8 setget set_split_size

var enable_verbose_print : bool = false

# Private properties
var _iterator_stack : Array = []
var _iterator_unvisited_ids : Array = []
var _iterator_cheat_visit_ids : Array = []
var _iterator_head_id : int = -1
var _iterator_branch_idx : int = -1
var _iterator_branch_node : int = -1

enum NodeOperation {
	NODE_ADDED,
	NODE_UPDATED,
	NODE_REMOVED
}
var _operation_affected_nodes : Dictionary = {}

signal curves_changed()

func _ready() -> void:
	if (network_nodes.size() > 0):
		selected_node = network_nodes.keys()[-1]

func _get_property_list() -> Array:
	var properties := []
	
	# Internal properties
	properties.append({
		"name": "network_nodes",
		"type": TYPE_DICTIONARY,
		"usage": PROPERTY_USAGE_NOEDITOR,
	})
	properties.append({
		"name": "baked_curves",
		"type": TYPE_ARRAY,
		"usage": PROPERTY_USAGE_NOEDITOR,
	})
	properties.append({
		"name": "curve_endpoints",
		"type": TYPE_ARRAY,
		"usage": PROPERTY_USAGE_NOEDITOR,
	})
	properties.append({
		"name": "intersection_nodes",
		"type": TYPE_ARRAY,
		"usage": PROPERTY_USAGE_NOEDITOR,
	})
	properties.append({
		"name": "intersection_curves",
		"type": TYPE_ARRAY,
		"usage": PROPERTY_USAGE_NOEDITOR,
	})
	
	# Configuration properties
	properties.append({
		"name": "split_curves",
		"type": TYPE_BOOL,
		"usage": PROPERTY_USAGE_DEFAULT,
	})
	properties.append({
		"name": "split_size",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "2,20,1,or_greater",
	})
	
	# Editor and debug properties.
	properties.append({
		"name": "Editor",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
	})
	properties.append({
		"name": "enable_verbose_print",
		"type": TYPE_BOOL,
		"USAGE": PROPERTY_USAGE_DEFAULT,
	})
	
	return properties

func property_can_revert(property_name: String) -> bool:
	if (property_name == "split_curves"):
		return split_curves != false
	
	if (property_name == "split_size"):
		return split_size != 8
	
	return false

func property_get_revert(property_name: String):
	if (property_name == "split_curves"):
		return false
	
	if (property_name == "split_size"):
		return 8
	
	return null

func set_split_curves(value: bool) -> void:
	split_curves = value
	_update_curves()

func set_split_size(value: int) -> void:
	split_size = value
	_update_curves()

# Properties
func get_network_nodes() -> Dictionary:
	return network_nodes

func get_network_node(node_id: int) -> Dictionary:
	if (node_id < 0 || !network_nodes.has(node_id)):
		return {}
	
	return network_nodes[node_id]

func get_selected_node() -> int:
	return selected_node

func get_node_control(node_id: int, control_index: int) -> Vector3:
	if (!network_nodes.has(node_id) || control_index < 0):
		return Vector3.ZERO
	var node_data = network_nodes[node_id]
	
	if (control_index < node_data.in_controls.size()):
		return node_data.in_controls[control_index]
	
	control_index = control_index - node_data.in_controls.size()
	
	if (control_index < node_data.out_controls.size()):
		return node_data.out_controls[control_index]
	
	return Vector3.ZERO

func set_node_control(node_id: int, control_index: int, position: Vector3) -> void:
	if (!network_nodes.has(node_id) || control_index < 0):
		return
	
	var node_data = network_nodes[node_id]
	if (control_index < node_data.in_controls.size()):
		node_data.in_controls[control_index] = position
	else:
		control_index = control_index - node_data.in_controls.size()
		if (control_index < node_data.out_controls.size()):
			node_data.out_controls[control_index] = position

func spread_node_controls(node_id: int, leading_control_index: int, leading_position: Vector3) -> void:
	if (!network_nodes.has(node_id) || leading_control_index < 0):
		return
	
	var node_data = network_nodes[node_id]
	var node_controls := []
	node_controls.append_array(node_data.in_controls)
	node_controls.append_array(node_data.out_controls)
	if (node_controls.size() == 0):
		return
	
	# The leasding control is always set to its actual value.
	set_node_control(node_id, leading_control_index, leading_position)
	if (node_controls.size() == 1):
		return
	
	# For two controls we just mirror the opposite one.
	if (node_controls.size() == 2):
		var mirrored_control_index = 1 - leading_control_index
		var mirrored_position = -leading_position
		set_node_control(node_id, mirrored_control_index, mirrored_position)
		return
	
	# For three and four controls we spread them evenly, using the up direction
	# as an axis (reasoning that most roads are flat with the ground, more or less).
	
	# We need to order all the handles for this to work sensibly. Handles must
	# go in a clockwise direction based on their corresponding branches.
	var control_indices = _get_ordered_node_controls(node_data, leading_control_index)
	
	if (node_controls.size() == 3):
		var rotated_control_index1 = control_indices[0]
		var rotated_position1 = _rotate_handle_around_node(leading_position, -120)
		set_node_control(node_id, rotated_control_index1, rotated_position1)
		
		var rotated_control_index2 = control_indices[1]
		var rotated_position2 = _rotate_handle_around_node(leading_position, 120)
		set_node_control(node_id, rotated_control_index2, rotated_position2)
	
	elif (node_controls.size() == 4):
		var mirrored_control_index = control_indices[1]
		var mirrored_position = -leading_position
		set_node_control(node_id, mirrored_control_index, mirrored_position)
		
		var rotated_control_index1 = control_indices[0]
		var rotated_position1 = _rotate_handle_around_node(leading_position, -90)
		set_node_control(node_id, rotated_control_index1, rotated_position1)
		
		var rotated_control_index2 = control_indices[2]
		var rotated_position2 = _rotate_handle_around_node(leading_position, 90)
		set_node_control(node_id, rotated_control_index2, rotated_position2)

func get_baked_curves() -> Array:
	return baked_curves

func get_baked_curve_count() -> int:
	return baked_curves.size()

func get_baked_curve(index: int) -> Curve3D:
	if (index < 0 || index >= baked_curves.size()):
		return null
	
	return baked_curves[index]

func get_baked_curve_endpoints(index: int) -> Dictionary:
	if (index < 0 || index >= curve_endpoints.size()):
		return {}
	
	return curve_endpoints[index]

func get_baked_curve_start(index: int) -> int:
	if (index < 0 || index >= curve_endpoints.size()):
		return -1
	
	return curve_endpoints[index].start

func get_baked_curve_end(index: int) -> int:
	if (index < 0 || index >= curve_endpoints.size()):
		return -1
	
	return curve_endpoints[index].end

func is_intersection(node_id: int) -> bool:
	if (node_id < 0):
		return false
	
	return intersection_nodes.has(node_id)

func get_intersections() -> Array:
	return intersection_nodes

func get_intersection_count() -> int:
	return intersection_nodes.size()

func get_intersection(index: int) -> Dictionary:
	if (index < 0 || index >= intersection_nodes.size()):
		return {}
	
	var node_id = intersection_nodes[index]
	return network_nodes[node_id]

func get_intersection_position(index: int) -> Vector3:
	if (index < 0 || index >= intersection_nodes.size()):
		return Vector3.ZERO
	
	var node_id = intersection_nodes[index]
	return network_nodes[node_id].position

func get_intersection_branch_count(index: int) -> int:
	if (index < 0 || index >= intersection_nodes.size()):
		return 0
	
	var node_id = intersection_nodes[index]
	var node_data = network_nodes[node_id]
	return node_data.next.size() + node_data.prev.size()

func get_intersection_curves(index: int) -> Array:
	if (index < 0 || index >= intersection_nodes.size()):
		return []
	
	return intersection_curves[index]

# Public methods
func clear_network() -> void:
	network_nodes = {}
	selected_node = -1
	baked_curves = []
	
	emit_signal("curves_changed")
	property_list_changed_notify()
	update_gizmo()

func are_controls_equal(prev_controls: Array, controls: Array) -> bool:
	if (prev_controls.size() == 0 && controls.size() == 0):
		return true
	if (prev_controls.size() != controls.size()):
		return false
	
	var i := 0
	for position in prev_controls:
		if (position != controls[i]):
			return false
		i += 1
	
	return true

## Node operations.
func get_next_id() -> int:
	# If the list is empty, the next ID is the first one.
	if (network_nodes.size() == 0):
		return 0
	
	# Find smallest available ID, looking for gaps (important for UndoRedo).
	var sorted_keys = network_nodes.keys()
	sorted_keys.sort()
	for i in sorted_keys[-1]:
		if (!network_nodes.has(i)):
			return i
	
	# If there are no gaps, take the biggest ID and increment it.
	return sorted_keys[-1] + 1

func get_affected_nodes() -> Dictionary:
	return _operation_affected_nodes

func try_add_node(position: Vector3, from_id: int = -1) -> bool:
	_operation_affected_nodes = {}
	
	var from_node
	if (from_id >= 0 && network_nodes.has(from_id)):
		# Check if the parent node has free branching slots (we only support up to 4 connections).
		from_node = network_nodes[from_id]
		if (from_node.prev.size() + from_node.next.size() >= 4):
			return false
		
		_add_affected_node(from_id, NodeOperation.NODE_UPDATED)
	
	_add_affected_node(get_next_id(), NodeOperation.NODE_ADDED)
	return true

func add_node(position: Vector3, from_id: int = -1) -> void:
	if (!try_add_node(position, from_id)):
		return
	
	var from_node
	if (from_id >= 0 && network_nodes.has(from_id)):
		from_node = network_nodes[from_id]
		# Zero out the branch handle, because it's been used up.
		from_node.branch_control = Vector3.ZERO
	
	# Create the node.
	var node_id = _create_new_node(position)
	var node_data = network_nodes[node_id]
	
	# Parent the new node to the parent node.
	if (from_node):
		_add_next_node(from_node, node_id)
		_add_prev_node(node_data, from_id)
	
	_update_curves()
	property_list_changed_notify()
	update_gizmo()

func try_remove_node(at_id: int) -> bool:
	_operation_affected_nodes = {}
	
	if (!network_nodes.has(at_id)):
		return false
	
	_add_affected_node(at_id, NodeOperation.NODE_REMOVED)
	
	var node_data = network_nodes[at_id]
	for from_id in node_data.prev:
		_add_affected_node(from_id, NodeOperation.NODE_UPDATED)
	for to_id in node_data.next:
		_add_affected_node(to_id, NodeOperation.NODE_UPDATED)
	
	return true

func remove_node(at_id: int) -> void:
	if (!try_remove_node(at_id)):
		return
	
	# Remove the node from its parent connections.
	var node_data = network_nodes[at_id]
	for from_id in node_data.prev:
		if (!network_nodes.has(from_id)):
			continue
		
		var from_node = network_nodes[from_id]
		if (from_node.next.has(at_id)):
			_remove_next_node(from_node, at_id)
	
	# Spread the nodes parented to this node between its parent connections.
	for to_id in node_data.next:
		if (!network_nodes.has(to_id)):
			continue
		
		var to_node = network_nodes[to_id]
		if (to_node.prev.has(at_id)):
			_remove_prev_node(to_node, at_id)
		
		for from_id in node_data.prev:
			if (!network_nodes.has(from_id)):
				continue
			
			var from_node = network_nodes[from_id]
			if (from_node.prev.size() + from_node.next.size() >= 4):
				continue
			
			_add_next_node(from_node, to_id)
			_add_prev_node(to_node, from_id)
			break
	
	# Move selection to the next available node.
	if (selected_node == at_id):
		if (node_data.prev.size() > 0):
			selected_node = node_data.prev[0]
		elif (node_data.next.size() > 0):
			selected_node = node_data.next[0]
		elif (network_nodes.size() > 0):
			selected_node = network_nodes.keys()[network_nodes.size() - 1]
		else:
			selected_node = -1
	# Remove the node from the network.
	network_nodes.erase(at_id)
	
	_update_curves()
	property_list_changed_notify()
	update_gizmo()

func try_split_path(from_id: int, to_id: int, position: Vector3) -> bool:
	_operation_affected_nodes = {}
	
	if (!network_nodes.has(from_id) || !network_nodes.has(to_id)):
		return false
	
	# Check if the nodes are actually connected.
	var from_node = network_nodes[from_id]
	var to_node = network_nodes[to_id]
	if (!from_node.next.has(to_id) || !to_node.prev.has(from_id)):
		return false
	
	_add_affected_node(get_next_id(), NodeOperation.NODE_ADDED)
	_add_affected_node(from_id, NodeOperation.NODE_UPDATED)
	_add_affected_node(to_id, NodeOperation.NODE_UPDATED)
	
	return true

func split_path(from_id: int, to_id: int, position: Vector3) -> void:
	if (!try_split_path(from_id, to_id, position)):
		return
	
	var node_id = _create_new_node(position)
	var node_data = network_nodes[node_id]
	
	# Inject the new node in between the existing nodes in the hierarchy.
	_add_prev_node(node_data, from_id)
	_add_next_node(node_data, to_id)
	
	var from_node = network_nodes[from_id]
	_remove_next_node(from_node, to_id)
	_add_next_node(from_node, node_id)
	
	var to_node = network_nodes[to_id]
	_remove_prev_node(to_node, from_id)
	_add_prev_node(to_node, node_id)
	
	_update_curves()
	property_list_changed_notify()
	update_gizmo()

func try_remove_path(from_id: int, to_id: int) -> bool:
	_operation_affected_nodes = {}
	
	if (!network_nodes.has(from_id) || !network_nodes.has(to_id)):
		return false
	
	# Check if the nodes are actually connected.
	var from_node = network_nodes[from_id]
	var to_node = network_nodes[to_id]
	if (!from_node.next.has(to_id) || !to_node.prev.has(from_id)):
		return false
	
	_add_affected_node(from_id, NodeOperation.NODE_UPDATED)
	_add_affected_node(to_id, NodeOperation.NODE_UPDATED)
	
	return true

func remove_path(from_id: int, to_id: int) -> void:
	if (!try_remove_path(from_id, to_id)):
		return
	
	var from_node = network_nodes[from_id]
	var to_node = network_nodes[to_id]
	
	# Erase the connection between the nodes.
	_remove_next_node(from_node, to_id)
	_remove_prev_node(to_node, from_id)
	
	_update_curves()
	update_gizmo()

func try_connect_path(from_id: int, to_id: int) -> bool:
	_operation_affected_nodes = {}
	
	if (!network_nodes.has(from_id) || !network_nodes.has(to_id)):
		return false
	
	var from_node = network_nodes[from_id]
	var to_node = network_nodes[to_id]
	
	# Check if the nodes are already connected.
	if (from_id == to_id):
		return false
	if (from_node.next.has(to_id) || from_node.prev.has(to_id) || to_node.next.has(from_id) || to_node.prev.has(from_id)):
		return false
	
	# Check if both nodes have free branch slots (we only support up to 4 connections per node).
	if (to_node.prev.size() + to_node.next.size() >= 4 || from_node.prev.size() + from_node.next.size() >= 4):
		return false
	
	_add_affected_node(from_id, NodeOperation.NODE_UPDATED)
	_add_affected_node(to_id, NodeOperation.NODE_UPDATED)
	
	return true

func connect_path(from_id: int, to_id: int) -> void:
	if (!try_connect_path(from_id, to_id)):
		return
	
	var from_node = network_nodes[from_id]
	var to_node = network_nodes[to_id]
	
	# Connect the nodes.
	_add_next_node(from_node, to_id)
	_add_prev_node(to_node, from_id)
	
	_update_curves()
	update_gizmo()

func restore_node_states(node_states: Dictionary) -> void:
	for node_id in node_states:
		var node_state = node_states[node_id]
		
		# The actions are the opposite of what we need to do to restore the state.
		if (node_state.action == NodeOperation.NODE_REMOVED || node_state.action == NodeOperation.NODE_UPDATED):
			network_nodes[node_id] = node_state.data
		elif (node_state.action == NodeOperation.NODE_ADDED):
			network_nodes.erase(node_id)
	
	_update_curves()
	property_list_changed_notify()
	update_gizmo()

func select_node(node_id: int) -> void:
	if (!network_nodes.has(node_id)):
		return
	
	selected_node = node_id
	update_gizmo()

func deselect_node() -> void:
	selected_node = -1
	update_gizmo()

func set_node_position(node_id: int, position: Vector3, in_controls: Array, out_controls: Array) -> void:
	if (!network_nodes.has(node_id)):
		return
	
	var node_data = network_nodes[node_id]
	node_data.position = position
	node_data.in_controls = in_controls
	node_data.out_controls = out_controls
	
	_update_curves()
	update_gizmo()

func set_control_position(node_id: int, control_index: int, position: Vector3) -> void:
	set_node_control(node_id, control_index, position)
	
	_update_curves()
	update_gizmo()

func set_node_origin(node_id: int, origin_rotation: float, origin_radius: float) -> void:
	if (!network_nodes.has(node_id)):
		return
	
	var node_data = network_nodes[node_id]
	node_data.origin_rotation = origin_rotation
	node_data.origin_radius = origin_radius
	
	_update_curves()
	update_gizmo()

func _add_affected_node(node_id: int, action: int) -> void:
	var node_data := {}
	if (network_nodes.has(node_id)):
		node_data = network_nodes[node_id].duplicate(true)
		node_data.branch_control = Vector3.ZERO # This should not be preserved.
	
	_operation_affected_nodes[node_id] = {
		"action": action,
		"data": node_data,
	}

## Unified node iteration routine.
func start_node_iterating() -> void:
	_iterator_head_id = -1
	_iterator_branch_idx = -1
	_iterator_branch_node = -1
	_iterator_stack = []
	_iterator_cheat_visit_ids = []
	
	# Take the entire pool of IDs, as we need to cover disconnected curves and dangling nodes as well.
	_iterator_unvisited_ids = network_nodes.keys()

func get_next_head() -> int:
	_print_verbose("Getting next head...")
	# Reset branching index for the next branch we visit.
	_iterator_branch_idx = -1
	
	# If we have branching nodes to consider, use them.
	if (_iterator_stack.size() > 0):
		_iterator_head_id = _iterator_stack.pop_front()
		_print_verbose("%d" % _iterator_head_id)
		return _iterator_head_id
	
	# If there are no more unvisited nodes left, return.
	if (_iterator_unvisited_ids.size() == 0):
		_print_verbose("%d" % -1)
		return -1
	
	# Process unvisited nodes to find the next interesting node.
	
	# First we consider parts of the network which have deadend branches (nodes with no parent).
	# This would also cover all the dangling nodes.
	var deadend_id = _iter_get_next_deadend()
	if (deadend_id >= 0):
		_iterator_unvisited_ids.erase(deadend_id)
		_iterator_head_id = deadend_id
		_print_verbose("%d" % _iterator_head_id)
		return _iterator_head_id
	
	# Next we consider the remaining parts of the network, those would be completely enclosed/looping.
	# We try to find an intersection node for a natural start of any curve.
	var intersection_id = _iter_get_next_intersection()
	if (intersection_id >= 0):
		_iterator_unvisited_ids.erase(intersection_id)
		_iterator_head_id = intersection_id
		_print_verbose("%d" % _iterator_head_id)
		return _iterator_head_id
	
	# If nothing else, we just start at an arbitrary node, as it's going to loop anyway.
	_iterator_head_id = _iterator_unvisited_ids.pop_front()
	_print_verbose("%d" % _iterator_head_id)
	return _iterator_head_id

func get_next_branch() -> int:
	_print_verbose("	Getting next branch...")
	_iterator_branch_idx += 1
	var head_data = network_nodes[_iterator_head_id]
	
	# There are no branches to follow from here.
	if (head_data.next.size() == 0 || head_data.next.size() <= _iterator_branch_idx):
		_print_verbose("	%d" % -1)
		return -1
	
	# Check if the next available branch exists, and move to the next one if it doesn't.
	var next_id = head_data.next[_iterator_branch_idx]
	if (!network_nodes.has(next_id)):
		return get_next_branch()
	
	# Check if we have already visited it, and move to the next one if we did.
	if (!_iterator_unvisited_ids.has(next_id)):
		return get_next_branch()
	
	# Move to the next branch and remove it from the unvisited list.
	_iterator_branch_node = next_id
	_iterator_unvisited_ids.erase(_iterator_branch_node)
	
	_print_verbose("	%d" % _iterator_branch_node)
	return _iterator_branch_node

func get_next_node() -> int:
	_print_verbose("		Getting next node...")
	# This was a cheat visit, we already know this node is used up.
	if (_iterator_cheat_visit_ids.has(_iterator_branch_node)):
		_iterator_cheat_visit_ids.erase(_iterator_branch_node)
		_print_verbose("		%d" % -1)
		return -1
	
	var node_data = network_nodes[_iterator_branch_node]
	
	# There are no nodes to follow from here.
	if (node_data.next.size() == 0):
		_print_verbose("		%d" % -1)
		return -1
	
	# We reached an intersection, return.
	if (node_data.next.size() + node_data.prev.size() > 2):
		# If it hasn't been fully explored, add the node to the stack to be considered later.
		if (!_iter_check_if_intersection_explored(_iterator_branch_node)):
			_iterator_stack.append(_iterator_branch_node)
		_print_verbose("		%d" % -1)
		return -1
	
	# Check if the next available node exists, and return if it doesn't.
	var next_id = node_data.next[0]
	if (!network_nodes.has(next_id)):
		_print_verbose("		%d" % -1)
		return -1
	
	# Check if we have already visited it, mark it for a cheat visit and remove on the next iteration.
	# A cheat visit is required for consistency and loops.
	if (!_iterator_unvisited_ids.has(next_id)):
		_iterator_cheat_visit_ids.append(next_id)
	else:
		# Don't forget to remove the node from the unvisited list.
		_iterator_unvisited_ids.erase(_iterator_branch_node)
	
	# Move to the next node.
	_iterator_branch_node = next_id
	_print_verbose("		%d" % _iterator_branch_node)
	return _iterator_branch_node

func _iter_get_next_deadend() -> int:
	_print_verbose("Looking for deadend...")
	for node_id in _iterator_unvisited_ids:
		var node_data = network_nodes[node_id]
		if (node_data.prev.size() == 0):
			return node_id
	
	return -1

func _iter_get_next_intersection() -> int:
	_print_verbose("Looking for intersection...")
	for node_id in _iterator_unvisited_ids:
		var node_data = network_nodes[node_id]
		if (node_data.next.size() + node_data.prev.size() > 2):
			return node_id
	
	return -1

func _iter_check_if_intersection_explored(node_id: int) -> bool:
	_print_verbose("Checking if intersection was explored...")
	var node_data = network_nodes[node_id]
	
	# If there is at least one unvisited branch, we haven't explored it properly yet.
	for node_id in node_data.next:
		if (_iterator_unvisited_ids.has(node_id)):
			return false
	
	return true

# Helpers
func _create_new_node(position: Vector3, in_controls: Array = [], out_controls: Array = []) -> int:
	var node_data := {
		"position": position,
		"in_controls": in_controls,
		"out_controls": out_controls,
		
		"origin_rotation": 0.0,
		"origin_radius": 1.0,
		
		"next": [],
		"prev": [],
		
		"branch_control": Vector3.ZERO, # Don't set, only used temporary when dragging the handle.
	}
	var node_id = get_next_id()
	
	# Add and select the node, as it's the latest and most relevant.
	network_nodes[node_id] = node_data
	selected_node = node_id
	
	return node_id

func _add_prev_node(node_data: Dictionary, prev_node_id: int) -> void:
	if (!network_nodes.has(prev_node_id)):
		return
	if (node_data.prev.size() + node_data.next.size() >= 4):
		return
	
	node_data.prev.append(prev_node_id)
	node_data.in_controls.append(Vector3.ZERO)

func _remove_prev_node(node_data: Dictionary, prev_node_id: int) -> void:
	if (!node_data.prev.has(prev_node_id)):
		return
	
	# TODO: Handle cases where the node is removed to be replaced better.
	# If we are going to replace the node in the same operation, keep the control
	# handle.
	
	var index = node_data.prev.find(prev_node_id)
	node_data.prev.erase(prev_node_id)
	node_data.in_controls.remove(index)

func _add_next_node(node_data: Dictionary, next_node_id: int) -> void:
	if (!network_nodes.has(next_node_id)):
		return
	if (node_data.prev.size() + node_data.next.size() >= 4):
		return
	
	node_data.next.append(next_node_id)
	node_data.out_controls.append(Vector3.ZERO)

func _remove_next_node(node_data: Dictionary, next_node_id: int) -> void:
	if (!node_data.next.has(next_node_id)):
		return
	
	# TODO: Handle cases where the node is removed to be replaced better.
	# If we are going to replace the node in the same operation, keep the control
	# handle.
	
	var index = node_data.next.find(next_node_id)
	node_data.next.erase(next_node_id)
	node_data.out_controls.remove(index)

func _update_curves() -> void:
	baked_curves = []
	curve_endpoints = []
	
	# Return early if there are no nodes on the network and so no point to do anything.
	if (network_nodes.size() == 0):
		emit_signal("curves_changed")
		return
	
	# Iterate over all available nodes, looking for starting points and building curves from there.
	# Single node curves are also possible, but maybe should be excluded.
	start_node_iterating()
	
	# Keep iterating until there are no starting/head nodes left (at which point every node should have been looked at).
	var head_id = get_next_head()
	while (head_id >= 0):
		var head_data = network_nodes[head_id]
		
		var branch_id = get_next_branch()
		while (branch_id >= 0):
			# For each branch of the node start a new curve.
			var current_curve = Curve3D.new()
			# Node itself is the first point.
			# In control doesn't matter for the first node, and out control needs
			# the next node to be figured out. It will be set later as we iterate.
			var in_control = Vector3.ZERO
			var out_control = Vector3.ZERO
			current_curve.add_point(head_data.position, in_control, out_control)
			
			var node_id = branch_id
			var last_node_id = head_id
			var node_sequence := [ last_node_id ]
			
			while (node_id >= 0):
				var node_data = network_nodes[node_id]
				
				# Set the out control for the previous point.
				var last_out_control = _get_node_inout_control(last_node_id, node_id)
				current_curve.set_point_out(current_curve.get_point_count() - 1, last_out_control)
				
				# Find the in control for this node. The out control will be set on
				# the next iteration. For the last node it wouldn't matter.
				in_control = _get_node_inout_control(node_id, last_node_id)
				out_control = Vector3.ZERO
				current_curve.add_point(node_data.position, in_control, out_control)
				
				last_node_id = node_id
				node_sequence.append(last_node_id)
				node_id = get_next_node()
			
			# Store the curve after iterating its nodes.
			# If the split option is enabled and the curve is long enough, cut it in chunks.
			if (split_curves && current_curve.get_point_count() > (split_size + 1)):
				var first_split_point = node_sequence[0]
				var split_curve := Curve3D.new()
				
				for i in current_curve.get_point_count():
					split_curve.add_point(current_curve.get_point_position(i), current_curve.get_point_in(i), current_curve.get_point_out(i))
					
					if (i % split_size == 0):
						baked_curves.append(split_curve)
						curve_endpoints.append({
							"start": first_split_point,
							"end": node_sequence[i],
						})
						
						first_split_point = i + 1
						split_curve = Curve3D.new()
						split_curve.add_point(current_curve.get_point_position(i), current_curve.get_point_in(i), current_curve.get_point_out(i))
				
				if (split_curve.get_point_count() > 1):
					baked_curves.append(split_curve)
					curve_endpoints.append({
						"start": first_split_point,
						"end": node_sequence[-1],
					})
			
			else:
				baked_curves.append(current_curve)
				curve_endpoints.append({
					"start": head_id,
					"end": last_node_id,
				})
			
			# And move to the next branch.
			branch_id = get_next_branch()
		
		head_id = get_next_head()
	
	_update_intersections()
	emit_signal("curves_changed")

func _update_intersections() -> void:
	intersection_nodes = []
	intersection_curves = []
	
	for node_id in network_nodes:
		var node_data = network_nodes[node_id]
		
		var branch_count = node_data.next.size() + node_data.prev.size()
		if (branch_count > 2):
			intersection_nodes.append(node_id)
			
			# Create curves for each branch of the intersection.
			var curves := []
			
			for i in node_data.prev.size():
				var prev_node_id = node_data.prev[i]
				var prev_node_data = network_nodes[prev_node_id]
				
				var curve = Curve3D.new()
				# For the previous node we start from the outside.
				var out_control = _get_node_inout_control(node_id, prev_node_id)
				var in_control = _get_node_inout_control(prev_node_id, node_id)
				curve.add_point(node_data.position, Vector3.ZERO, out_control)
				curve.add_point(prev_node_data.position, in_control, Vector3.ZERO)
				curves.append(curve)
			
			for i in node_data.next.size():
				var next_node_id = node_data.next[i]
				var next_node_data = network_nodes[next_node_id]
				
				var curve = Curve3D.new()
				# For the next node we start from the inside.
				var out_control = _get_node_inout_control(node_id, next_node_id)
				var in_control = _get_node_inout_control(next_node_id, node_id)
				curve.add_point(node_data.position, Vector3.ZERO, out_control)
				curve.add_point(next_node_data.position, in_control, Vector3.ZERO)
				curves.append(curve)
			
			# Sort the curves using clockwise direction and their angle to -Z as the starting value.
			curves.sort_custom(self, "_sort_intersection_curves")
			intersection_curves.append(curves)

func _get_node_inout_control(in_node_id: int, for_node_id: int) -> Vector3:
	if (!network_nodes.has(in_node_id) || !network_nodes.has(for_node_id)):
		return Vector3.ZERO
	
	# Control handles are always used in the prev-next order.
	var node_data = network_nodes[in_node_id]
	
	if (node_data.prev.has(for_node_id)):
		var index = node_data.prev.find(for_node_id)
		if (index >= 0 && index < node_data.in_controls.size()):
			return node_data.in_controls[index]
	
	if (node_data.next.has(for_node_id)):
		var index = node_data.next.find(for_node_id)
		if (index >= 0 && index < node_data.out_controls.size()):
			return node_data.out_controls[index]
	
	return Vector3.ZERO

func _get_ordered_node_controls(node_data: Dictionary, from_control_index: int) -> Array:
	var unsorted_angles := []
	var index_offset := 0
	
	# Take all previous nodes and calculate their angles.
	for index in node_data.prev.size():
		var prev_id = node_data.prev[index]
		var prev_data = network_nodes[prev_id]
		var prev_angle = _get_intersection_branch_angle(node_data.position, prev_data.position)
		
		unsorted_angles.append({
			"index": index + index_offset,
			"angle": prev_angle,
		})
	index_offset += node_data.prev.size()
	
	# Take all following nodes and calculate their angles.
	for index in node_data.next.size():
		var next_id = node_data.next[index]
		var next_data = network_nodes[next_id]
		var next_angle = _get_intersection_branch_angle(node_data.position, next_data.position)
		
		unsorted_angles.append({
			"index": index + index_offset,
			"angle": next_angle,
		})
	
	# Sort the data using the angles calculated before, then collect only ordered indices.
	unsorted_angles.sort_custom(self, "_sort_node_controls")
	var sorted_indices := []
	for angle_data in unsorted_angles:
		sorted_indices.append(angle_data.index)
	
	# If the starting index is at either end, just cut it off and proceed.
	if (from_control_index == sorted_indices[0] || from_control_index == sorted_indices[-1]):
		sorted_indices.erase(from_control_index)
	
	# If the index is in the middle, however, split the array into two parts and stitch them
	# back together in the reverse order (omitting the starting index).
	else:
		var split_index = sorted_indices.find(from_control_index)
		var first_part = sorted_indices.slice(split_index + 1, sorted_indices.size() - 1, 1)
		sorted_indices.resize(split_index)
		sorted_indices = first_part + sorted_indices
	
	return sorted_indices

func _sort_intersection_curves(curve_a: Curve3D, curve_b: Curve3D) -> bool:
	var angle_a = _get_intersection_branch_angle(curve_a.get_point_position(0), curve_a.get_point_position(1))
	var angle_b = _get_intersection_branch_angle(curve_b.get_point_position(0), curve_b.get_point_position(1))
	
	if (angle_b < angle_a):
		return true
	return false

func _sort_node_controls(data_a: Dictionary, data_b: Dictionary) -> bool:
	if (data_b.angle < data_a.angle):
		return true
	return false

func _get_intersection_branch_angle(from_position: Vector3, ref_position: Vector3) -> float:
	var branch_position = ref_position - from_position
	var handle_position = Vector2(branch_position.x, branch_position.z)
	
	var branch_angle = handle_position.angle_to(Vector2(0, -1))
	if (branch_angle > 0):
		branch_angle -= TAU
	
	return branch_angle

func _rotate_handle_around_node(from_position: Vector3, degrees: float) -> Vector3:
	var rotated_position = from_position.rotated(Vector3(0, 1, 0), deg2rad(degrees))
	var mirrored_position = -from_position
	var interpolated_y = lerp(from_position.y, mirrored_position.y, abs(degrees / 180.0))
	
	return Vector3(rotated_position.x, interpolated_y, rotated_position.z)

func _print_verbose(message: String = "") -> void:
	if (!enable_verbose_print || !Engine.editor_hint):
		return
	
	print(message)
