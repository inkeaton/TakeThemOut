class_name Messages extends RefCounted

static func print_message(message: String, origin: String):
	# Using %s format is cleaner than many + + +
	print_rich("[color=Greenyellow][b][MESSAGE][/b] - from [u]%s[/u][/color]: %s" % [origin, message])

static func print_variable(variable, variable_name: String, origin: String):
	var val_str = var_to_str(variable)
	print_message("La variabile \"[u]%s[/u]\" ha valore: %s" % [variable_name, val_str], origin)
