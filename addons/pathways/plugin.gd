tool
extends EditorPlugin

# Private properties
var _edited_network : PathwayNetwork

const THEME_TYPE : String = "PathwaysPlugin"

# Plugins
const PathwayNetworkGizmoPlugin : GDScript = preload("res://addons/pathways/plugins/PathwayNetworkGizmoPlugin.gd")
const PathwayNetworkSpatialToolbar : GDScript = preload("res://addons/pathways/plugins/PathwayNetworkSpatialToolbar.gd")
const PathwayPieceInspectorPlugin : GDScript = preload("res://addons/pathways/plugins/PathwayPieceInspectorPlugin.gd")

# Private properties
var _pathway_network_gizmo : EditorSpatialGizmoPlugin
var _pathway_network_toolbar : HBoxContainer
var _pathway_piece_inspector : EditorInspectorPlugin

func _enter_tree() -> void:
	_register_theme()
	
	_pathway_network_gizmo = PathwayNetworkGizmoPlugin.new(self)
	add_spatial_gizmo_plugin(_pathway_network_gizmo)
	
	_pathway_network_toolbar = PathwayNetworkSpatialToolbar.new()
	_pathway_network_toolbar.hide()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _pathway_network_toolbar)
	_pathway_network_toolbar.connect("network_clear_requested", self, "_on_network_clear_requested")
	
	_pathway_piece_inspector = PathwayPieceInspectorPlugin.new()
	add_inspector_plugin(_pathway_piece_inspector)

func _exit_tree() -> void:
	remove_spatial_gizmo_plugin(_pathway_network_gizmo)
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _pathway_network_toolbar)
	_pathway_network_toolbar.queue_free()
	
	remove_inspector_plugin(_pathway_piece_inspector)
	
	_unregister_theme()

func _register_theme() -> void:
	var base_control = get_editor_interface().get_base_control()
	var editor_theme = base_control.theme
	if (!editor_theme):
		return
	
	editor_theme.set_color("network_lines", THEME_TYPE, Color(0.67, 0.89, 0.1, 0.25))
	editor_theme.set_color("control_lines", THEME_TYPE, Color(0.517, 0.694, 1.0, 0.45))
	editor_theme.set_color("baked_lines", THEME_TYPE, Color(0.89, 0.67, 0.1))
	editor_theme.set_color("intersection_lines", THEME_TYPE, Color(0.89, 0.1, 0.67))
	editor_theme.set_color("intersection_areas", THEME_TYPE, Color(0.92, 0.39, 0.58, 0.25))
	
	editor_theme.set_icon("node_handle", THEME_TYPE, preload("res://addons/pathways/icons/node_handle_default.png"))
	editor_theme.set_icon("node_handle_selected", THEME_TYPE, preload("res://addons/pathways/icons/node_handle_selected.png"))
	editor_theme.set_icon("node_handle_add", THEME_TYPE, preload("res://addons/pathways/icons/node_handle_add.png"))
	editor_theme.set_icon("control_handle", THEME_TYPE, preload("res://addons/pathways/icons/control_handle_default.png"))
	editor_theme.set_icon("intersection_handle", THEME_TYPE, preload("res://addons/pathways/icons/intersection_handle_default.png"))
	editor_theme.set_icon("piece_arrow", THEME_TYPE, preload("res://addons/pathways/icons/piece_orientation_arrow.png"))

func _unregister_theme() -> void:
	var base_control = get_editor_interface().get_base_control()
	var editor_theme = base_control.theme
	if (!editor_theme):
		return
	
	var colors = editor_theme.get_color_list(THEME_TYPE)
	for item in colors:
		editor_theme.clear_color(item, THEME_TYPE)
	
	var constants = editor_theme.get_constant_list(THEME_TYPE)
	for item in constants:
		editor_theme.clear_constant(item, THEME_TYPE)
	
	var fonts = editor_theme.get_font_list(THEME_TYPE)
	for item in fonts:
		editor_theme.clear_font(item, THEME_TYPE)
	
	var icons = editor_theme.get_icon_list(THEME_TYPE)
	for item in icons:
		editor_theme.clear_icon(item, THEME_TYPE)
	
	var styleboxes = editor_theme.get_stylebox_list(THEME_TYPE)
	for item in styleboxes:
		editor_theme.clear_stylebox(item, THEME_TYPE)

# Implementation
func handles(object: Object) -> bool:
	return object is PathwayNetwork

func edit(object: Object) -> void:
	if (object is PathwayNetwork):
		_edited_network = object
		_pathway_network_gizmo.edit_network(object)
	else:
		_edited_network = null
		_pathway_network_gizmo.edit_network(null)

func make_visible(visible: bool) -> void:
	_pathway_network_toolbar.visible = visible
	if (!visible):
		_edited_network = null
		_pathway_network_gizmo.edit_network(null)

# Spatial hooks
func forward_spatial_draw_over_viewport(overlay: Control) -> void:
	_pathway_network_gizmo.draw_over_viewport(overlay)

func forward_spatial_gui_input(camera: Camera, event: InputEvent) -> bool:
	return _pathway_network_gizmo.handle_gui_input(camera, event)

# Handlers
func _on_network_clear_requested() -> void:
	if (!_edited_network || !is_instance_valid(_edited_network)):
		return
	
	_edited_network.clear_network()
