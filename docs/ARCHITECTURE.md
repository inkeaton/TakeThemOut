# Take Them Out - System Architecture Documentation

This document provides a comprehensive overview of the VEsNA-based stealth game architecture, covering the integration between Godot (bodies) and Jason/JaCaMo (minds).

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Project Structure](#project-structure)
3. [Communication Protocol](#communication-protocol)
4. [State Machine Framework](#state-machine-framework)
5. [Agent Types](#agent-types)
   - [Sentry](#sentry)
   - [Patrol](#patrol)
   - [Captain](#captain)
6. [Temper System](#temper-system)
7. [Internal Actions Reference](#internal-actions-reference)
8. [Message Protocol Reference](#message-protocol-reference)
9. [Quick Start Guide](#quick-start-guide)

---

## System Overview

This game uses a **dual-process architecture** where:

- **Bodies** (Godot/GDScript) handle physics, rendering, navigation, and sensory detection
- **Minds** (Jason/AgentSpeak) handle decision-making, personality, and inter-agent communication

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GAME ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────┐         ┌─────────────────────────┐           │
│  │   GODOT (Body)          │◄─ WS ──►│   JASON (Mind)          │           │
│  │                         │         │                         │           │
│  │  • CharacterBody2D      │         │  • VesnaAgent.java      │           │
│  │  • StateMachine         │         │  • AgentSpeak (.asl)    │           │
│  │  • NavigationAgent2D    │         │  • Temper System        │           │
│  │  • VesnaManager         │         │  • Internal Actions     │           │
│  │  • Vision/Detection     │         │  • Inter-agent Comms    │           │
│  └─────────────────────────┘         └─────────────────────────┘           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Separation of Concerns**: Bodies handle "how", minds handle "what" and "why"
2. **Event-Driven Communication**: Bodies report perceptions, minds issue commands
3. **State Machine Pattern**: Each body uses a finite state machine for behavior
4. **Personality via Temper**: Agents have persistent traits affecting decisions

---

## Project Structure

```
take-them-out/
├── bodies/                          # Godot-side agent implementations
│   ├── guards/
│   │   ├── vesnaManager.gd          # WebSocket server for mind-body comms
│   │   ├── shared/
│   │   │   ├── state_machine.gd     # Generic FSM with dependency injection
│   │   │   └── state.gd             # Base state class
│   │   ├── sentries/
│   │   │   ├── sentry.gd            # Sentry body (stationary)
│   │   │   └── states/              # Scan, Alert, Cooldown
│   │   ├── patrols/
│   │   │   ├── patrol.gd            # Patrol body (mobile)
│   │   │   └── states/              # Patrol, Chase, Track, Investigate, Travel, Idle
│   │   └── captains/
│   │       └── captain.gd           # Extends patrol.gd
│   └── player/
│       └── src/player.gd
│
├── mind/                            # Jason/JaCaMo-side implementations
│   ├── vesna.jcm                    # JaCaMo project configuration
│   ├── build.gradle                 # Gradle build file
│   └── src/
│       ├── agt/
│       │   ├── vesna.asl            # Base agent logic (RCC navigation)
│       │   ├── sentry.asl           # Sentry mind
│       │   ├── patrol.asl           # Patrol mind
│       │   ├── captain.asl          # Captain mind
│       │   └── vesna/
│       │       ├── VesnaAgent.java  # Core agent class
│       │       ├── WsClient.java    # WebSocket client
│       │       ├── Temper.java      # Personality system
│       │       ├── helpers/
│       │       │   └── calc_centroid.java
│       │       └── via/             # Internal actions
│       │           ├── patrol.java
│       │           ├── chase.java
│       │           ├── alert.java
│       │           ├── investigate.java
│       │           └── move_to.java
│       └── env/vesna/
│           ├── SituatedArtifact.java
│           └── GrabbableArtifact.java
│
├── stages/                          # Game levels/scenes
│   └── maze/test_maze.tscn
│
├── references/                      # Reference VEsNA implementations
│   ├── docs/                        # Original documentation (may be outdated)
│   ├── vesna-light-main/            # Basic VEsNA example
│   ├── vesna-pro-main/              # Temper system example
│   └── vesna-temper/                # Extended temper example
│
└── docs/                            # This documentation
    └── ARCHITECTURE.md
```

---

## Communication Protocol

### Connection Flow

1. **Godot** starts a TCP server via `VesnaManager` on a unique `PORT` per agent
2. **Jason** uses `WsClient` to connect as WebSocket client
3. Agent names in JaCaMo **must match** Godot node names (lowercase)

### Message Format

All messages are JSON with this structure:

```json
{
  "sender": "agent_name | body",
  "receiver": "body | vesna",
  "type": "message_type",
  "data": { /* type-specific payload */ }
}
```

### VesnaManager (vesnaManager.gd)

The `VesnaManager` class handles all WebSocket communication on the Godot side:

**Key Methods:**
| Method | Purpose |
|--------|---------|
| `send_data(data: Dictionary)` | Send raw JSON to mind |
| `send_signal(type, status, reason)` | Send event signal |
| `send_sight_with_position(name, id, pos)` | Report visual detection |
| `send_allies_found(allies: Array)` | Report nearby allies |
| `send_navigation_update(status, waypoint)` | Report navigation events |
| `send_target_lost(pos, reason)` | Report lost target |
| `send_event(type, data)` | Send custom event |

**Signals:**
- `command_received(intention: Dictionary)` - Emitted when mind sends command
- `connection_established()` - WebSocket handshake complete
- `connection_lost()` - Connection closed

---

## State Machine Framework

### StateMachine (state_machine.gd)

A generic FSM that manages state transitions and injects dependencies into states.

```gdscript
class_name StateMachine
extends Node

@export var initial_state: State
var current_state: State
var states: Dictionary = {}  # Maps state name to node

func init(target_body: CharacterBody2D, target_nav: NavigationAgent2D, target_vesna: VesnaManager) -> void:
    # Injects dependencies into all child states
    for child in get_children():
        if child is State:
            child.body = target_body
            child.nav_agent = target_nav
            child.vesna = target_vesna
            child.state_machine = self
            states[child.name] = child

func change_state(new_state_node: State, msg: Dictionary = {}) -> void
func change_state_by_name(state_name: String, msg: Dictionary = {}) -> void
```

### State (state.gd)

Base class for all states with injected references:

```gdscript
class_name State
extends Node

var body: CharacterBody2D      # The agent's body
var nav_agent: NavigationAgent2D  # Navigation (null for sentries)
var vesna: VesnaManager        # Communication manager
var state_machine: StateMachine

func enter(_msg: Dictionary = {}) -> void: pass
func exit() -> void: pass
func update_physics(_delta: float) -> void: pass
```

---

## Agent Types

### Sentry

**Role**: Stationary guard that rotates between viewpoints and alerts others when player is detected.

**Body** (`sentry.gd`):
- No navigation (stationary)
- Rotates `VisionCone` through configured angles
- Uses `AlertScanner` (ShapeCast2D) to find nearby allies
- Sends sight reports with position to mind

**States:**
| State | File | Description |
|-------|------|-------------|
| **Scan** | `scan_state.gd` | Default state, rotates viewpoint on timer |
| **Cooldown** | `cooldown_state.gd` | Waiting for mind response after detection |
| **Alert** | `alert_state.gd.gd` | Performs ally scan, sends results to mind |

**Mind** (`sentry.asl`):
```
States: scanning → alerting → scanning

+sight(player, Id, pos(X, Y))
    → vesna.alert (trigger body alert)
    
+allies_nearby(AllyList)
    → !broadcast_alert (use .send() to each ally)
    
+player_spotted_at(X, Y)[source(Sender)]
    → Store awareness of player location
```

**Message Flow:**
```
Player enters vision cone
    → Body: check_line_of_sight()
    → Body: send_sight_with_position("player", id, pos)
    → Body: change_state("Cooldown")
    → Mind: +sight(player, Id, pos(X,Y)) triggers
    → Mind: vesna.alert
    → Body: receives "alert" command
    → Body: change_state("Alert")
    → Body: _perform_scan() finds allies
    → Body: send_allies_found(["patrol1", "sentry2"])
    → Mind: +allies_nearby([...]) triggers
    → Mind: .send(Ally, tell, player_spotted_at(X, Y))
```

---

### Patrol

**Role**: Mobile guard that patrols waypoints, chases player on sight, tracks by scent, and investigates alerts.

**Body** (`patrol.gd`):
- Uses `NavigationAgent2D` for pathfinding
- Vision cone rotates with velocity direction
- Detects player via `VisionCone` (Area2D) and `LineOfSight` (RayCast2D)
- Tracks player via `ScentCast` (ShapeCast2D) following scent crumbs

**States:**
| State | File | Description |
|-------|------|-------------|
| **Patrol** | `patrol_state.gd` | Move between waypoints (next/prev/random) |
| **Chase** | `chase_state.gd` | Follow player directly |
| **Track** | `track_state.gd` | Follow scent crumbs after losing sight |
| **Investigate** | `investigate_state.gd` | Check random points in area |
| **Travel** | `travel_state.gd` | Move to absolute coordinates (from alert) |
| **Idle** | `idle_state.gd` | Stopped, waiting for mind command |

**Mind** (`patrol.asl`):
```
States: patrolling → chasing → searching → investigating → patrolling

+!patrol
    → !decide_next_step (temper-based choice)
    
+sight(player, Id, pos(X, Y))
    → vesna.chase(patience)  // patience based on aggressiveness
    
+target_lost(pos(X,Y), Reason)
    → vesna.investigate(points)  // points based on laziness
    
+player_spotted_at(X, Y)[source(Sender)]
    → vesna.move_to(X, Y)  // respond to sentry/captain alert
```

**Temper Examples:**
```jason
@chase_aggressive[temper([aggressiveness(0.8)])]
+sight(player, Id, pos(X, Y)) <- vesna.chase(15).  // Very persistent

@chase_lazy[temper([aggressiveness(0.2)])]
+sight(player, Id, pos(X, Y)) <- vesna.chase(4).   // Gives up quickly
```

---

### Captain

**Role**: Squad leader that patrols, coordinates intel from team, and calculates intercept points.

**Body** (`captain.gd`):
- Extends `patrol.gd` (inherits all patrol behavior and states)
- Overrides `react_to_player()` to also trigger alert broadcast

**Mind** (`captain.asl`):
```
States: patrolling → (same as patrol)

+!decide_next_step
    → .broadcast(achieve, report_sightings)  // Ask squad for intel
    → .wait(2000)
    → !analyze_intel
    
+!analyze_intel (with sightings)
    → vesna.calc_centroid(List, AvgX, AvgY)
    → vesna.move_to(AvgX, AvgY)  // Move to centroid of sightings
    
+!analyze_intel (no sightings)
    → vesna.patrol(random)  // Random waypoint
    
+sight(player, Id, pos(X, Y))
    → .broadcast(tell, player_spotted_at(X, Y))  // Alert squad
    → vesna.chase(20)  // Captains are very persistent
```

**Squad Coordination Flow:**
```
Captain reaches waypoint
    → .broadcast(achieve, report_sightings)
    → Each agent receives +!report_sightings
    → Agents reply with .send(Captain, tell, sighting_report(pos(X,Y)))
    → Captain collects in sightings([...]) belief
    → vesna.calc_centroid calculates average position
    → Captain moves to intercept point
```

---

## Temper System

The Temper system allows agents to have personality traits that influence plan selection.

### Configuration (vesna.jcm)

```jcm
agent patrol1:patrol.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(aggressiveness(0.7), laziness(0.3)[mood])
    strategy:   most_similar
    address:    localhost
    port:       9081
}
```

### Trait Types

| Type | Range | Persistence | Syntax |
|------|-------|-------------|--------|
| **Personality** | [0.0, 1.0] | Never changes | `trait(value)` |
| **Mood** | [-1.0, 1.0] | Changes via effects | `trait(value)[mood]` |

### Plan Annotations

```jason
@plan_label[temper([trait1(value), trait2(value)]), effects([mood_trait(delta)])]
+!goal
    :   context
    <-  actions.
```

### Selection Strategies

| Strategy | Type | Algorithm |
|----------|------|-----------|
| `most_similar` | Deterministic | Minimum distance: $\sum |T_{agent} - T_{plan}|$ |
| `random` | Probabilistic | Weighted by: $\sum T_{agent} \times T_{plan}$ |

---

## Internal Actions Reference

Internal actions are Java classes in `mind/src/agt/vesna/via/` that send commands to Godot.

| Action | Arguments | Sends to Body | Triggers State |
|--------|-----------|---------------|----------------|
| `vesna.patrol(action)` | `next`, `prev`, `resume`, `random` | `{"type": "patrol", "data": {"action": "..."}}` | PatrolState |
| `vesna.chase(patience)` | Integer (crumb limit) | `{"type": "chase", "data": {"type": "start", "patience": N}}` | ChaseState |
| `vesna.alert` | (none) | `{"type": "alert", "data": {"type": "start"}}` | AlertState |
| `vesna.investigate(points)` | Integer (point count) | `{"type": "investigate", "data": {"points": N}}` | InvestigateState |
| `vesna.move_to(X, Y)` | Coordinates | `{"type": "move_to", "data": {"pos_x": X, "pos_y": Y}}` | TravelState |
| `vesna.calc_centroid(List, X, Y)` | List of pos(), output vars | (Pure calculation, no message) | - |

---

## Message Protocol Reference

### Body → Mind Messages

| Type | Data Fields | Creates Belief/Signal |
|------|-------------|----------------------|
| `sight` | `sight`, `id`, `pos_x`, `pos_y` | `+sight(object, id, pos(X, Y))` |
| `allies` | `allies: [...]` | `+allies_nearby([...])` |
| `navigation` | `status`, `waypoint` | `+navigation(status, waypoint)` |
| `event` | `event`, `pos_x`, `pos_y`, `reason` | `+target_lost(pos(X,Y), reason)` |
| `signal` | `type`, `status`, `reason` | `+signal_type(status, reason)` |

### Mind → Body Messages

| Type | Data Fields | Handled By |
|------|-------------|------------|
| `patrol` | `action` | `_on_vesna_manager_command_received` → PatrolState |
| `chase` | `type`, `patience` | ChaseState (then TrackState) |
| `alert` | `type: "start"` | AlertState |
| `investigate` | `points` | InvestigateState |
| `move_to` | `pos_x`, `pos_y` | TravelState |

---

## Quick Start Guide

### Running the Game

1. **Start Jason/JaCaMo first:**
   ```bash
   cd mind/
   ./gradlew run
   ```

2. **Start Godot second:**
   - Open project in Godot 4
   - Run the scene (F5)
   - Console should show "Mind connected!" for each agent

### Adding a New Agent

1. **Create Godot scene:**
   - Create CharacterBody2D with required children (VesnaManager, StateMachine, states)
   - Set unique `PORT` in VesnaManager inspector
   - Name the node to match Jason agent name (lowercase)

2. **Create Jason agent:**
   - Create `myagent.asl` in `mind/src/agt/`
   - Add agent definition to `vesna.jcm` with matching port

3. **Naming Convention:**
   - Jason agent name and Godot node name **must match** (both lowercase)
   - Example: `agent patrol1:patrol.asl` → Godot node named `patrol1`

### Debugging Tips

- Check console output for `[NetworkManager]` messages
- Verify ports match between JaCaMo and Godot
- Use `Messages.print_message()` in GDScript for consistent logging
- Check Jason console for `.print()` output and plan execution

---

## Notes and Known Issues

1. **File naming**: Some state files have double extensions (e.g., `alert_state.gd.gd`) - consider renaming for consistency

2. **Captain states**: Captain uses Patrol's states directly - no captain-specific states needed currently

3. **Scent tracking**: Player must drop `Crumb` nodes for tracking to work (see `crumb.gd`)

4. **Connection order**: Always start Jason before Godot to ensure agents connect properly

5. **vesna.asl base file**: Contains RCC (Region Connection Calculus) logic - currently not heavily used by game agents but available for spatial reasoning
