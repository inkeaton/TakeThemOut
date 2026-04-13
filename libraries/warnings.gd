## Warnings: Centralized warning logger for rich console output and debugger visibility.
class_name Warnings extends RefCounted

# --- Warning Helpers ---
static func print_warning(message : String, origin : String):
	# Print colored warning text in the output console.
	print_rich("[color=Goldenrod][b][WARNING][/b] - from [u]%s[/u][/color]: %s" % [origin, message])
	# Mirror warning to the Godot Debugger panel.
	push_warning("%s: %s" % [origin, message])

# --- Abstract Contract Helper ---
static func not_defined(method_name : String, origin : String):
	print_warning("Abstract method \"[u]%s()[/u]\" was not overridden" % method_name, origin)
