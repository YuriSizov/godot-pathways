extends EditorInspectorPlugin

# Scene references
const pathway_piece_preview : PackedScene = preload("res://addons/pathways/ui/PathwayPiecePreview.tscn")

func can_handle(object: Object) -> bool:
	return object is PathwayPiece

func parse_begin(object: Object) -> void:
	var piece = object as PathwayPiece
	if (!piece):
		return
	
	var preview = pathway_piece_preview.instance()
	preview.pathway_piece = piece
	add_custom_control(preview)
