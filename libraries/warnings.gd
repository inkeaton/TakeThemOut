class_name Warnings extends RefCounted

static func print_warning(message : String, origin : String):
	# Print the colored text
	print_rich("[color=Goldenrod][b][WARNING][/b] - from [u]%s[/u][/color]: %s" % [origin, message])
	# Also push to the Godot Debugger tab so you don't miss it
	push_warning("%s: %s" % [origin, message])

static func not_defined(method_name : String, origin : String):
	print_warning("Il metodo astratto \"[u]%s()[/u]\" non è stato ridefinito" % method_name, origin)
