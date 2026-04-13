# 06 — Project Architecture Overview

This document summarizes how the whole project works across:
- **Bodies** (Godot gameplay and NPC execution)
- **Minds** (Jason/JaCaMo agents + VEsNA bridge)
- **Tongue** (Rasa conversational bots)

It is intended as a practical end-to-end reference.

---

## 1) High-level architecture

The project is a 3-layer game AI stack:

1. **Godot (Bodies/UI/Scenes)**
   - Runs the game world, movement, sensing, collisions, state machines, and chat UI.
   - Starts/stops external services (Rasa + Jason) through `ServerManager.gd`.

2. **Jason/JaCaMo (Minds)**
   - Executes deliberative guard logic in `.asl` plans.
   - Receives world events from Godot and sends high-level commands back.
   - Uses **temper-driven selection** through custom `VesnaAgent` integration.

3. **Rasa (Tongue/NLP)**
   - Handles natural language interactions in chat scenes.
   - Produces social/gameplay scores and events that feed back into Godot and then Jason.

---

## 2) Main runtime lifecycle

### A. Game boot

1. `stages/intro/intro.gd` sends player to `stages/loading_screen/LoadingScreen.tscn`.
2. `stages/loading_screen/loading_screen.gd`:
   - Calls `ServerManager.kill_orphans_on_ports()`
   - Starts Rasa services:
     - Skirmish core `:5005`
     - Skirmish actions `:5055`
     - Date core `:5006`
     - Date actions `:5056`
   - Polls `http://localhost:5005` and `http://localhost:5006` until both are ready.
3. Scene transitions to `stages/maze/test_maze.tscn`.

### B. Maze start

1. `stages/maze/test_maze.gd` starts the Jason mind via `ServerManager.start_jason_server()`.
2. `libraries/ServerManager.gd` listens on WebSocket port `9200` for readiness.
3. `director` agent (`ready_agent.asl`) sends `vesna.signal_ready`.
4. When `signal_ready` arrives, Godot emits `jason_service_ready`, unpauses gameplay, and sends pending sympathy setup if available.

### C. Encounter/chat loop

1. Maze triggers encounter and stores target guard in `GameManager.target_guard_name`.
2. Scene changes to `stages/chat/chat_interface.tscn`.
3. `chat_interface.gd` selects mode:
   - **GUARD** → skirmish bot (`:5005`)
   - **DATE** (`eugenia`) → date bot (`:5006`)
   - **CAPTAIN** (`daniele`, `samuele`) → no Rasa call, immediate dismissal branch
4. On exit from chat:
   - Returns to maze (guard/captain) or ending screen (date)
  - Updates `GameManager` state (sympathy deltas, date outcome)

### D. Next maze load

1. Maze waits for Jason readiness again.
2. It sends setup payload to director with accumulated sympathy deltas.
3. Director distributes `update_sympathy(Value)` to specific agents.

---

## 3) Implemented agents (Jason side)

Configured in `mind/vesna.jcm`.

### Shared base

- `mind/src/agt/vesna.asl`
  - Spatial/RCC rules (`po`, `ec`, `ntpp`), path finding (`find_path`), movement plans (`!go_to`, `!follow_path`), and artifact interaction helpers.
  - Included by role agents to reuse navigation/world logic.

### Role agents

- `mind/src/agt/sentry.asl`
  - Static watch behavior, local detection, alarm forwarding, recovery.
  - Typically escalates sightings to captains.

- `mind/src/agt/patrol.asl`
  - Roaming/route behavior, target chase/investigate transitions, alert handling.
  - Acts as mobile responder in guard loop.

- `mind/src/agt/captain.asl`
  - Coordination role: consumes reports, decides escalation/intercept behavior, command-level responses.

- `mind/src/agt/ready_agent.asl` (agent name: `director`)
  - Startup synchronization with Godot (`signal_ready`).
  - Receives `sympathy_updates(List)` and dispatches `update_sympathy(Value)` to squad agents.

### Active instantiated agents (`vesna.jcm`)

- **Sentries:** `sentry1`…`sentry8` (ports `9071`…`9078`)
- **Patrols:** `patrol_rosanna`, `patrol_susanna`, `patrol_polyanna`, `patrol_marianna` (ports `9080`…`9083`)
- **Captains:** `captain_daniele`, `captain_samuele` (ports `9090`, `9091`)
- **Director:** `director` (port `9200`)

All use `ag-class: vesna.VesnaAgent` and temper strategy `most_similar`.

---

## 4) Godot ↔ Jason (VEsNA bridge)

### Bridge components

- `mind/src/agt/vesna/VesnaAgent.java`
  - Custom Jason agent class.
  - Converts incoming JSON from Godot into beliefs/events.
  - Handles setup payload (`handleSetup`) and creates belief `sympathy_updates([...])`.
  - Overrides option/intention selection to integrate Temper logic.

- `libraries/ServerManager.gd`
  - Starts Jason with `gradle run` in `mind/`.
  - Hosts readiness WebSocket on `9200`.
  - Receives `signal_ready`, emits `jason_service_ready` in Godot.
  - Sends setup JSON back to director through `send_to_director(data)`.

### Practical effect

Godot runs the simulation clock and perceives events; Jason runs the decision logic for guards and returns actions/intents through the bridge.

---

## 5) Tongue folder (Rasa bots)

There are two independent bots:

1. `tongue/skirmish`
   - Purpose: one-turn guard confrontation scoring.
   - Main action: `ActionEvaluateExcuse` in `actions/actions.py`.
   - Endpoint config: actions at `http://localhost:5055/webhook`.

2. `tongue/date`
   - Purpose: multi-turn social engineering/date progression.
   - Main action: `ActionEvaluateDate` in `actions/actions.py`.
   - Endpoint config: actions at `http://localhost:5056/webhook`.

Both bots include:
- `config.yml` (NLU pipeline with SpaCy + DIET + fallback)
- `domain.yml` (intents/slots/actions)
- `data/nlu.yml`, `data/rules.yml`, `data/stories.yml`

Rules route intents directly to custom actions (minimal story branching).

---

## 6) Godot ↔ Rasa integration details

Implemented mainly in `stages/chat/chat_interface.gd`.

### Outgoing request shape

Godot sends:

```json
{
  "sender": "godot_player",
  "message": "<player text>"
}
```

- Guard mode uses `http://localhost:5005/webhooks/rest/webhook`.
- Date mode uses `http://localhost:5006/webhooks/rest/webhook`.
- In guard mode, Godot first sends a hidden `/inform{"guard_name":"<name>"}` to set context.

### Incoming response shape used by Godot

Godot consumes:
- `text` (dialog line)
- `custom` object fields

Skirmish custom fields (used):
- `sympathy_score`
- `detected_intent`
- `guard_name`

Date custom fields (used):
- `ease_score`
- `suspicion_score`
- `delta_suspicion`
- `detected_intent`
- optional `game_event` (`date_success` / `date_failed`)
- optional `secret_info`

### Gameplay coupling

- **Guard outcome:** `sympathy_score > 0` pacifies, else alarm.
- **Captain outcome:** fixed alarm + negative sympathy penalty (no Rasa).
- **Date outcome:** success/failure drives ending scene and recovered secret.

---

## 7) Data flow from Rasa into Jason temper/sympathy

1. Chat computes deltas and stores them in `GameManager.sympathy_updates` keyed by Jason agent name.
2. On maze return, `test_maze.gd` builds setup payload from `GameManager.get_sympathy_payload()`.
3. Payload is sent through `ServerManager.send_to_director(...)`:

```json
{
  "sender": "body",
  "receiver": "director",
  "type": "setup",
  "data": {
    "sympathies": [
      { "agent": "patrol_rosanna", "value": 0.4 }
    ]
  }
}
```

4. `VesnaAgent.handleSetup()` converts this to belief `sympathy_updates([...])`.
5. `ready_agent.asl` forwards each value as `update_sympathy(Value)` to target agents.
6. Agents then adapt future behavior via temper/sympathy-aware plan selection.

---

## 8) Scene-level relation map (Godot)

- `intro` → `loading_screen` → `maze`
- `maze` ↔ `chat`
- `chat` (date branch) → `ending`

Cross-scene persistent state lives in `libraries/GameManager.gd`.
Process lifecycle and external service control live in `libraries/ServerManager.gd`.

---

## 9) Why this architecture works

- **Separation of concerns:**
  - Godot = execution, physics, UI, pacing
  - Jason = symbolic deliberation and squad AI
  - Rasa = language understanding and social scoring
- **Loose coupling by message contracts:** JSON over HTTP/WebSocket keeps systems replaceable.
- **Persistent adaptation loop:** Conversation outcomes affect future agent dispositions (sympathy/temper), creating continuity across encounters.

---

## 10) Key files index

### Godot
- `libraries/ServerManager.gd`
- `libraries/GameManager.gd`
- `stages/loading_screen/loading_screen.gd`
- `stages/maze/test_maze.gd`
- `stages/chat/chat_interface.gd`
- `stages/ending/ending_screen.gd`

### Jason / VEsNA
- `mind/vesna.jcm`
- `mind/src/agt/vesna.asl`
- `mind/src/agt/sentry.asl`
- `mind/src/agt/patrol.asl`
- `mind/src/agt/captain.asl`
- `mind/src/agt/ready_agent.asl`
- `mind/src/agt/vesna/VesnaAgent.java`

### Rasa
- `tongue/skirmish/config.yml`
- `tongue/skirmish/domain.yml`
- `tongue/skirmish/data/nlu.yml`
- `tongue/skirmish/data/rules.yml`
- `tongue/skirmish/actions/actions.py`
- `tongue/skirmish/endpoints.yml`
- `tongue/date/config.yml`
- `tongue/date/domain.yml`
- `tongue/date/data/nlu.yml`
- `tongue/date/data/rules.yml`
- `tongue/date/actions/actions.py`
- `tongue/date/endpoints.yml`
