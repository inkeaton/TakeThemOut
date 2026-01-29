# 06_PATROL_SETUP.md - Patrol Agent Configuration Guide

This document explains how to configure and deploy VEsNA-controlled patrol agents that navigate waypoints, detect and chase players, search for lost targets, and coordinate with other patrols.

## Architecture Overview

```
┌─────────────────────┐                    ┌─────────────────────┐
│   Godot Patrol      │◄──── WebSocket ────►│   Jason Patrol      │
│   (patrol.gd)       │       (PORT)        │   (patrol.asl)      │
├─────────────────────┤                    ├─────────────────────┤
│ • Navigation        │                    │ • state(patrolling/ │
│ • Vision cone       │                    │   chasing/searching)│
│ • Patience timer    │                    │ • Temper system     │
│ • LKP tracking      │                    │ • Waypoint loop     │
│ • VesnaManager      │                    │ • Chase logic       │
└─────────────────────┘                    └─────────────────────┘
         │                                          │
         ├──────────────────────────────────────────┤
         │        Player Detection & Chase           │
         │ 1. Body sees player (vision cone)         │
         │ 2. Sends sight(player, id)                │
         │ 3. Mind triggers vesna.chase(id)          │
         │ 4. Body chases to last known position     │
         │ 5. After 2s, sends signal(sight, lost)    │
         │ 6. Mind starts search behavior            │
         │ 7. Search completes, returns to patrol    │
         └──────────────────────────────────────────┘
```

## ⚠️ CRITICAL: Naming Convention

**The Godot node name MUST exactly match the Jason agent name** for inter-patrol communication.

**Important:** JaCaMo requires agent names to start with a lowercase letter (they're atoms in Prolog).

| Jason Config (vesna.jcm) | Godot Scene Node Name |
|--------------------------|----------------------|
| `agent patrol_lazy:patrol.asl` | Node named `patrol_lazy` |
| `agent patrol_angry:patrol.asl` | Node named `patrol_angry` |
| `agent patrol_north:patrol.asl` | Node named `patrol_north` |

## State Machine

The patrol agent transitions through these states:

```
[patrolling] ─→ sight(player, Id) ─→ [chasing]
     ▲                                    │
     │                          signal(sight, lost)
     │                                    │
     │         search_area complete       ▼
     └────────────────────── [searching]
```

## Step-by-Step Setup

### 1. Configure Jason Side (mind/vesna.jcm)

```jcm
agent patrol_lazy:patrol.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(laziness(0.9), aggressiveness(0.1))
    address:    localhost
    port:       9084                      // Unique port for each patrol
    beliefs:    waypoints(["M1_A", "M1_B", "M1_C", "M1_D"])  // Waypoint names as strings
    strategy:   most_similar
    goals:      start_patrol
}

agent patrol_angry:patrol.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(laziness(0.1), aggressiveness(0.9))
    address:    localhost
    port:       9085
    beliefs:    waypoints(["M2_A", "M2_B", "M2_C", "M2_D"])
    strategy:   most_similar
    goals:      start_patrol
}
```

**Key Points:**
- Each patrol agent needs a unique port
- Waypoint names **MUST be strings** (quoted) because they start with uppercase
- Waypoint names must match Godot Marker2D node names under `/root/SCENE_NAME/waypoints/`
- `strategy: most_similar` enables the temper system for personality-based plan selection
- `goals: start_patrol` automatically triggers patrol when agent starts

### 2. Configure Godot Side

For each patrol in your scene:

1. **Set Node Name**: Rename the CharacterBody2D node to match the Jason agent name (e.g., `patrol_lazy` - lowercase)

2. **Set Port**: In the Inspector, set `VesnaManager.PORT` to match the port in `vesna.jcm`

3. **Add to Group**: Add the node to the `"patrols"` group (Project → Groups → Add) - used for coordination

4. **Create Waypoints**: In the scene, create a `waypoints` Node2D with Marker2D children:
   ```
   waypoints (Node2D)
   ├── M1_A (Marker2D) at position (-740, -479)
   ├── M1_B (Marker2D) at position (88, -473)
   ├── M1_C (Marker2D) at position (-5, 425)
   └── M1_D (Marker2D) at position (-711, 255)
   ```

5. **Configure NavigationAgent2D**:
   - Set `path_desired_distance = 10.0`
   - Set `target_desired_distance = 10.0`
   - Ensure a `NavigationRegion2D` with `NavigationPolygon` exists in the scene

### 3. Example Scene Structure

```
patrol_lazy (CharacterBody2D)      # Name matches Jason agent (lowercase!)
├── Sprite
├── CollisionShape2D
├── VisionCone (Area2D)
│   └── CollisionPolygon2D          # Detection wedge
├── NavigationAgent2D               # Handles pathfinding
├── PatienceTimer (Timer)           # Waits 2s after losing sight
├── DebugLabel (Label)              # Shows current state
└── VesnaManager                    # PORT = 9084
```

### 4. Collision Layers Setup

| Layer | Name | Used By |
|-------|------|---------|
| 2 | Player | Player body |
| 4 | Vision | Vision cones (layer 4) |

**VisionCone**: 
- `collision_layer = 16` (layer 4)
- `collision_mask = 6` (detects layers 2 (Player) and 4)
- Polygon: `[900, -370], [900, 370], [0, 100], [0, -100]` (wedge shape)

## Message Flow

### Body → Mind Messages

| Type | Data | When |
|------|------|------|
| `sight` | `{sight: "player", id: N}` | Player enters vision cone |
| `signal` | `{type: "sight", status: "lost", reason: "..."}` | Player leaves vision cone |
| `signal` | `{type: "movement", status: "completed", reason: "waypoint_reached"}` | Waypoint reached |
| `signal` | `{type: "movement", status: "completed", reason: "lkp_reached"}` | Last known position reached |

### Mind → Body Messages

| Type | Data | When |
|------|------|------|
| `walk` | `{type: "goto", target: "M1_A"}` | Navigate to waypoint |
| `chase` | `{id: N}` | Chase player by instance ID |
| `stop` | `{}` | Stop all movement |

## Temper-Based Behavior Selection

The patrol agent uses the temper system to select different plans based on personality:

### Lazy Guard (`laziness(0.9)`)
```jason
@lazy_rest[temper([laziness(0.8)])]
+!rest_at_waypoint
    <-  .print("Ugh, my feet hurt. Taking a break...");
        .wait(5000).  // Long rest between waypoints

@calm_search[temper([aggressiveness(-0.5)])]
+!search_area
    <-  .print("Must have been rats.");
        !check_random_spots(1).  // Only checks 1 spot
```

### Angry Guard (`aggressiveness(0.9)`)
```jason
@active_rest[temper([laziness(0.2)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving on.");
        .wait(1000).  // Short rest between waypoints

@angry_search[temper([aggressiveness(0.8)])]
+!search_area
    <-  .print("COME OUT! I KNOW YOU'RE HERE!");
        !check_random_spots(3).  // Checks 3 spots thoroughly
```

## Behavior Lifecycle

### 1. Patrolling State

```
+!start_patrol ─→ .wait(1000) ─→ !patrol(Waypoints)
                  (WebSocket ready)

+!patrol([NextWP|Rest]) ─→ vesna.walk(NextWP)
                            ↓
                      .wait(+signal_movement(completed, _))
                            ↓
                      !rest_at_waypoint ─→ !patrol(Rest)
                            ↓
                      [repeat until empty list]
                            ↓
                      !patrol([]) ─→ !patrol(WPs)
                      [loop forever]
```

### 2. Chase State

```
+sight(player, Id) ──→ -state(patrolling)
 [not chasing]         +state(chasing)
                       .drop_all_desires
                            ↓
                       vesna.chase(Id) ──→ Body tracks player
                            ↓
                       Body tracks until sight lost
```

### 3. Vision Loss & LKP Tracking

```
+signal_sight(lost, _) ──→ !wait_for_lkp
   [chasing]
                       .wait({+signal_movement(completed, lkp_reached)}, 10000)
                            ↓
                    [timeout OR lkp_reached]
                            ↓
                       -state(chasing)
                       +state(searching)
                       .abolish(sight(player, _))
                            ↓
                       !search_area
```

### 4. Search & Return to Patrol

```
+!search_area ──→ !check_random_spots(N)
                  [N = 1 for lazy, N = 3 for angry]
                        ↓
                  (waits 2s per spot)
                        ↓
              +!check_random_spots(0) ──→ .abolish(state(_))
                                           +state(patrolling)
                                           !start_patrol
                                                ↓
                                           [loop back to patrol]
```

## Testing

### Prerequisites
1. Navigation mesh configured in scene (`NavigationRegion2D` with `NavigationPolygon`)
2. Waypoint nodes created at `/root/SCENE_NAME/waypoints/M1_A`, etc.
3. Ports match between `vesna.jcm` and Godot `VesnaManager.PORT`

### Test Sequence

1. Start JaCaMo:
   ```bash
   cd mind && gradle run
   ```

2. Run Godot scene

3. **Expected Output (Jason):**
   ```
   [patrol_lazy] Starting patrol!
   [patrol_lazy] Moving to waypoint: M1_A
   [patrol_lazy] Moving to waypoint: M1_B
   [patrol_lazy] Moving to waypoint: M1_C
   [patrol_lazy] Moving to waypoint: M1_D
   [patrol_lazy] Moving to waypoint: M1_A
   [patrol_lazy] CONTACT! Engaging target 12345
   [patrol_lazy] Visual lost! Moving to Last Known Position...
   [patrol_lazy] Arrived at LKP. Target gone.
   [patrol_lazy] Must have been rats.
   [patrol_lazy] Search complete. Returning to patrol.
   [patrol_lazy] Starting patrol!
   ```

4. **Expected Output (Godot):**
   ```
   [MESSAGE] - from patrol_lazy: Looking for waypoint at: /root/test_maze/waypoints/M1_A
   [MESSAGE] - from patrol_lazy: Navigating to position: (-740.0, -479.0)
   [MESSAGE] - from patrol_lazy: Chase started but player already lost
   [MESSAGE] - from patrol_lazy: Looking for waypoint at: /root/test_maze/waypoints/M1_A
   ```

5. **Visual Verification:**
   - Patrol agents move smoothly between waypoints
   - Upon player detection, they pursue
   - After losing sight, they move to last known position
   - After searching, they return to patrol cycle
   - Patrol should restart from first waypoint after search

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| `Moving to waypoint: M1_A` but no movement | Waypoint not found | Check `/root/SCENE_NAME/waypoints/M1_A` exists |
| `Moving to waypoint: <no-value>` | Waypoints not quoted in JCM | Use `["M1_A", "M1_B"]` not `[M1_A, M1_B]` |
| Agent never chases | Collision layers wrong | VisionCone must detect layer 2 (Player) |
| Agent gets stuck | Navigation mesh missing | Add `NavigationRegion2D` to scene |
| Chase never ends | Vision exit not detected | Check `_on_vision_body_exited()` sends signal |
| Patrol doesn't resume | Search doesn't clean state | Verify `.abolish(state(_))` in search completion |

## Extending

### Add More Waypoints

Update `vesna.jcm`:
```jcm
beliefs: waypoints(["M1_A", "M1_B", "M1_C", "M1_D", "M1_E", "M1_F"])
```

And add corresponding Marker2D nodes in the scene.

### Custom Patrol Behavior

Override the rest plan:
```jason
@my_rest[temper([laziness(0.5)])]
+!rest_at_waypoint
    <-  .print("Taking my custom break...");
        .wait(3000).
```

### Patrol Coordination

The coordination handler is already in `patrol.asl`:
```jason
+sight(Ally, _)
    :   state(chasing) & not negotiating(_) & .substring("patrol", Ally)
    <-  // Only matches other patrol agents, not signal beliefs
        +negotiating(Ally);
        .send(Ally, askOne, dist_to_base(_), Reply);
        !resolve_chase(Reply).
```

This allows two patrols to negotiate who continues the chase based on distance to base.

## Architecture Notes

### Signal Namespace Separation

All signal beliefs are prefixed with `signal_` to avoid collision with sight beliefs:
- Sight beliefs: `sight(player, id)` from vision detection
- Signal beliefs: `signal_sight(lost, _)`, `signal_movement(completed, reason)` from body state changes

### Waypoint Resolution

Waypoints in `vesna.jcm` must be strings (quoted) because:
- Godot node names start with uppercase: `M1_A`
- Jason atoms cannot start with uppercase (they're variables)
- Quoting them makes them `StringTerm` which `walk.java` properly handles

### Path Construction in Body

When `walk.java` receives `"M1_A"`:
```gdscript
var waypoint_path = "/root/test_maze/waypoints/" + target_name
var target_node = get_node_or_null(waypoint_path)
```

Adjust the scene path if your scene is named differently.

## Performance Considerations

- **Vision Cone Rotation**: Updates every frame to face movement direction
- **Navigation Updates**: Every physics frame via `NavigationAgent2D`
- **Patience Timer**: 2-second delay before declaring target truly lost
- **Search Duration**: ~6s for lazy (1×2s), ~6s for angry (3×2s)
- **Waypoint Loop**: Continuous unless interrupted by player detection

