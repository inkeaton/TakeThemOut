# VEsNA Framework - Getting Started Tutorial

A step-by-step guide to creating a new Godot application with VEsNA-controlled BDI agents.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Step 1: Set Up the Jason/JaCaMo Project](#step-1-set-up-the-jasonjacamo-project)
4. [Step 2: Create the Godot Project](#step-2-create-the-godot-project)
5. [Step 3: Configure the Agent Body](#step-3-configure-the-agent-body)
6. [Step 4: Write Agent Logic](#step-4-write-agent-logic)
7. [Step 5: Running the Application](#step-5-running-the-application)
8. [Step 6: Adding Custom Actions](#step-6-adding-custom-actions)
9. [Step 7: Adding Temper/Personality](#step-7-adding-temperpersonality)
10. [Troubleshooting](#troubleshooting)
11. [Next Steps](#next-steps)

---

## Prerequisites

### Required Software

1. **Godot Engine 4.x** - [Download](https://godotengine.org/download)
2. **Java JDK 17+** - [Download](https://adoptium.net/)
3. **Gradle 8.x** - [Download](https://gradle.org/install/)

### Required Knowledge

- Basic Godot/GDScript experience
- Understanding of BDI agents (Beliefs, Desires, Intentions)
- Familiarity with AgentSpeak syntax is helpful

---

## Project Structure

Create the following folder structure:

```
my_vesna_project/
├── mind/                          # Jason/JaCaMo project
│   ├── build.gradle               # Gradle build configuration
│   ├── vesna.jcm                  # JaCaMo project file
│   └── src/
│       ├── agt/
│       │   ├── vesna.asl          # Base agent logic (copy from VEsNA)
│       │   ├── vesna/             # Java classes (copy from VEsNA)
│       │   │   ├── VesnaAgent.java
│       │   │   ├── WsClient.java
│       │   │   ├── WsClientMsgHandler.java
│       │   │   ├── Temper.java
│       │   │   ├── TemperSelectable.java
│       │   │   ├── IntentionWrapper.java
│       │   │   ├── OptionWrapper.java
│       │   │   └── via/
│       │   │       ├── walk.java
│       │   │       ├── rotate.java
│       │   │       └── jump.java
│       │   └── myagent.asl        # Your custom agent
│       └── env/
│           └── vesna/             # Artifacts (copy from VEsNA)
│               ├── SituatedArtifact.java
│               └── GrabbableArtifact.java
│
└── game/                          # Godot project
    ├── project.godot
    ├── scripts/
    │   └── vesna.gd               # Agent body script
    └── scenes/
        └── main.tscn              # Main scene
```

---

## Step 1: Set Up the Jason/JaCaMo Project

### 1.1 Create build.gradle

```gradle
defaultTasks 'run'

apply plugin: 'java'

repositories {
    maven { url "https://raw.githubusercontent.com/jacamo-lang/mvn-repo/master" }
    maven { url "https://repo.gradle.org/gradle/libs-releases" }
    mavenCentral()
}

dependencies {
    implementation('org.jacamo:jacamo:1.2')
    implementation group: 'org.java-websocket', name: 'Java-WebSocket', version: '1.5.6'
    implementation("org.json:json:20230227")
}

task run(type: JavaExec, dependsOn: 'classes') {
    description 'runs the application'
    group 'JaCaMo'
    mainClass = 'jacamo.infra.JaCaMoLauncher'
    args 'vesna.jcm'
    classpath sourceSets.main.runtimeClasspath
}

sourceSets {
    main {
        java {
            srcDir 'src/'
        }
    }
}
```

### 1.2 Create vesna.jcm

```jcm
mas vesna {

    agent myagent:myagent.asl {
        ag-class:   vesna.VesnaAgent
        address:    localhost
        port:       9080
        goals:      start
    }

}
```

### 1.3 Copy VEsNA Core Files

Copy the following files from the VEsNA framework to your project:

**From `minds/src/agt/`:**
- `vesna.asl` → `mind/src/agt/`
- `vesna/VesnaAgent.java` → `mind/src/agt/vesna/`
- `vesna/WsClient.java` → `mind/src/agt/vesna/`
- `vesna/WsClientMsgHandler.java` → `mind/src/agt/vesna/`
- `vesna/Temper.java` → `mind/src/agt/vesna/`
- `vesna/TemperSelectable.java` → `mind/src/agt/vesna/`
- `vesna/IntentionWrapper.java` → `mind/src/agt/vesna/`
- `vesna/OptionWrapper.java` → `mind/src/agt/vesna/`
- `vesna/via/walk.java` → `mind/src/agt/vesna/via/`
- `vesna/via/rotate.java` → `mind/src/agt/vesna/via/`
- `vesna/via/jump.java` → `mind/src/agt/vesna/via/`

**From `minds/src/env/`:**
- `vesna/SituatedArtifact.java` → `mind/src/env/vesna/`
- `vesna/GrabbableArtifact.java` → `mind/src/env/vesna/`

### 1.4 Create Your Agent (myagent.asl)

```jason
{ include("vesna.asl") }

// Initial beliefs
my_state(idle).

// Initial goal handler
+!start
    <-  .print("Agent started!");
        !main_loop.

// Main behavior loop
+!main_loop
    <-  .print("Looking for waypoint...");
        vesna.walk(waypoint1);
        .wait({+movement(completed, destination_reached)});
        .print("Reached waypoint1!");
        
        .wait(2000);
        
        vesna.walk(waypoint2);
        .wait({+movement(completed, destination_reached)});
        .print("Reached waypoint2!");
        
        .wait(2000);
        !main_loop.

// Handle movement failures
+movement(stopped, Reason)
    <-  .print("Movement stopped: ", Reason);
        !main_loop.
```

---

## Step 2: Create the Godot Project

### 2.1 Create New Godot Project

1. Open Godot
2. Create New Project in `my_vesna_project/game/`
3. Set renderer to Forward+ (3D) or Compatibility

### 2.2 Create Main Scene Structure

Create `scenes/main.tscn` with this structure:

```
Main (Node3D)
├── DirectionalLight3D
├── Camera3D
├── NavigationRegion3D
│   ├── MeshInstance3D (floor)
│   ├── waypoint1 (Node3D)
│   └── waypoint2 (Node3D)
└── Agent (CharacterBody3D)
    ├── NavigationAgent3D
    ├── CollisionShape3D
    └── MeshInstance3D (or your character model)
```

### 2.3 Set Up Navigation

1. Select `NavigationRegion3D`
2. In Inspector, create a new `NavigationMesh`
3. Add a floor mesh (e.g., a plane or BoxMesh)
4. Click "Bake NavigationMesh" in the toolbar

### 2.4 Create Waypoints

1. Create `Node3D` nodes as children of `NavigationRegion3D`
2. Name them `waypoint1`, `waypoint2`, etc.
3. Position them on the navigation mesh

---

## Step 3: Configure the Agent Body

### 3.1 Create vesna.gd Script

Create `scripts/vesna.gd`:

```gdscript
extends CharacterBody3D

# Movement parameters
const SPEED = 5.0
const ACCELERATION = 8.0

# Network configuration - SET UNIQUE PORT PER AGENT
@export var PORT : int = 9080

# Network objects
var tcp_server := TCPServer.new()
var ws := WebSocketPeer.new()

# State
var end_communication = true
var target_movement : String = ""

# Node references
@onready var navigator : NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
    # Start TCP server
    if tcp_server.listen(PORT) != OK:
        push_error("Unable to start server on port " + str(PORT))
        set_process(false)
    print("Agent listening on port ", PORT)

func _process(delta: float) -> void:
    # Accept new connections
    while tcp_server.is_connection_available():
        var conn : StreamPeerTCP = tcp_server.take_connection()
        assert(conn != null)
        ws.accept_stream(conn)
        print("Mind connected!")
    
    # Poll WebSocket
    ws.poll()
    
    # Process incoming messages
    if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
        while ws.get_available_packet_count():
            var msg : String = ws.get_packet().get_string_from_ascii()
            print("Received: ", msg)
            var intention : Dictionary = JSON.parse_string(msg)
            manage(intention)

func _physics_process(delta: float) -> void:
    # Apply gravity
    if not is_on_floor():
        velocity += get_gravity() * delta
    
    # Handle navigation
    if navigator.is_navigation_finished():
        velocity.x = 0
        velocity.z = 0
        if not end_communication:
            signal_end_movement("completed", "destination_reached")
    else:
        var direction = (navigator.get_next_path_position() - global_position).normalized()
        rotation.y = atan2(direction.x, direction.z)
        velocity = velocity.lerp(direction * SPEED, ACCELERATION * delta)
    
    move_and_slide()

func manage(intention : Dictionary) -> void:
    var type : String = intention['type']
    var data : Dictionary = intention['data']
    
    match type:
        'walk':
            if data['type'] == 'goto':
                walk(data['target'])
        'rotate':
            rotate_agent(data)
        'jump':
            jump()
        _:
            print("Unknown action type: ", type)

func walk(target: String) -> void:
    # Try to find target node
    var target_node = find_target(target)
    if target_node == null:
        print("Target not found: ", target)
        signal_end_movement("failed", "target_not_found")
        return
    
    # Set navigation target
    navigator.set_target_position(target_node.global_position)
    target_movement = target
    end_communication = false

func find_target(target_name: String) -> Node3D:
    # Search in NavigationRegion
    var nav_region = get_node_or_null("/root/Main/NavigationRegion3D")
    if nav_region:
        var target = nav_region.get_node_or_null(target_name)
        if target:
            return target
    
    # Search in root
    var root = get_tree().root.get_node_or_null("Main")
    if root:
        return root.get_node_or_null(target_name)
    
    return null

func rotate_agent(data: Dictionary) -> void:
    # Implement rotation if needed
    pass

func jump() -> void:
    if is_on_floor():
        velocity.y = 4.5

func signal_end_movement(status: String, reason: String) -> void:
    target_movement = ""
    end_communication = true
    
    var log : Dictionary = {
        "sender": "body",
        "receiver": "vesna",
        "type": "signal",
        "data": {
            "type": "movement",
            "status": status,
            "reason": reason
        }
    }
    ws.send_text(JSON.stringify(log))
    print("Sent: ", JSON.stringify(log))

func _exit_tree() -> void:
    ws.close()
    tcp_server.stop()
```

### 3.2 Attach Script to Agent

1. Select the `Agent` CharacterBody3D node
2. Attach the `vesna.gd` script
3. In Inspector, set `PORT` to `9080`

### 3.3 Configure NavigationAgent3D

1. Select the `NavigationAgent3D` node
2. Set `Path Desired Distance`: 0.5
3. Set `Target Desired Distance`: 0.5

### 3.4 Add CollisionShape

1. Select `CollisionShape3D`
2. Create a `CapsuleShape3D` or `BoxShape3D`
3. Size it appropriately for your agent

---

## Step 4: Write Agent Logic

### 4.1 Basic Agent Behavior

The `myagent.asl` we created earlier will:
1. Start with goal `!start`
2. Print a message
3. Walk to `waypoint1`
4. Wait for movement completion
5. Walk to `waypoint2`
6. Repeat

### 4.2 Adding Reactions to Events

```jason
{ include("vesna.asl") }

+!start
    <-  .print("Agent ready!");
        !patrol.

// Patrol behavior
+!patrol
    <-  vesna.walk(waypoint1);
        .wait({+movement(Status, Reason)});
        if (Status == completed) {
            .print("Reached waypoint1");
        } else {
            .print("Failed to reach waypoint1: ", Reason);
        }
        .wait(1000);
        vesna.walk(waypoint2);
        .wait({+movement(Status2, Reason2)});
        .print("Movement result: ", Status2, " - ", Reason2);
        .wait(1000);
        !patrol.

// React to seeing something
+sight(Object, Id)
    <-  .print("I see: ", Object, " with id ", Id);
        !investigate(Object).

+!investigate(Object)
    <-  .print("Investigating ", Object);
        vesna.walk(Object);
        .wait({+movement(_, _)}).
```

---

## Step 5: Running the Application

### 5.1 Start Godot First

1. Open the Godot project
2. Run the scene (F5)
3. You should see "Agent listening on port 9080" in the console

### 5.2 Start Jason Second

Open a terminal in the `mind/` folder:

```bash
# On Linux/Mac
./gradlew run

# On Windows
gradlew.bat run
```

### 5.3 Verify Connection

You should see:
- In Godot: "Mind connected!"
- In Jason console: Agent initialization messages
- Agent starts moving between waypoints

### 5.4 Stop the Application

1. Stop Godot (click Stop or press F8)
2. The Jason agents will terminate automatically (or press Ctrl+C in terminal)

---

## Step 6: Adding Custom Actions

### 6.1 Create Internal Action (Java)

Create `mind/src/agt/vesna/via/speak.java`:

```java
package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

public class speak extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        if (args.length < 1)
            return false;
        
        String message = args[0].toString();
        
        JSONObject data = new JSONObject();
        data.put("message", message);
        
        JSONObject action = new JSONObject();
        action.put("sender", ts.getAgArch().getAgName());
        action.put("receiver", "body");
        action.put("type", "speak");
        action.put("data", data);
        
        VesnaAgent ag = (VesnaAgent) ts.getAg();
        ag.perform(action.toString());
        return true;
    }
}
```

### 6.2 Handle in Godot

Add to `vesna.gd` in the `manage()` function:

```gdscript
func manage(intention : Dictionary) -> void:
    var type : String = intention['type']
    var data : Dictionary = intention['data']
    
    match type:
        'walk':
            if data['type'] == 'goto':
                walk(data['target'])
        'speak':
            speak(data['message'])
        # ... other actions

func speak(message: String) -> void:
    print("Agent says: ", message)
    # You could also display a speech bubble, play audio, etc.
    
    # Signal completion
    var log : Dictionary = {
        "sender": "body",
        "receiver": "vesna",
        "type": "signal",
        "data": {
            "type": "speech",
            "status": "completed",
            "reason": "finished"
        }
    }
    ws.send_text(JSON.stringify(log))
```

### 6.3 Use in Agent

```jason
+!greet
    <-  vesna.speak("Hello, world!");
        .wait({+speech(completed, _)});
        .print("Finished speaking").
```

---

## Step 7: Adding Temper/Personality

### 7.1 Configure Temper in JCM

```jcm
mas vesna {

    agent myagent:myagent.asl {
        ag-class:   vesna.VesnaAgent
        temper:     temper(
            curiosity(0.7),           // Personality
            caution(0.4),             // Personality
            excitement(0.0)[mood]     // Mood
        )
        strategy:   most_similar
        address:    localhost
        port:       9080
        goals:      start
    }

}
```

### 7.2 Annotate Plans

```jason
{ include("vesna.asl") }

+!start
    <-  !decide_action.

// Curious agent explores new areas
@explore_plan[
    temper([curiosity(0.8), caution(0.2)]),
    effects([excitement(0.2)])
]
+!decide_action
    :   unknown_area(Area)
    <-  .print("I'm curious! Let's explore ", Area);
        vesna.walk(Area);
        .wait({+movement(_, _)});
        !decide_action.

// Cautious agent stays in safe areas
@safe_plan[
    temper([curiosity(0.2), caution(0.8)]),
    effects([excitement(-0.1)])
]
+!decide_action
    :   safe_area(Area)
    <-  .print("Better stay safe in ", Area);
        vesna.walk(Area);
        .wait({+movement(_, _)});
        !decide_action.

// Default behavior
+!decide_action
    <-  .print("Nothing to do, waiting...");
        .wait(2000);
        !decide_action.
```

---

## Troubleshooting

### Connection Issues

**Problem:** Agent doesn't connect
- **Check:** Is Godot running before Jason starts?
- **Check:** Are ports matching in JCM and Godot?
- **Check:** Is the port already in use?

```bash
# Check if port is in use (Linux/Mac)
lsof -i :9080

# Windows
netstat -an | findstr 9080
```

**Problem:** "Unable to start server"
- Try a different port number
- Make sure no other Godot instance is running

### Navigation Issues

**Problem:** Agent doesn't move
- **Check:** Is NavigationMesh baked?
- **Check:** Does the target node exist with the correct name?
- **Check:** Is the target on the navigation mesh?

**Problem:** Agent moves erratically
- Adjust `SPEED` and `ACCELERATION` constants
- Check `NavigationAgent3D` distance settings

### Jason Errors

**Problem:** ClassNotFoundException
- Make sure all Java files are in correct packages
- Run `gradle clean` then `gradle run`

**Problem:** Agent terminates immediately
- Check the console for error messages
- Verify WebSocket connection is established

### Message Protocol Issues

**Problem:** Actions not being received
- Add print statements to debug
- Verify JSON format in both directions
- Check that message type strings match exactly

---

## Next Steps

### 1. Multiple Agents

Add more agents with unique ports:

```jcm
agent agent1:myagent.asl {
    ag-class: vesna.VesnaAgent
    port: 9080
    goals: start
}

agent agent2:myagent.asl {
    ag-class: vesna.VesnaAgent
    port: 9081
    goals: start
}
```

Duplicate the Agent node in Godot and set different PORT values.

### 2. Add Artifacts

Create interactive objects using CArtAgO:

```jcm
workspace world {
    artifact button: vesna.SituatedArtifact("room1", 1)
}
```

### 3. Visual Perception

Add area detection to send sight information:

```gdscript
func _on_vision_area_body_entered(body):
    if body != self:
        var sight_msg = {
            "sender": "body",
            "receiver": "vesna",
            "type": "sight",
            "data": {
                "sight": body.name,
                "id": body.get_instance_id()
            }
        }
        ws.send_text(JSON.stringify(sight_msg))
```

### 4. Complex Behaviors

- Add region-based navigation using RCC rules
- Implement team coordination between agents
- Add more personality traits and mood effects

### 5. Study the Coin-Game Example

The `minds/examples/coin-game/` folder contains a complete working example with:
- Multiple agents
- Team-based gameplay
- Dynamic object spawning
- Position-based events

---

## Quick Reference

### Key Files

| File | Purpose |
|------|---------|
| `vesna.jcm` | Agent configuration |
| `build.gradle` | Java dependencies |
| `vesna.asl` | Base agent logic |
| `myagent.asl` | Custom agent behavior |
| `VesnaAgent.java` | Agent class with WebSocket |
| `vesna.gd` | Godot body script |

### Common ASL Patterns

```jason
// Walk to target and wait
vesna.walk(target);
.wait({+movement(completed, destination_reached)});

// Walk with timeout
vesna.walk(target);
.wait({+movement(Status, Reason)}, 10000, fallback_plan);

// React to perception
+sight(Object, Id)
    <- !handle(Object).

// Temper-annotated plan
@my_plan[temper([trait(0.5)]), effects([mood_trait(0.1)])]
+!goal :- context <- action.
```

### Message Types

| Direction | Type | Purpose |
|-----------|------|---------|
| Jason→Godot | `walk` | Movement command |
| Jason→Godot | `rotate` | Rotation command |
| Jason→Godot | `jump` | Jump command |
| Jason→Godot | `interact` | Object interaction |
| Godot→Jason | `signal` | Event notification |
| Godot→Jason | `sight` | Visual perception |

---

Happy coding with VEsNA! 🚀
