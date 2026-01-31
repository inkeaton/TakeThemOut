# State.gd
class_name State
extends Node

# References injected by the StateMachine
var body: CharacterBody2D
var nav_agent: NavigationAgent2D
var vesna: VesnaManager
var state_machine: StateMachine

# Called when the state becomes active
# msg: Optional dictionary to pass data (e.g., {"points": 3} or {"patience": 5})
func enter(_msg: Dictionary = {}) -> void:
	pass

# Called when the state is replaced
func exit() -> void:
	pass

# Corresponds to _physics_process
func update_physics(_delta: float) -> void:
	pass

# Corresponds to _process (optional)
func update(_delta: float) -> void:
	pass
