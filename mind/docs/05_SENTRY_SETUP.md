# 05_SENTRY_SETUP.md - Sentry Agent Configuration Guide

This document explains how to configure and deploy VEsNA-controlled sentry agents that detect players and coordinate alerts with each other.

## Architecture Overview

```
┌─────────────────────┐                    ┌─────────────────────┐
│   Godot Sentry      │◄──── WebSocket ────►│   Jason Sentry      │
│   (sentry.gd)       │       (PORT)        │   (sentry.asl)      │
├─────────────────────┤                    ├─────────────────────┤
│ • Vision cone       │                    │ • state(scanning/   │
│ • Alert radius      │                    │   alerting)         │
│ • Timers            │                    │ • Perception rules  │
│ • VesnaManager      │                    │ • .send() for alerts│
└─────────────────────┘                    └─────────────────────┘
         │                                          │
         │           Player Detected                │
         ├──────────────────────────────────────────┤
         │ 1. Body sees player                      │
         │ 2. Sends sight(player, id, pos(X,Y))     │
         │ 3. Mind triggers vesna.alert             │
         │ 4. Body runs alert sequence              │
         │ 5. Body sends allies_nearby([...])       │
         │ 6. Mind broadcasts to allies via .send() │
         └──────────────────────────────────────────┘
```

## ⚠️ CRITICAL: Naming Convention

**The Godot node name MUST exactly match the Jason agent name** for `.send()` to work.

**Important:** JaCaMo requires agent names to start with a lowercase letter (they're atoms in Prolog).

| Jason Config (vesna.jcm) | Godot Scene Node Name |
|--------------------------|----------------------|
| `agent sentry1:sentry.asl` | Node named `sentry1` |
| `agent sentry2:sentry.asl` | Node named `sentry2` |
| `agent guard_north:sentry.asl` | Node named `guard_north` |

Jason's `.send(Ally, tell, ...)` uses the agent name as the receiver identifier. VEsNA uses the node name when the body-side needs to route messages.

## Step-by-Step Setup

### 1. Configure Jason Side (mind/vesna.jcm)

```jcm
agent sentry1:sentry.asl {
    ag-class:   vesna.VesnaAgent
    address:    localhost
    port:       9081    // Each sentry needs a unique port
}

agent sentry2:sentry.asl {
    ag-class:   vesna.VesnaAgent
    address:    localhost
    port:       9082
}
```

### 2. Configure Godot Side

For each sentry in your scene:

1. **Set Node Name**: Rename the CharacterBody2D node to match the Jason agent name (e.g., `sentry1` - lowercase)

2. **Set Port**: In the Inspector, set `VesnaManager.PORT` to match the port in `vesna.jcm`

3. **Add to Group**: Add the node to the `"sentries"` group (Project → Groups → Add)

4. **Configure AlertRadius**: Ensure the `AlertRadius` Area2D is set up:
   - `monitoring = false` (script enables it during alerts)
   - Collision mask set to detect other sentries

### 3. Example Scene Structure

```
sentry1 (CharacterBody2D)           # Name matches Jason agent (lowercase!)
├── Sprite
├── CollisionShape2D
├── VisionCone (Area2D)
│   └── CollisionShape2D            # The detection wedge
├── AlertRadius (Area2D)
│   └── CollisionShape2D            # Circular area for finding allies
├── LineOfSight (RayCast2D)
├── SwitchSide (Timer)
├── CooldownTimer (Timer)
└── VesnaManager                    # PORT = 9081
```

### 4. Collision Layers Setup

| Layer | Name | Used By |
|-------|------|---------|
| 1 | Default | Player, walls |
| 2 | Player | Player body |
| 3 | Sentries | Sentry bodies |

**VisionCone**: Mask includes layer 2 (detects Player)
**AlertRadius**: Mask includes layer 3 (detects other Sentries)

## Message Flow

### Body → Mind Messages

| Type | Data | When |
|------|------|------|
| `sight` | `{sight: "player", id: N, pos_x: X, pos_y: Y}` | Player detected |
| `allies` | `{allies: ["Sentry2", "Sentry3"]}` | After alert scan |
| `signal` | `{type: "alert", status: "completed"}` | Alert sequence done |

### Mind → Body Messages

| Type | Data | When |
|------|------|------|
| `alert` | `{type: "start"}` | Mind decides to alert |
| `alert` | `{type: "start", pos_x: X, pos_y: Y}` | Alert with position |

### Mind → Mind Messages (via .send())

| Message | Data | When |
|---------|------|------|
| `player_alert(X, Y)` | Position | Broadcasting to allies |
| `player_alert` | None | Broadcasting without position |

## Testing

1. Start JaCaMo: `./gradlew run` from `mind/` folder
2. Run Godot scene
3. Move player into sentry vision cone
4. Expected output:
   - Jason: `PLAYER DETECTED at position (X, Y)!`
   - Godot: "Alert sequence triggered by mind!"
   - Jason: `Allies found: [sentry2, sentry3]`
   - Jason: `Sending alert to sentry2`
   - Sentry2's Jason: `ALERT received from sentry1!`

## Extending

### Add Custom Alert Response

In `sentry.asl`, modify the `+player_alert` handler:

```jason
+player_alert(X, Y)[source(Sender)]
    <-  .print("ALERT received from ", Sender);
        +aware_of_player(X, Y, Sender);
        // Add custom behavior:
        !investigate(X, Y).

+!investigate(X, Y)
    <-  vesna.walk(target(X, Y));
        .wait({+movement(completed, _)}).
```

### Add Patrol Behavior

Create a patrol plan that runs continuously:

```jason
+state(scanning)
    :   not busy
    <-  +busy;
        !patrol_cycle.

+!patrol_cycle
    <-  vesna.rotate(90);
        .wait(2000);
        vesna.rotate(-90);
        .wait(2000);
        -busy.
```
