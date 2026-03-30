# 07 — Runtime Quick Reference

Fast operational map of the project runtime.

---

## 1) Stack at a glance

- **Godot (Bodies + UI):** world simulation, movement, sensing, scene flow, chat UI.
- **Jason/JaCaMo (Minds):** guard reasoning/plans via `.asl` agents.
- **Rasa (Tongue):** NLP intent parsing + social scoring for chat interactions.

---

## 2) Core startup sequence

1. `intro` → `loading_screen`.
2. `loading_screen.gd` starts both Rasa bots via `ServerManager`.
3. Wait until both health checks return `200` (`:5005`, `:5006`).
4. Enter `maze`.
5. `test_maze.gd` starts Jason (`gradle run` in `mind/`).
6. `director` sends `signal_ready` over WebSocket `:9200`.
7. Godot unpauses and begins gameplay.

---

## 3) Scene flow

- `intro` → `loading_screen` → `maze`
- `maze` → `chat` (on encounter)
- `chat` → `maze` (guard/captain) or `ending` (date)

Persistent cross-scene state:
- `libraries/GameManager.gd`

Process/service lifecycle:
- `libraries/ServerManager.gd`

---

## 4) Agents implemented

Configured in `mind/vesna.jcm`:

- **Sentries:** `sentry1` … `sentry8` (ports `9071`…`9078`) → `sentry.asl`
- **Patrols:**
  - `patrol_rosanna` (`9080`)
  - `patrol_susanna` (`9081`)
  - `patrol_polyanna` (`9082`)
  - `patrol_marianna` (`9083`) → `patrol.asl`
- **Captains:**
  - `captain_daniele` (`9090`)
  - `captain_samuele` (`9091`) → `captain.asl`
- **Director:** `director` (`9200`) → `ready_agent.asl`

Shared logic file:
- `mind/src/agt/vesna.asl` (navigation/spatial/path/artifact helpers)

All agents use:
- `ag-class: vesna.VesnaAgent`
- `strategy: most_similar`

---

## 5) Ports and endpoints

### Jason / VEsNA
- WebSocket readiness + director channel: `localhost:9200`

### Rasa skirmish bot (`tongue/skirmish`)
- Core API: `localhost:5005`
- Action server: `localhost:5055`
- Action endpoint configured in `endpoints.yml`

### Rasa date bot (`tongue/date`)
- Core API: `localhost:5006`
- Action server: `localhost:5056`
- Action endpoint configured in `endpoints.yml`

---

## 6) Godot ↔ Rasa contract

Used by `stages/chat/chat_interface.gd`.

### Request sent to Rasa REST webhook

```json
{
  "sender": "godot_player",
  "message": "<player text>"
}
```

### Endpoints selected by mode

- **Guard mode:** `http://localhost:5005/webhooks/rest/webhook`
- **Date mode:** `http://localhost:5006/webhooks/rest/webhook`
- **Captain mode:** no Rasa call (hardcoded branch)

### Expected custom fields

**Skirmish (`ActionEvaluateExcuse`):**
- `sympathy_score`
- `detected_intent`
- `guard_name`

**Date (`ActionEvaluateDate`):**
- `ease_score`
- `suspicion_score`
- `delta_suspicion`
- `detected_intent`
- optional `game_event` (`date_success` | `date_failed`)
- optional `secret_info`

---

## 7) Rasa result → gameplay result

### Guard chat
- `sympathy_score > 0` → `pacified`
- otherwise → `alarm`

### Captain encounter
- always dismissal branch
- forces `alarm`
- applies negative sympathy penalty to mapped captain agent

### Date chat
- `game_event = date_success` → go `ending` with recovered secret
- `game_event = date_failed` → go `ending` with failure

---

## 8) Gameplay state → Jason updates

1. Chat accumulates deltas in `GameManager.sympathy_updates`.
2. On maze return, `test_maze.gd` sends setup payload to director through `ServerManager.send_to_director(...)`.
3. `VesnaAgent.handleSetup()` creates belief `sympathy_updates([...])`.
4. `ready_agent.asl` distributes `update_sympathy(Value)` to target agents.
5. Future plan selection is influenced by updated temper/sympathy values.

---

## 9) Files to open first (debug order)

1. `libraries/ServerManager.gd`
2. `stages/loading_screen/loading_screen.gd`
3. `stages/maze/test_maze.gd`
4. `stages/chat/chat_interface.gd`
5. `libraries/GameManager.gd`
6. `mind/vesna.jcm`
7. `mind/src/agt/ready_agent.asl`
8. `mind/src/agt/vesna/VesnaAgent.java`
9. `tongue/skirmish/actions/actions.py`
10. `tongue/date/actions/actions.py`
