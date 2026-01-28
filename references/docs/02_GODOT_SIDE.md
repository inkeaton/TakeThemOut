# VEsNA Framework - Godot Side Documentation

This document describes the Godot (body) side of the VEsNA framework, covering the GDScript implementation and scene setup required to connect agent bodies to their Jason minds.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Script: vesna.gd](#core-script-vesnagd)
3. [Message Protocol](#message-protocol)
4. [Scene Setup Requirements](#scene-setup-requirements)
5. [Environment Manager](#environment-manager)
6. [Extending the Body](#extending-the-body)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          GODOT ENGINE (Body)                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      CharacterBody3D (Agent)                           │ │
│  │                                                                        │ │
│  │  ┌─────────────────────┐    ┌─────────────────────────────────────┐   │ │
│  │  │    vesna.gd         │    │     NavigationAgent3D               │   │ │
│  │  │  - TCP Server       │    │   - Pathfinding                     │   │ │
│  │  │  - WebSocket Peer   │◄───┤   - Target tracking                 │   │ │
│  │  │  - Message handling │    │   - Navigation finished signals     │   │ │
│  │  │  - Action execution │    └─────────────────────────────────────┘   │ │
│  │  └─────────────────────┘                                              │ │
│  │           │                                                            │ │
│  │           ▼                                                            │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    Action Handlers                              │  │ │
│  │  │  - walk(target, id)     - Navigate to target                    │  │ │
│  │  │  - use(art_name)        - Use artifact                          │  │ │
│  │  │  - grab(art_name)       - Pick up artifact                      │  │ │
│  │  │  - release(art_name)    - Drop artifact                         │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │           │                                                            │ │
│  │           ▼                                                            │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                  Signal Back to Mind                            │  │ │
│  │  │  - signal_end_movement(status, reason)                          │  │ │
│  │  │  - signal_mind(type, data)                                      │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     NavigationRegion3D                                 │ │
│  │  - Navigation mesh                                                     │ │
│  │  - Region markers                                                      │ │
│  │  - Door connections                                                    │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     env_manager.gd (Optional)                          │ │
│  │  - Object spawning                                                     │ │
│  │  - Game logic                                                          │ │
│  │  - Notifying agents                                                    │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Script: vesna.gd

**Location:** `examples/coin-game/env/scripts/vesna.gd`

This script is attached to a `CharacterBody3D` node representing the agent's body in the game world.

### Essential Properties

```gdscript
extends CharacterBody3D

# Movement constants
const SPEED = 5.0
const ACCELERATION = 8.0
const JUMP_VELOCITY = 4.5

# Network configuration (set per agent in editor)
@export var PORT : int

# Network objects
var tcp_server := TCPServer.new()
var ws := WebSocketPeer.new()

# State tracking
var end_communication = true
var target_movement : String = "empty"
var global_target_node : Node3D
var global_target_pos : Vector3

# Node references
@onready var navigator : NavigationAgent3D = $NavigationAgent3D
@onready var jump_anim = $Body/Jump
@onready var idle_anim = $Body/Idle
@onready var run_anim = $Body/Run
```

### Initialization (_ready)

```gdscript
func _ready() -> void:
    # Start TCP server on the exported port
    if tcp_server.listen(PORT) != OK:
        push_error("Unable to start the server")
        set_process(false)
    
    # Start in idle animation
    play_idle()
```

### Main Loop (_process)

Handles incoming WebSocket connections and messages.

```gdscript
func _process(delta: float) -> void:
    # Accept new connections
    while tcp_server.is_connection_available():
        var conn : StreamPeerTCP = tcp_server.take_connection()
        assert(conn != null)
        ws.accept_stream(conn)
    
    # Poll WebSocket for new data
    ws.poll()
    
    # Process incoming messages
    if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
        while ws.get_available_packet_count():
            var msg : String = ws.get_packet().get_string_from_ascii()
            print("Received msg ", msg)
            var intention : Dictionary = JSON.parse_string(msg)
            manage(intention)
```

### Physics Loop (_physics_process)

Handles navigation and movement.

```gdscript
func _physics_process(delta: float) -> void:
    # Apply gravity
    if not is_on_floor():
        velocity += get_gravity() * delta
    
    # Handle navigation
    navigate(delta)
    
    # Handle collisions (game-specific logic)
    for i in range(get_slide_collision_count()):
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()
        # Process collisions...
```

### Navigation Function

```gdscript
func navigate(delta: float) -> void:
    if navigator.is_target_reached() or navigator.is_navigation_finished():
        # Stop and signal completion
        play_idle()
        velocity.x = 0
        velocity.z = 0
        if not end_communication:
            signal_end_movement('completed', 'destination_reached')
            
    elif not navigator.is_navigation_finished():
        # Continue moving toward target
        play_run()
        var final_direction = (navigator.get_next_path_position() - global_position).normalized()
        rotation.y = atan2(final_direction.x, final_direction.z)
        velocity = velocity.lerp(final_direction * SPEED, ACCELERATION * delta)
    
    move_and_slide()
```

### Message Handler (manage)

Routes incoming messages to appropriate action handlers.

```gdscript
func manage(intention : Dictionary) -> void:
    var sender : String = intention['sender']
    var receiver : String = intention['receiver']
    var type : String = intention['type']
    var data : Dictionary = intention['data']
    
    if type == 'walk':
        if data['type'] == 'goto':
            var target : String = data['target']
            if data.has('id'):
                var id : int = data['id']
                walk(target, id)
            else:
                walk(target, -1)
                
    elif type == 'interact':
        if data['type'] == 'use':
            use(data['art_name'])
        elif data['type'] == 'grab':
            grab(data['art_name'])
        elif data['type'] == 'free':
            free_art(data['art_name'])
        elif data['type'] == 'release':
            release(data['art_name'])
```

### Action Implementations

#### Walk Action

```gdscript
func walk(target, id):
    # Try to find target in NavigationRegion first
    var target_node = get_node_or_null("/root/Node3D/NavigationRegion3D/" + target)
    if not target_node:
        target_node = get_node_or_null("/root/Node3D/" + target)
    if not target_node:
        return
    
    # Set navigation target
    navigator.set_target_position(target_node.global_position)
    
    # Connect to target destroyed signal for dynamic targets
    target_node.connect("tree_exited", Callable(self, "_on_target_destroyed"))
    
    target_movement = target
    global_target_node = target_node
    play_run()
    end_communication = false
```

#### Grab Action

```gdscript
func grab(art_name: String):
    var art = get_obj_from_group(art_name, "GrabbableArtifact")
    if art == null:
        print("Object not found!")
        return
    
    # Attach to hand
    var right_hand = get_node_or_null("Body/Root/Skeleton3D/RightHand")
    if right_hand == null:
        print("No hand found!")
        return
    
    art.reparent(right_hand)
    art.transform.origin = Vector3.ZERO
```

#### Release Action

```gdscript
func release(art_name : String):
    # Find nearest release point
    var release_points = get_tree().get_nodes_in_group("ReleasePoint")
    var nearest_release
    var nearest_dist = 1000
    for release_point in release_points:
        var cur_dist = release_point.global_position.distance_to(global_position)
        if cur_dist < nearest_dist:
            nearest_release = release_point
            nearest_dist = cur_dist
    
    # Reparent artifact to release point
    var art = get_obj_from_group(art_name, "GrabbableArtifact")
    art.reparent(nearest_release)
    art.transform.origin = Vector3.ZERO
```

### Signaling the Mind

#### Signal End Movement

```gdscript
func signal_end_movement(status : String, reason : String) -> void:
    target_movement = "empty"
    var log : Dictionary = {}
    log['sender'] = 'body'
    log['receiver'] = 'vesna'
    log['type'] = 'signal'
    var msg : Dictionary = {}
    msg['type'] = 'movement'
    msg['status'] = status
    msg['reason'] = reason
    log['data'] = msg
    ws.send_text(JSON.stringify(log))
    end_communication = true
```

#### Generic Signal

```gdscript
func signal_mind(type: String, data: Dictionary):
    var log : Dictionary = {}
    log['sender'] = 'body'
    log['receiver'] = 'vesna'
    log['type'] = type
    log['data'] = data
    ws.send_text(JSON.stringify(log))
```

### Utility Functions

```gdscript
func get_obj_from_group(art_name : String, group_name : String):
    var group_objs = get_tree().get_nodes_in_group(group_name)
    for group_obj in group_objs:
        if art_name == group_obj.name:
            return group_obj
    return null

func play_idle() -> void:
    if run_anim and run_anim.is_playing():
        run_anim.stop()
    idle_anim.play("Root|Idle")

func play_run() -> void:
    if idle_anim.is_playing():
        idle_anim.stop()
    run_anim.play("Root|Run")
```

### Cleanup

```gdscript
func _exit_tree() -> void:
    ws.close()
    tcp_server.stop()
```

---

## Message Protocol

### Messages FROM Jason (Actions)

#### Walk Command

```json
{
    "sender": "alice",
    "receiver": "body",
    "type": "walk",
    "data": {
        "type": "goto",
        "target": "coffee_machine",
        "id": 123456789
    },
    "propensions": ["offensive", "curious"]
}
```

**Walk Data Types:**
- `"type": "step"` - Take a single step
- `"type": "goto"` - Navigate to target

#### Rotate Command

```json
{
    "sender": "alice",
    "receiver": "body",
    "type": "rotate",
    "data": {
        "type": "direction",
        "direction": "left"
    }
}
```

**Or for looking at target:**
```json
{
    "sender": "alice",
    "receiver": "body",
    "type": "rotate",
    "data": {
        "type": "lookat",
        "target": "enemy",
        "id": 987654321
    }
}
```

#### Jump Command

```json
{
    "sender": "alice",
    "receiver": "body",
    "type": "jump",
    "data": {}
}
```

#### Interact Command

```json
{
    "sender": "alice",
    "receiver": "body",
    "type": "interact",
    "data": {
        "type": "use | grab | free | release",
        "art_name": "artifact_name"
    }
}
```

### Messages TO Jason (Perceptions)

#### Movement Signal

```json
{
    "sender": "body",
    "receiver": "vesna",
    "type": "signal",
    "data": {
        "type": "movement",
        "status": "completed | stopped",
        "reason": "destination_reached | target_destroyed"
    }
}
```

**This triggers in ASL:**
```jason
+movement(completed, destination_reached)
+movement(stopped, target_destroyed)
```

#### Sight Perception

```json
{
    "sender": "body",
    "receiver": "vesna",
    "type": "sight",
    "data": {
        "sight": "enemy",
        "id": 123456789
    }
}
```

**This adds belief in ASL:**
```jason
sight(enemy, 123456789)
```

#### Custom Game Events (Coin Game Example)

```json
{
    "sender": "body",
    "receiver": "vesna",
    "type": "coin",
    "data": {
        "type": "spawn",
        "name": "coin(coin_42)",
        "midfield": "blue"
    }
}
```

```json
{
    "sender": "body",
    "receiver": "vesna",
    "type": "env",
    "data": {
        "type": "pos",
        "color": "red"
    }
}
```

---

## Scene Setup Requirements

### Minimum Node Structure

```
Root (Node3D)
├── NavigationRegion3D
│   ├── NavigationMesh
│   ├── Markers/
│   │   ├── waypoint1 (Node3D)
│   │   └── waypoint2 (Node3D)
│   └── Regions/
│       ├── room1 (Area3D)
│       └── room2 (Area3D)
├── Agent (CharacterBody3D) [vesna.gd attached]
│   ├── NavigationAgent3D
│   ├── CollisionShape3D
│   └── Body (Node3D)
│       ├── MeshInstance3D / Model
│       ├── Idle (AnimationPlayer)
│       ├── Run (AnimationPlayer)
│       └── Jump (AnimationPlayer)
└── Environment
    └── (Floor, Walls, Props, etc.)
```

### Agent Node Configuration

1. **CharacterBody3D**: Root node for the agent
   - Attach `vesna.gd` script
   - Set `PORT` export variable (unique per agent)

2. **NavigationAgent3D**: Child of CharacterBody3D
   - Configure path desired distance
   - Configure target desired distance

3. **CollisionShape3D**: For physics collision

4. **Body**: Visual representation
   - Animation players for Idle, Run, Jump

### NavigationRegion3D Setup

1. Create `NavigationMesh` covering walkable areas
2. Create child nodes for targets:
   - **Markers**: Named Node3D positions agents can walk to
   - **Regions**: Area3D nodes for region detection (optional)

### Groups Configuration

Add nodes to groups for easy lookup:

| Group Name | Purpose |
|------------|---------|
| `Agents` | All agent CharacterBody3D nodes |
| `GrabbableArtifact` | Objects that can be picked up |
| `ReleasePoint` | Locations where items can be dropped |
| `coins` | Game-specific collectibles |

---

## Environment Manager

**Location:** `examples/coin-game/env/scripts/env_manager.gd`

Optional script for managing game logic and spawning objects.

```gdscript
extends NavigationRegion3D

@export var scene_to_spawn: PackedScene
@export var spawn_area_min: Vector3 = Vector3(-5, 0, -4.5)
@export var spawn_area_max: Vector3 = Vector3(5, 5, 4.5)
@export var min_spawn_time: float = 10.0
@export var max_spawn_time: float = 20.0

var connected_players : int = 0
var total_players : int = 0

func _ready():
    spawn_loop()
    for player in get_tree().get_nodes_in_group("Agents"):
        if player.is_visible_in_tree():
            total_players += 1

func spawn_loop():
    var wait_time = randf_range(min_spawn_time, max_spawn_time)
    await get_tree().create_timer(wait_time).timeout
    spawn_object()
    spawn_loop()

func spawn_object():
    if not scene_to_spawn:
        return
    if not connected_players == total_players:
        return  # Wait for all agents to connect
    
    var instance = scene_to_spawn.instantiate()
    var rand_x = randf_range(spawn_area_min.x, spawn_area_max.x)
    var rand_z = randf_range(spawn_area_min.z, spawn_area_max.z)
    instance.global_transform.origin = Vector3(rand_x, 0.2, rand_z)
    add_child(instance)
    
    # Notify all agents about new object
    get_tree().call_group("Agents", "on_object_spawned", instance)

func connected_player():
    connected_players += 1
```

### Agent Callback for Spawned Objects

In `vesna.gd`:

```gdscript
func on_object_spawned(new_object):
    var log : Dictionary = {}
    log['sender'] = 'body'
    log['receiver'] = 'vesna'
    log['type'] = 'coin'
    var msg : Dictionary = {}
    msg['type'] = 'spawn'
    msg['name'] = 'coin(' + new_object.name + ')'
    if new_object.global_transform.origin.z < 0:
        msg['midfield'] = 'blue'
    else:
        msg['midfield'] = 'red'
    log['data'] = msg
    ws.send_text(JSON.stringify(log))
```

---

## Extending the Body

### Adding New Actions

1. **In Jason** (create internal action in `src/agt/vesna/via/`):

```java
public class attack extends DefaultInternalAction {
    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) {
        JSONObject data = new JSONObject();
        data.put("type", "melee");
        data.put("target", args[0].toString());
        
        JSONObject action = new JSONObject();
        action.put("sender", ts.getAgArch().getAgName());
        action.put("type", "attack");
        action.put("data", data);
        
        VesnaAgent ag = (VesnaAgent) ts.getAg();
        ag.perform(action.toString());
        return true;
    }
}
```

2. **In Godot** (extend `manage()` in `vesna.gd`):

```gdscript
func manage(intention : Dictionary) -> void:
    var type : String = intention['type']
    var data : Dictionary = intention['data']
    
    match type:
        'walk':
            # existing walk handling...
        'attack':
            perform_attack(data)

func perform_attack(data: Dictionary):
    var attack_type = data['type']
    var target_name = data['target']
    
    # Play attack animation
    # Deal damage to target
    # Send result back to mind
    
    signal_mind("signal", {
        "type": "attack",
        "status": "completed",
        "reason": "hit"
    })
```

### Adding Visual Perceptions

```gdscript
# Example: Detecting enemies in view cone
func _on_vision_area_body_entered(body):
    if body.is_in_group("Enemies"):
        var sight_data = {
            "sight": body.name,
            "id": body.get_instance_id()
        }
        signal_mind("sight", sight_data)
```

### Handling Dynamic Targets

```gdscript
func _on_target_destroyed():
    if not gained_coin:
        signal_end_movement('stopped', 'target_destroyed')
    gained_coin = false
```

---

## Summary

The Godot side of VEsNA provides:

1. **TCP/WebSocket Server**: Each agent body listens on a unique port
2. **Message Handling**: Parses JSON commands from Jason mind
3. **Navigation**: Uses `NavigationAgent3D` for pathfinding
4. **Action Execution**: Walk, grab, release, use artifacts
5. **Perception Signaling**: Reports movement completion, sights, and events back to mind
6. **Animation**: Switches between idle/run/jump based on state

**Key Points:**
- Each agent needs a **unique port** number
- Godot must be **running before** Jason agents start
- Use **groups** for easy node lookup (Agents, GrabbableArtifact, etc.)
- All communication uses **JSON** format
- Navigation relies on **NavigationRegion3D** with baked mesh
