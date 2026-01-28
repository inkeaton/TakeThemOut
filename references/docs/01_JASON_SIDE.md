# VEsNA Framework - Jason/JaCaMo Side Documentation

This document describes the Jason (mind) side of the VEsNA framework, covering all Java classes, AgentSpeak files, and configuration.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Configuration](#project-configuration)
3. [VesnaAgent Class](#vesnaagent-class)
4. [WebSocket Communication](#websocket-communication)
5. [Internal Actions (via package)](#internal-actions-via-package)
6. [CArtAgO Artifacts](#cartago-artifacts)
7. [Base Agent Logic (vesna.asl)](#base-agent-logic-vesnaasl)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                      JASON/JACAMO (Mind)                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐     ┌──────────────────────────────┐   │
│  │   vesna.jcm         │     │    Agent ASL Files           │   │
│  │  (Project Config)   │     │   - vesna.asl (base)         │   │
│  │  - Agent defs       │────►│   - alice.asl (example)      │   │
│  │  - Temper params    │     │   - Custom agents            │   │
│  │  - Ports/addresses  │     │                              │   │
│  └─────────────────────┘     └──────────────────────────────┘   │
│           │                              │                       │
│           ▼                              ▼                       │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   VesnaAgent.java                        │    │
│  │  - Extends Jason Agent                                   │    │
│  │  - WebSocket client connection                           │    │
│  │  - Temper-based plan/intention selection                 │    │
│  │  - Message handling (sense, sight)                       │    │
│  └─────────────────────────────────────────────────────────┘    │
│           │                              │                       │
│           ▼                              ▼                       │
│  ┌───────────────────┐     ┌─────────────────────────────────┐  │
│  │  Internal Actions │     │      CArtAgO Artifacts          │  │
│  │  (vesna.via.*)    │     │  - SituatedArtifact.java        │  │
│  │  - walk.java      │     │  - GrabbableArtifact.java       │  │
│  │  - rotate.java    │     │                                 │  │
│  │  - jump.java      │     │                                 │  │
│  └───────────────────┘     └─────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Project Configuration

### vesna.jcm

The JaCaMo project file defines agents, their configurations, and workspaces.

```jcm
mas vesna {

    agent alice:alice.asl {
        ag-class:   vesna.VesnaAgent              // Custom agent class
        temper:     temper( prop1(0.2), prop2(0.3), prop3(-0.5)[mood], prop4(0.3)[mood] )
        address:    localhost                      // WebSocket server address
        port:       9080                           // WebSocket server port
        strategy:   most_similar                   // Decision strategy
        goals:      start                          // Initial goals
    }

    workspace game_world {
        artifact door: vesna.Door("room1", 1)     // Optional artifacts
    }
}
```

**Key Parameters:**

| Parameter | Description | Values |
|-----------|-------------|--------|
| `ag-class` | Custom agent Java class | `vesna.VesnaAgent` |
| `temper` | Personality and mood traits | `temper(trait(value), ...)` |
| `address` | Godot server address | hostname or IP |
| `port` | Godot server port | integer (unique per agent) |
| `strategy` | Decision strategy for temper | `most_similar` or `random` |
| `goals` | Initial agent goals | goal name(s) |
| `beliefs` | Initial beliefs (alternative config) | `belief(value) ...` |

### build.gradle

```gradle
dependencies {
    implementation ('org.jacamo:jacamo:1.2')
    implementation group: 'org.java-websocket', name: 'Java-WebSocket', version: '1.5.6'
    implementation("org.json:json:20230227")
}

task run (type: JavaExec, dependsOn: 'classes') {
    mainClass = 'jacamo.infra.JaCaMoLauncher'
    args 'vesna.jcm'
    classpath sourceSets.main.runtimeClasspath
}

sourceSets {
    main {
        java { srcDir 'src/' }
    }
}
```

**Dependencies:**
- **JaCaMo 1.2**: Agent platform (Jason + CArtAgO + Moise)
- **Java-WebSocket 1.5.6**: WebSocket client library
- **JSON 20230227**: JSON parsing for message handling

---

## VesnaAgent Class

**Location:** `src/agt/vesna/VesnaAgent.java`

The `VesnaAgent` class extends Jason's `Agent` class to create embodied agents with WebSocket communication and temper-based decision making.

### Class Structure

```java
public class VesnaAgent extends Agent {
    private WsClient client;           // WebSocket client
    private Temper temper;             // Agent's personality/mood
    protected transient Logger logger;  // JaCaMo logger
}
```

### Initialization Flow

```
┌─────────────────┐
│   initAg()      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ 1. Call super.initAg()              │
│ 2. Read user parameters from JCM:   │
│    - temper, strategy               │
│    - address, port                  │
│ 3. Initialize Temper system         │
│ 4. Call initBody(address, port)     │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│       initBody()                    │
│ 1. Create WebSocket URI             │
│ 2. Instantiate WsClient             │
│ 3. Set message handler callbacks    │
│ 4. Connect to Godot server          │
└─────────────────────────────────────┘
```

### Key Methods

#### `perform(String action)`
Sends an action command to the Godot body via WebSocket.

```java
public void perform(String action) {
    client.send(action);
}
```

#### `sense(Literal perception)`
Creates an internal signal that triggers agent plans.

```java
private void sense(Literal perception) {
    Message signal = new Message("signal", agName, agName, perception);
    getTS().getAgArch().sendMsg(signal);
}
```

#### `vesnaHandleMsg(String msg)`
Handles incoming messages from Godot body.

```java
public void vesnaHandleMsg(String msg) {
    JSONObject log = new JSONObject(msg);
    String type = log.getString("type");
    JSONObject data = log.getJSONObject("data");
    
    switch(type) {
        case "signal":
            handleEvent(data);    // Creates perception via sense()
            break;
        case "sight":
            handleSight(data);    // Adds belief via addBel()
            break;
    }
}
```

#### `handleEvent(JSONObject event)`
Converts JSON event to Jason literal and triggers perception.

```java
private void handleEvent(JSONObject event) {
    String event_type = event.getString("type");     // e.g., "movement"
    String event_status = event.getString("status"); // e.g., "completed"
    String event_reason = event.getString("reason"); // e.g., "destination_reached"
    
    // Creates: movement(completed, destination_reached)
    Literal perception = createLiteral(event_type, 
        createLiteral(event_status), 
        createLiteral(event_reason));
    sense(perception);
}
```

#### `handleSight(JSONObject sight)`
Adds visual perception as belief.

```java
private void handleSight(JSONObject sight) {
    String object = sight.getString("sight");
    long id = sight.getLong("id");
    
    // Creates belief: sight(object_name, instance_id)
    Literal sight_belief = createLiteral("sight", 
        createLiteral(object), 
        createNumber(id));
    addBel(sight_belief);
}
```

#### `selectOption(List<Option> options)` and `selectIntention(Queue<Intention> intentions)`
Override default selection to use Temper system when applicable.

```java
public Option selectOption(List<Option> options) {
    // Use default if single option or no temper annotations
    if (options.size() == 1 || !areOptionsWithTemper(options))
        return super.selectOption(options);
    
    // Wrap options and select using Temper
    List<OptionWrapper> wrappedOptions = options.stream()
        .map(OptionWrapper::new)
        .collect(Collectors.toList());
    
    return temper.select(wrappedOptions).getOption();
}
```

---

## WebSocket Communication

### WsClient.java

**Location:** `src/agt/vesna/WsClient.java`

A simple WebSocket client extending `WebSocketClient` from Java-WebSocket library.

```java
public class WsClient extends WebSocketClient {
    private WsClientMsgHandler msgHandler;

    public void setMsgHandler(WsClientMsgHandler handler) {
        this.msgHandler = handler;
    }

    @Override
    public void onMessage(String message) {
        if (msgHandler != null)
            msgHandler.handleMsg(message);
    }

    @Override
    public void onError(Exception ex) {
        if (msgHandler != null)
            msgHandler.handleError(ex);
    }
}
```

### WsClientMsgHandler.java

**Location:** `src/agt/vesna/WsClientMsgHandler.java`

Interface for handling WebSocket messages.

```java
public interface WsClientMsgHandler {
    public void handleMsg(String msg);
    public void handleError(Exception ex);
}
```

### Message Protocol

**From Jason → Godot (Actions):**

```json
{
    "sender": "agent_name",
    "receiver": "body",
    "type": "walk | rotate | jump | interact",
    "data": { /* action-specific data */ },
    "propensions": ["trait1", "trait2"]
}
```

**From Godot → Jason (Perceptions):**

```json
{
    "sender": "body",
    "receiver": "vesna",
    "type": "signal | sight",
    "data": { /* perception data */ }
}
```

---

## Internal Actions (via package)

Internal actions are Java classes that execute agent commands and send them to the Godot body.

### walk.java

**Location:** `src/agt/vesna/via/walk.java`

**Usage in ASL:**
```jason
vesna.walk                  // Perform a step
vesna.walk(n)               // Step of length n
vesna.walk(target)          // Go to target
vesna.walk(target, id)      // Go to target with specific id
```

**Implementation:**
```java
public Object execute(TransitionSystem ts, Unifier un, Term[] args) {
    String type = "none";
    if (args.length == 0)
        type = "step";
    else if (args.length == 1) {
        if (args[0].isNumeric())
            type = "step";
        else if (args[0].isLiteral())
            type = "goto";
    }
    // ...
    
    JSONObject data = new JSONObject();
    data.put("type", type);
    if (type.equals("goto"))
        data.put("target", args[0].toString());
    
    JSONObject action = new JSONObject();
    action.put("sender", ts.getAgArch().getAgName());
    action.put("receiver", "body");
    action.put("type", "walk");
    action.put("data", data);
    
    VesnaAgent ag = (VesnaAgent) ts.getAg();
    ag.perform(action.toString());
    return true;
}
```

### rotate.java

**Location:** `src/agt/vesna/via/rotate.java`

**Usage in ASL:**
```jason
vesna.rotate(left)          // Rotate in direction (left/right/forward/backward)
vesna.rotate(target)        // Look at target
vesna.rotate(target, id)    // Look at target with id
```

### jump.java

**Location:** `src/agt/vesna/via/jump.java`

**Usage in ASL:**
```jason
vesna.jump                  // Make a jump
```

---

## CArtAgO Artifacts

Artifacts are environment objects that agents can interact with.

### SituatedArtifact.java

**Location:** `src/env/vesna/SituatedArtifact.java`

Base class for artifacts located in a specific region with usage limits.

```java
public class SituatedArtifact extends Artifact {
    private String region;      // Region where artifact is located
    private String art_name;    // Artifact name
    private int limit;          // Max simultaneous users
    private List<String> using; // Currently using agents

    public void init(String region, int limit) {
        this.region = region;
        this.limit = limit;
        using = new ArrayList<String>();
        this.art_name = getId().getName();
    }

    @OPERATION
    public void use(String ag_region) {
        if (!ag_region.equals(this.region))
            failed("Artifact in another region!");
        if (using.size() >= limit)
            failed("Artifact already in use!");
        
        String ag_name = getCurrentOpAgentId().getAgentName();
        using.add(ag_name);
        
        // Signal body about interaction
        JSONObject action = new JSONObject();
        action.put("type", "interact");
        // ... build and send message
        ag.perform(action.toString());
    }

    @OPERATION
    public void free() {
        String ag_name = getCurrentOpAgentId().getAgentName();
        using.remove(ag_name);
    }
}
```

### GrabbableArtifact.java

**Location:** `src/env/vesna/GrabbableArtifact.java`

Artifact that can be picked up and carried by agents.

```java
public class GrabbableArtifact extends Artifact {
    private String owner;   // Current owner (null if not grabbed)
    private String region;  // Current region
    private String art_name;

    @OPERATION
    public void grab(String ag_region) {
        if (!ag_region.equals(this.region))
            failed("Artifact in another region!");
        if (this.owner != null)
            failed("Artifact already has an owner!");
        
        String ag_name = getCurrentOpAgentId().getAgentName();
        this.owner = ag_name;
        
        // Signal body and add belief
        ag.perform(action.toString());
        ag.addBel(parseLiteral("grab(" + art_name + ")"));
    }

    @OPERATION
    public void release(String ag_region) {
        owner = null;
        this.region = ag_region;  // Dropped in current region
        
        ag.perform(action.toString());
        ag.delBel(parseLiteral("grab(" + art_name + ")"));
    }
}
```

---

## Base Agent Logic (vesna.asl)

**Location:** `src/agt/vesna.asl`

The base AgentSpeak file provides common plans and rules for all VEsNA agents.

### RCC (Region Connection Calculus) Rules

```jason
// Partially Overlapping (bidirectional)
po(X, Y) :- map_po(X, Y).
po(Y, X) :- map_po(X, Y).

// Non-Tangential Proper Part
ntpp(X, Y) :- map_ntpp(X, Y).
ntppi(Y, X) :- map_ntpp(X, Y).

// Externally Connected (bidirectional)
ec(X, Y) :- map_ec(X, Y).
ec(Y, X) :- map_ec(X, Y).

// Check if two regions share a super-region
same_region(Region1, Region2) :- 
    ntpp(Region1, SuperRegion) & ntpp(Region2, SuperRegion).
```

### Navigation Plans

```jason
// Navigate within same region
+!go_to(Target)
    :   .my_name(Me) & same_region(Me, Target)
    <-  vesna.walk(Target, _);
        .wait({+movement(completed, destination_reached)});
        -at(Me, _);
        +at(Me, Target).

// Navigate through a door
+!go_to(Target)
    :   ntpp(Me, MyRegion) & ntpp(Target, TargetRegion) & 
        po(MyRegion, Door) & po(Door, TargetRegion)
    <-  vesna.walk(Door, _);
        .wait({+movement(completed, destination_reached)});
        vesna.walk(TargetRegion, _);
        .wait({+movement(completed, destination_reached)}).

// Follow a path
+!follow_path([])
    <-  .print("Destination reached").

+!follow_path([Head | Tail])
    :   .my_name(Me)
    <-  vesna.walk(Head);
        .wait({+movement(completed, destination_reached)});
        -ntpp(Me, _);
        +ntpp(Me, Head);
        !follow_path(Tail).
```

### Artifact Interaction Plans

```jason
+!use(ArtName)
    :   .my_name(Me) & ntpp(Me, MyRegion)
    <-  lookupArtifact(ArtName, ArtId);
        focus(ArtId);
        use(MyRegion)[artifact_id(ArtId)].

+!grab(ArtName)
    :   .my_name(Me) & ntpp(Me, MyRegion)
    <-  lookupArtifact(ArtName, ArtId);
        grab(MyRegion)[artifact_id(ArtId)].

+!release(ArtName)
    :   .my_name(Me) & ntpp(Me, MyRegion)
    <-  lookupArtifact(ArtName, ArtId);
        release(MyRegion)[artifact_id(ArtId)].
```

### Path Finding

```jason
find_path(Start, Target, Path) :- 
    find_path_recursive(Start, Target, [Start], Path).

find_path_recursive(Target, Target, Visited, Visited).

find_path_recursive(Current, Target, Visited, Path) :- 
    (po(Current, Next) | ec(Current, Next)) & 
    not .member(Next, Visited) & 
    find_path_recursive(Next, Target, [Next | Visited], Path).
```

---

## Creating a New Agent

1. **Create ASL file** (e.g., `myagent.asl`):

```jason
{ include("vesna.asl") }  // Include base functionality

+!start
    <-  .print("Agent started!");
        !main_behavior.

@behavior1[temper([aggression(0.8)]), effects([stress(0.1)])]
+!main_behavior
    :   enemy_nearby
    <-  vesna.walk(enemy).

@behavior2[temper([aggression(0.2)]), effects([stress(-0.1)])]
+!main_behavior
    :   true
    <-  .print("Patrolling");
        vesna.walk(waypoint1).
```

2. **Add to vesna.jcm**:

```jcm
agent myagent:myagent.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(aggression(0.5), stress(0.0)[mood])
    address:    localhost
    port:       9090
    strategy:   most_similar
    goals:      start
}
```

---

## Summary

The Jason side of VEsNA provides:

1. **VesnaAgent**: Extended agent class with WebSocket communication and Temper support
2. **WsClient**: WebSocket client for body communication
3. **Internal Actions**: `vesna.walk`, `vesna.rotate`, `vesna.jump` for movement commands
4. **Artifacts**: `SituatedArtifact` and `GrabbableArtifact` for environment interaction
5. **vesna.asl**: Base agent logic with RCC rules, navigation, and artifact plans
