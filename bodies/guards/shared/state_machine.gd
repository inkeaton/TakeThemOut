# StateMachine.gd
class_name StateMachine
extends Node

@export var initial_state: State
var current_state: State

# Dictionary to access states by name (e.g., states["Track"])
var states: Dictionary = {}

func init(target_body: CharacterBody2D, target_nav: NavigationAgent2D, target_vesna: VesnaManager) -> void:
	for child in get_children():
		if child is State:
			# Inject dependencies
			child.body = target_body
			child.nav_agent = target_nav
			child.vesna = target_vesna
			child.state_machine = self
			
			# Map state name to node (Case sensitive based on Node Name)
			states[child.name] = child

	if initial_state:
		change_state(initial_state)

func change_state(new_state_node: State, msg: Dictionary = {}) -> void:
	if current_state:
		current_state.exit()
	
	current_state = new_state_node
	current_state.enter(msg)

func change_state_by_name(state_name: String, msg: Dictionary = {}) -> void:
	if states.has(state_name):
		change_state(states[state_name], msg)
	else:
		push_error("StateMachine: State %s does not exist." % state_name)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.update_physics(delta)
