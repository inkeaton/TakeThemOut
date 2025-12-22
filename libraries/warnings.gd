class_name Warnings extends RefCounted

#//////////////////////////////////////////////////////////////////////////////#

static func print_warning(message : String, origin : String):
	print_rich("[color=Goldenrod][b]WARNING[/b] - from [u]" + origin + "[/u][/color]: " + message)

static func not_defined(method_name : String, origin : String):
	print_warning("Il metodo astratto \"[u]" + method_name + "()[/u]\" non è stato ridefinito", origin)
	
