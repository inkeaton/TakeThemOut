# VEsNA Quick Reference Card

## Agent Configuration (vesna.jcm)

```jcm
agent agent_name:agent_file.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(trait(0.5), mood_trait(0.0)[mood])
    strategy:   most_similar | random
    address:    localhost
    port:       9080  # Must be unique per agent
    goals:      start
}
```

---

## Internal Actions (Jason → Godot)

| Action | Usage | Effect |
|--------|-------|--------|
| `vesna.patrol(next)` | Move to next waypoint | → PatrolState |
| `vesna.patrol(prev)` | Move to previous waypoint | → PatrolState |
| `vesna.patrol(resume)` | Resume patrol | → PatrolState |
| `vesna.patrol(random)` | Move to random waypoint | → PatrolState |
| `vesna.chase(N)` | Chase with N crumb patience | → ChaseState |
| `vesna.alert` | Trigger alert scan | → AlertState |
| `vesna.investigate(N)` | Check N random points | → InvestigateState |
| `vesna.move_to(X, Y)` | Move to coordinates | → TravelState |
| `vesna.calc_centroid(List, X, Y)` | Calculate average position | (internal) |

---

## Perception Handlers (Godot → Jason)

```jason
// Player detected with position
+sight(player, Id, pos(X, Y))
    <- /* react to player */ .

// Allies found during alert
+allies_nearby([Ally1, Ally2, ...])
    <- /* broadcast alerts */ .

// Arrived at waypoint
+navigation(reached, WaypointName)
    <- /* continue patrol */ .

// Target lost during chase
+target_lost(pos(X, Y), Reason)
    <- /* investigate or resume */ .

// Event signal from body
+signal_type(status, reason)
    <- /* handle event */ .
```

---

## Inter-Agent Communication

```jason
// Send to specific agent
.send(agent_name, tell, belief(args))
.send(agent_name, achieve, goal)

// Broadcast to all
.broadcast(tell, belief(args))
.broadcast(achieve, goal)

// Handle incoming message
+belief(args)[source(Sender)]
    <- /* Sender is the source agent */ .

+!goal[source(Requester)]
    <- /* achieve goal, reply to Requester */ .
```

---

## Temper Annotations

```jason
@plan_label[
    temper([trait1(0.8), trait2(0.2)]),
    effects([mood_trait(+0.1)])
]
+!goal
    :   context
    <-  actions.
```

**Selection**: Plans with temper closer to agent's traits are preferred.

---

## State Machine (GDScript)

```gdscript
# Change state with optional data
state_machine.change_state_by_name("StateName", {"key": "value"})

# Access in state
func enter(msg: Dictionary = {}) -> void:
    var value = msg.get("key", default)

# Send to mind
vesna.send_sight_with_position("player", id, position)
vesna.send_navigation_update("reached", "waypoint_name")
vesna.send_signal("type", "status", "reason")
```

---

## Agent States Overview

### Sentry
```
Scan ──(sees player)──► Cooldown ──(mind: alert)──► Alert ──► Scan
```

### Patrol
```
Patrol ──(sees player)──► Chase ──(loses sight)──► Track ──(loses scent)──► Idle
                                                          └──► Investigate ──► Idle
       ◄──(investigation complete)────────────────────────────────────────────┘
       ◄──(receives alert)──── Travel ──► Investigate
```

### Captain
```
Same as Patrol, plus:
- At waypoint: broadcasts for intel → moves to centroid or random
- On sight: broadcasts alert to all, then chases
```

---

## Port Assignment Example

| Agent | Port | Node Name |
|-------|------|-----------|
| sentry1 | 9081 | `sentry1` |
| sentry2 | 9082 | `sentry2` |
| patrol1 | 9083 | `patrol1` |
| patrol2 | 9084 | `patrol2` |
| captain1 | 9085 | `captain1` |

---

## Common Patterns

### Patrol with Personality

```jason
@aggressive[temper([aggressiveness(0.9)])]
+sight(player, _, pos(X,Y)) <- vesna.chase(15).

@passive[temper([aggressiveness(0.1)])]
+sight(player, _, pos(X,Y)) <- vesna.chase(3).
```

### Alert Broadcasting

```jason
+allies_nearby([]) <- .print("No allies").
+allies_nearby([Ally|Rest]) 
    <- .send(Ally, tell, player_spotted_at(X, Y));
       !broadcast([Rest]).
```

### Intel Gathering (Captain)

```jason
+!gather_intel
    <- .broadcast(achieve, report_sightings);
       .wait(2000);
       !analyze.

+!report_sightings[source(Captain)]
    :   last_pos(X, Y)
    <- .send(Captain, tell, sighting_report(pos(X,Y))).
```
