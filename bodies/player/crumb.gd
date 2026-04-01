## Crumb: Lightweight trail marker dropped by the player for patrol tracking.
## Role: utility
## Responsibilities:
## - Store creation timestamp used by patrol tracking logic.
## - Self-destruct after a short lifetime to limit world clutter.
## Dependencies:
## - Consumed by patrol tracking state via group membership and timestamp reads.
class_name Crumb
extends Area2D

# Timestamp used by patrols to identify newer trail points.
var timestamp : int = 0

func _ready() -> void:
	timestamp = Time.get_ticks_msec()
	# Auto-remove after a short lifetime.
	get_tree().create_timer(10.0).timeout.connect(queue_free)
	
