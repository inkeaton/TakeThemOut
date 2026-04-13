## Crumb: Lightweight trail marker dropped by the player for patrol tracking.
class_name Crumb
extends Area2D

# Timestamp used by patrols to identify newer trail points.
var timestamp : int = 0

func _ready() -> void:
	timestamp = Time.get_ticks_msec()
	# Auto-remove after a short lifetime.
	get_tree().create_timer(10.0).timeout.connect(queue_free)
	
