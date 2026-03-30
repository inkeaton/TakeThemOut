# Agent Style Guide (Uniform `.asl` Conventions)

This document defines a **single style standard** for all Jason agents in this project, with focus on:
- consistent structure,
- predictable message protocols,
- stable temper-based plan selection,
- easier maintenance across `captain`, `patrol`, `sentry`, and `director` roles.

---

## 1) Scope and goals

Use this guide when creating or refactoring files in `mind/src/agt/*.asl`.

Goals:
1. Keep behavior role-specific, but style identical.
2. Make plan competition deterministic and readable.
3. Make state cleanup explicit and symmetrical.
4. Prevent protocol drift in squad communication.

---

## 2) Canonical file layout (all agents)

Every agent file should follow the same section order (even if some sections are tiny):

1. **Bootstrap**
   - initial goal (`!start` or `!start_patrol`)
2. **Knowledge & State Management**
   - initial beliefs
   - supersede/update rules (`+belief(New) : belief(Old) & Old \== New <- -belief(Old).`)
3. **Main Role Loop**
   - patrol / scan / coordination core behavior
4. **Direct Detection/Reactivity**
   - `+sight(...)`, immediate reaction goals
5. **Incoming Alerts & Reports**
   - `+player_spotted_at(...)`, `+!report_sightings...`
6. **Recovery & Reset**
   - target lost, investigation complete, state reset helpers
7. **Setup/Configuration Hooks**
   - `+!update_sympathy(...)`, startup sync signals
8. **Fallback / Failure handlers**
   - `-!goal` handlers near end of file

> Rule: Keep section headers identical across files for fast scanning.

---

## 3) Naming conventions

### 3.1 Plan labels

Use:

`@<phase>_<archetype>`

Examples:
- `@analyze_default`
- `@chase_aggressive`
- `@alert_lazy`
- `@recover_default`

Avoid mixing synonyms for the same archetype across files unless there is a true semantic difference.

### 3.2 Archetype dictionary (project-wide)

Prefer this fixed set:
- `default`
- `aggressive`
- `fearful`
- `lazy`
- `sympathetic`
- optional role flavor tags (only if needed): `warlord`, `corrupt`, `vengeful`

If role flavor is used, include the base archetype in comments, e.g.:
- `@chase_warlord` with comment `Aggressive variant`.

### 3.3 Goals and events

Use verb-first names:
- `!gather_intel`, `!act_on_intel`, `!respond_to_alert`, `!reset_after_investigation`.

Use nouns for beliefs:
- `is_chasing(no)`, `responding_to_alert(yes)`, `last_player_pos(X,Y)`.

---

## 4) Temper annotation rules

Temper selection is done on competing applicable plans. To keep comparisons stable:

1. For one decision family (same trigger/goal), keep trait vectors comparable.
   - Example family: all `+!start_chase` plans.
2. Include a clear **default** plan in every family.
3. Use `effects([...])` only for mood traits (e.g. `fear`, `sympathy` if configured as mood).
4. Keep annotation order stable: `temper([...]), effects([...])`.

### 4.1 Decision family template

```jason
@phase_variant_a[temper([aggressiveness(0.8), fear(0.0)]), effects([fear(-0.05)])]
+!some_goal
    <-  ... .

@phase_variant_b[temper([aggressiveness(0.2), fear(0.8)])]
+!some_goal
    <-  ... .

@phase_default[temper([aggressiveness(0.5), fear(0.0)])]
+!some_goal
    <-  ... .
```

---

## 5) Message protocol uniformity

Define protocol semantics once and enforce the same handling style in each file.

### 5.1 Standard messages

- `player_spotted_at(X, Y)`
  - Producer: sentry/patrol/captain
  - Consumer: patrol/captain/sentry
  - Must include anti-loop rule when rebroadcasting

- `sighting_report(pos(X, Y) | none)`
  - Producer: patrol/sentry
  - Consumer: captain

- `report_sightings` (achieve)
  - Producer: captain
  - Consumer: patrol/sentry

### 5.2 Anti-echo rule (rebroadcast)

When relaying alerts, use the same guard pattern everywhere:

```jason
.term2string(Sender, SenderStr);
if (not .substring("captain", SenderStr)) {
    .broadcast(tell, player_spotted_at(X, Y));
}
```

If role-specific constraints differ, keep structure identical and document exception in one line.

---

## 6) State lifecycle and cleanup

### 6.1 Supersede pattern (required)

For mutable singleton beliefs:

```jason
+belief(S) : belief(Old) & Old \== S <- -belief(Old).
```

### 6.2 Reset pattern (required)

Prefer dedicated reset goal instead of inlining repeated cleanup in many plans:

```jason
+!reset_after_investigation
    <-  -is_chasing(_); +is_chasing(no);
        -responding_to_alert(_); +responding_to_alert(no);
        -last_player_pos(_, _);
        -consecutive_failures(_); +consecutive_failures(0).
```

Then call `!reset_after_investigation` from completion events.

### 6.3 Event consumption

If an event should not persist, retract it in the handling plan:

```jason
+player_spotted_at(X, Y)[source(Sender)]
    <-  ...;
        -player_spotted_at(X, Y)[source(Sender)].
```

---

## 7) Comment and documentation style

### 7.1 Section headers

Use block separators consistently:

```jason
// =============================================================================
// INCOMING ALERTS
// =============================================================================
```

### 7.2 Plan comment style

One short intent line above each variant family:
- what this variant means,
- what trait it expresses,
- optional side effects.

Avoid long narrative comments unless behavior is non-obvious.

### 7.3 Inline comments

Only for protocol guards, engine constraints, or safety-critical logic.

---

## 8) Role templates

## 8.1 Captain skeleton

```jason
!start_patrol.

consecutive_failures(0).
is_chasing(no).
responding_to_alert(no).

+is_chasing(S) : is_chasing(Old) & Old \== S <- -is_chasing(Old).

+!start_patrol <- vesna.transition_to("Patrol", [target("next")]).
+!patrol <- !gather_intel.

@analyze_default[temper([sympathy(0.0), laziness(0.5), fear(0.0)])]
+!analyze_intel <- ... .

@chase_default[temper([sympathy(0.0), aggressiveness(0.5), fear(0.0)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <- ... .

+!reset_after_investigation <- ... .
```

## 8.2 Patrol skeleton

```jason
!start_patrol.

is_chasing(no).
responding_to_alert(no).
is_messenger(no).

+!patrol <- !decide_next_step.

@step_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!decide_next_step <- vesna.transition_to("Patrol", [target("next")]).

+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <- +is_chasing(yes); !start_chase.

+!reset_after_investigation <- ... .
```

## 8.3 Sentry skeleton

```jason
!start.

@player_seen_default[temper([aggressiveness(0.5), fear(0.0)])]
+sight(player, Id, pos(X, Y))
    <- !alert_about_player(X, Y).

@alert_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0)])]
+!alert_about_player(X, Y)
    <- +last_player_pos(X, Y);
       vesna.transition_to("Alert", [duration(5)]).
```

## 8.4 Director/ready skeleton

```jason
!start.

+!start <- .wait(1000); vesna.signal_ready.

+sympathy_updates(List)
    <- !distribute_updates(List).

+!distribute_updates([]).
+!distribute_updates([[Agent, Value] | Rest])
    <- .send(Agent, achieve, update_sympathy(Value));
       !distribute_updates(Rest).
```

---

## 9) Uniformity checklist (use before commit)

- [ ] File sections follow canonical order.
- [ ] Every decision family has explicit `default` variant.
- [ ] Competing variants use comparable trait axes.
- [ ] `effects([...])` only modifies mood traits.
- [ ] Mutable singleton beliefs have supersede rules.
- [ ] Alert/report events are consumed (retracted) consistently.
- [ ] Relay logic uses anti-echo guard where needed.
- [ ] Recovery path resets all role-critical state.
- [ ] Plan labels follow `@phase_archetype` naming.
- [ ] Comments are concise and behavior-focused.

---

## 10) Migration plan (recommended order)

1. Normalize section headers and ordering in all `.asl` files.
2. Normalize plan labels and archetype naming.
3. Normalize decision-family defaults and trait vectors.
4. Extract repeated reset logic into reset goals.
5. Standardize message protocol guards + cleanup.
6. Re-run behavioral tests/scenarios in Godot.

---

## 11) Implementation note for engine consistency

Current codebase note:
- `mind/src/agt/vesna/VesnaAgent.java` checks `temper(...)` in option selection,
- but checks `propensions(...)` in intention selection (`areIntentionsWithTemper`).

If intention-level temper selection is expected everywhere, this should be aligned in engine code.

(Analysis note only; this guide does not change runtime behavior.)
