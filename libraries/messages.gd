class_name Messages extends RefCounted

#//////////////////////////////////////////////////////////////////////////////#

static func print_message(message: String, origin: String):
	print_rich("[color=Greenyellow][b]MESSAGE[/b] - from [u]" + origin + "[/u][/color]: " + message)
	
static func print_variable(variable, variable_name: String, origin: String):
	print_message("La variabile \"[u]" + variable_name + "[/u]\" ha valore: " + var_to_str(variable), origin)
