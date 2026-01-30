class_name Crumb
extends Area2D

# When the crumb was created. Helps agents find the "next" one (newer).
var timestamp : int = 0

func _ready() -> void:
	timestamp = Time.get_ticks_msec()
	# Wait for 2.0 seconds, then call queue_free()
	get_tree().create_timer(10.0).timeout.connect(queue_free)
	
