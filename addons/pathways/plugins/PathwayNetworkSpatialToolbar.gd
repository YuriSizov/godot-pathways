tool
extends HBoxContainer

# Node references
var _clear_network_button : Button

signal network_clear_requested()

func _init() -> void:
	add_child(VSeparator.new())
	var title_label = Label.new()
	title_label.text = "Pathways:"
	add_child(title_label)

	_clear_network_button = Button.new()
	_clear_network_button.flat = true
	_clear_network_button.text = "Clear Network"
	add_child(_clear_network_button)
	_clear_network_button.connect("pressed", self, "emit_signal", [ "network_clear_requested" ])
