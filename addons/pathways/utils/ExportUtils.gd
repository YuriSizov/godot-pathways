extends Object

static func get_enum_export_hint(enum_object: Dictionary) -> String:
	var hint_string := ""
	
	var i := 0
	for key in enum_object:
		if (i > 0):
			hint_string += ","
		
		hint_string += "%s:%d" % [ key.capitalize(), enum_object[key] ]
		
		i += 1
	
	return hint_string
