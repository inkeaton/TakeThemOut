class_name Messages extends RefCounted

static func print_message(message: String, origin: String) -> void:
	print_rich("[color=Greenyellow][b][MESSAGE][/b] - from [u]%s[/u][/color]: %s" % [origin, message])

static func print_variable(variable, variable_name: String, origin: String) -> void:
	var val_str = var_to_str(variable)
	print_message("The variable \"[u]%s[/u]\" has value: %s" % [variable_name, val_str], origin)

## Pretty-prints a variable (Dictionary/Array) as formatted JSON.
static func print_json(data, origin: String = "Debug") -> void:
	# indent using 4 spaces ("    ")
	var json_text = JSON.stringify(data, "    ")
	
	# If stringify fails (returns empty string usually due to incompatible types like Vector2)
	# we fallback to standard string conversion to avoid printing nothing.
	if json_text == "":
		json_text = "[!JSON FAILED] Raw: " + str(data)
	
	print_rich("[color=Orange][b][JSON][/b] - from [u]%s[/u][/color]:\n%s" % [origin, json_text])
