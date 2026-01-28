# VEsNA Framework - Temper System Documentation

This document provides a comprehensive guide to the Temper system, which implements personality and mood-based decision making for VEsNA agents.

---

## Table of Contents

1. [Concept Overview](#concept-overview)
2. [Temper Configuration](#temper-configuration)
3. [Plan Annotations](#plan-annotations)
4. [Selection Algorithms](#selection-algorithms)
5. [Mood Effects](#mood-effects)
6. [Implementation Details](#implementation-details)
7. [Examples](#examples)
8. [Best Practices](#best-practices)

---

## Concept Overview

The Temper system allows agents to have **personality** (persistent traits) and **mood** (dynamic traits) that influence their decision-making when multiple applicable plans exist.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TEMPER SYSTEM                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────┐     ┌─────────────────────────────────┐   │
│  │       PERSONALITY           │     │            MOOD                 │   │
│  │      (Persistent)           │     │          (Dynamic)              │   │
│  │                             │     │                                 │   │
│  │  • Range: [0.0, 1.0]        │     │  • Range: [-1.0, 1.0]           │   │
│  │  • Never changes            │     │  • Changes via effects          │   │
│  │  • Defined at agent start   │     │  • Clamped to valid range       │   │
│  │                             │     │                                 │   │
│  │  Examples:                  │     │  Examples:                      │   │
│  │  • aggression(0.7)          │     │  • stress(-0.2)[mood]           │   │
│  │  • curiosity(0.4)           │     │  • energy(0.8)[mood]            │   │
│  │  • caution(0.6)             │     │  • frustration(0.0)[mood]       │   │
│  └─────────────────────────────┘     └─────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      DECISION STRATEGIES                            │   │
│  │                                                                     │   │
│  │  MOST_SIMILAR (Deterministic):                                      │   │
│  │    Select plan with minimum |agent_trait - plan_trait| distance     │   │
│  │                                                                     │   │
│  │  RANDOM (Probabilistic):                                            │   │
│  │    Weighted random selection based on agent_trait × plan_trait      │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Personality** | Persistent traits (0.0 to 1.0) that never change during execution |
| **Mood** | Dynamic traits (-1.0 to 1.0) that change based on plan effects |
| **Temper Annotation** | Plan label specifying required trait values for selection |
| **Effects Annotation** | Plan label specifying mood changes after plan execution |
| **Strategy** | Algorithm for selecting among applicable plans |

---

## Temper Configuration

### In vesna.jcm

Define agent temper in the JaCaMo project file:

```jcm
agent alice:alice.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper( 
        aggression(0.7),           // Personality trait
        curiosity(0.4),            // Personality trait
        stress(-0.2)[mood],        // Mood trait (initial value)
        energy(0.8)[mood]          // Mood trait (initial value)
    )
    strategy:   most_similar       // or "random"
    address:    localhost
    port:       9080
    goals:      start
}
```

### Trait Syntax

```
trait_name(value)           // Personality trait: value in [0.0, 1.0]
trait_name(value)[mood]     // Mood trait: value in [-1.0, 1.0]
```

### Strategy Options

| Strategy | Type | Description |
|----------|------|-------------|
| `most_similar` | Deterministic | Always selects plan closest to agent's current temper |
| `random` | Probabilistic | Weighted random based on trait alignment |

---

## Plan Annotations

Plans can be annotated with temper requirements and effects.

### Temper Annotation

Specifies the trait values that make this plan more likely to be selected.

```jason
@plan_label[temper([ trait1(value), trait2(value), ... ])]
+!goal
    :   context
    <-  actions.
```

**Example:**
```jason
@aggressive_response[temper([ aggression(0.8), caution(0.1) ])]
+!respond_to_threat
    :   true
    <-  vesna.walk(enemy);
        !attack(enemy).

@cautious_response[temper([ aggression(0.2), caution(0.9) ])]
+!respond_to_threat
    :   true
    <-  vesna.walk(safe_zone);
        !hide.
```

### Effects Annotation

Specifies how mood traits change after executing this plan.

```jason
@plan_label[temper([...]), effects([ mood_trait(delta), ... ])]
+!goal
    :   context
    <-  actions.
```

**Example:**
```jason
@calm_action[
    temper([ stress(0.0) ]), 
    effects([ stress(-0.1), energy(0.05) ])
]
+!rest
    :   true
    <-  .wait(2000);
        .print("I feel better now").
```

After executing this plan:
- `stress` decreases by 0.1 (clamped to [-1.0, 1.0])
- `energy` increases by 0.05

---

## Selection Algorithms

### How Plan Selection Works

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        PLAN SELECTION FLOW                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Agent has goal +!my_goal                                             │
│                    │                                                     │
│                    ▼                                                     │
│  2. Find all applicable plans for +!my_goal                              │
│     ┌────────────────────────────────────────────────────┐              │
│     │  Plan A: @p1[temper([aggr(0.8)])] +!my_goal <- ... │              │
│     │  Plan B: @p2[temper([aggr(0.3)])] +!my_goal <- ... │              │
│     │  Plan C: @p3[temper([aggr(0.5)])] +!my_goal <- ... │              │
│     └────────────────────────────────────────────────────┘              │
│                    │                                                     │
│                    ▼                                                     │
│  3. Check if temper annotations exist                                    │
│     ├─ No temper → Use default Jason selection                          │
│     └─ Has temper → Continue to temper selection                        │
│                    │                                                     │
│                    ▼                                                     │
│  4. Calculate weights for each plan                                      │
│     Agent temper: aggression(0.6)                                       │
│                                                                          │
│     MOST_SIMILAR:                         RANDOM:                        │
│     Plan A: |0.6 - 0.8| = 0.2            Plan A: 0.6 × 0.8 = 0.48       │
│     Plan B: |0.6 - 0.3| = 0.3            Plan B: 0.6 × 0.3 = 0.18       │
│     Plan C: |0.6 - 0.5| = 0.1  ← MIN     Plan C: 0.6 × 0.5 = 0.30       │
│                    │                                                     │
│                    ▼                                                     │
│  5. Select plan                                                          │
│     MOST_SIMILAR: Plan C (smallest distance)                            │
│     RANDOM: Weighted random (Plan A most likely)                        │
│                    │                                                     │
│                    ▼                                                     │
│  6. Apply effects to mood traits                                        │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### MOST_SIMILAR Strategy

Deterministic selection based on minimum distance:

$$\text{selected} = \arg\min_p \sum_{t \in \text{traits}} |T_{\text{agent}}(t) - T_{\text{plan}}(t)|$$

Where:
- $T_{\text{agent}}(t)$ = agent's current value for trait $t$
- $T_{\text{plan}}(t)$ = plan's required value for trait $t$

**Java Implementation:**
```java
private int getMostSimilarIdx(List<Double> weights) {
    double min = Double.MAX_VALUE;
    int minIdx = -1;
    for (int i = 0; i < weights.size(); i++) {
        if (weights.get(i) < min) {
            min = weights.get(i);
            minIdx = i;
        }
    }
    return minIdx;
}
```

### RANDOM Strategy

Probabilistic selection with weighted random:

$$w_p = \sum_{t \in \text{traits}} T_{\text{agent}}(t) \times T_{\text{plan}}(t)$$

Plans with higher positive alignment have higher probability.

**Java Implementation:**
```java
private int getWeightedRandomIdx(List<Double> weights) {
    double min_bound = 0.0;
    double max_bound = 0.0;
    for (double weight : weights) {
        if (weight < 0.0)
            min_bound += weight;
        else
            max_bound += weight;
    }
    double roll = dice.nextDouble(min_bound, max_bound);
    int currentMin = 0;
    for (int i = 0; i < weights.size(); i++) {
        if (roll > currentMin && roll < weights.get(i) + currentMin)
            return i;
        currentMin += weights.get(i);
    }
    return 0;
}
```

---

## Mood Effects

### How Effects Work

After a plan is selected and executed, its `effects` annotation modifies mood traits:

```jason
@stressful_action[
    temper([ energy(0.8) ]), 
    effects([ stress(0.2), energy(-0.1) ])
]
+!fight
    :   true
    <-  !attack(enemy).
```

**Before execution:**
- stress: 0.0
- energy: 0.8

**After execution:**
- stress: 0.0 + 0.2 = 0.2
- energy: 0.8 - 0.1 = 0.7

### Clamping Rules

Mood values are always clamped to the valid range:

```java
if (moodValue + effectValue > 1.0)
    mood.put(traitName, 1.0);
else if (moodValue + effectValue < -1.0)
    mood.put(traitName, -1.0);
else
    mood.put(traitName, moodValue + effectValue);
```

### Important Restrictions

1. **Effects can only modify mood traits**, not personality traits
2. Effect values must be in the range [-1.0, 1.0]
3. If an effect references a personality trait without `[mood]`, an error is thrown:

```java
if (personality.containsKey(traitName) && !effect.hasAnnot(createLiteral("mood")))
    throw new IllegalArgumentException(
        "You used a Personality trait in the post-effects! Use only mood traits."
    );
```

---

## Implementation Details

### Temper.java Class

**Location:** `src/agt/vesna/Temper.java`

```java
public class Temper {
    private enum DecisionStrategy { MOST_SIMILAR, RANDOM }
    
    private Map<String, Double> personality;  // Persistent traits
    private Map<String, Double> mood;         // Dynamic traits
    private DecisionStrategy strategy;
    private Random dice = new Random();

    public Temper(String temper, String strategy) {
        // Parse temper string from JCM
        // Separate personality and mood traits
        // Set decision strategy
    }

    public <T extends TemperSelectable> T select(List<T> choices) {
        // Calculate weights for each choice
        // Select based on strategy
        // Apply effects
        // Return selected choice
    }
}
```

### TemperSelectable Interface

```java
public interface TemperSelectable {
    Pred getLabel();  // Returns plan label with annotations
}
```

### Wrapper Classes

**OptionWrapper.java** - Wraps Jason's `Option` class:
```java
public class OptionWrapper implements TemperSelectable {
    private final Option option;
    
    @Override
    public Pred getLabel() {
        return option.getPlan().getLabel();
    }
    
    public Option getOption() {
        return option;
    }
}
```

**IntentionWrapper.java** - Wraps Jason's `Intention` class:
```java
public class IntentionWrapper implements TemperSelectable {
    private final Intention intention;
    
    @Override
    public Pred getLabel() {
        return intention.peek().getPlan().getLabel();
    }
    
    public Intention getIntention() {
        return intention;
    }
}
```

### Integration in VesnaAgent

```java
public class VesnaAgent extends Agent {
    private Temper temper;

    @Override
    public Option selectOption(List<Option> options) {
        // Skip temper if only one option or no temper annotations
        if (options.size() == 1 || !areOptionsWithTemper(options))
            return super.selectOption(options);
        
        // Wrap options and use temper selection
        List<OptionWrapper> wrapped = options.stream()
            .map(OptionWrapper::new)
            .collect(Collectors.toList());
        
        return temper.select(wrapped).getOption();
    }

    @Override
    public Intention selectIntention(Queue<Intention> intentions) {
        // Similar logic for intention selection
    }
}
```

---

## Examples

### Example 1: Simple Personality-Based Selection

**JCM Configuration:**
```jcm
agent guard:guard.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(aggression(0.8), caution(0.2))
    strategy:   most_similar
    port:       9080
    goals:      start
}
```

**Agent ASL:**
```jason
// Aggressive guard will prefer this plan
@aggressive_patrol[temper([aggression(0.9), caution(0.1)])]
+!patrol
    :   see(intruder)
    <-  !chase(intruder).

// Cautious guard would prefer this plan
@cautious_patrol[temper([aggression(0.3), caution(0.8)])]
+!patrol
    :   see(intruder)
    <-  !raise_alarm;
        !wait_for_backup.

// Default patrol behavior
@default_patrol[temper([aggression(0.5), caution(0.5)])]
+!patrol
    :   true
    <-  !walk_route.
```

### Example 2: Mood Changes Over Time

**JCM Configuration:**
```jcm
agent worker:worker.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(
        diligence(0.7),           // Personality: always works hard
        fatigue(0.0)[mood],       // Mood: starts rested
        satisfaction(0.5)[mood]   // Mood: neutral satisfaction
    )
    strategy:   most_similar
    port:       9081
    goals:      start
}
```

**Agent ASL:**
```jason
// When not tired, work energetically
@work_hard[
    temper([fatigue(-0.5), diligence(0.8)]),
    effects([fatigue(0.2), satisfaction(0.1)])
]
+!do_task
    :   task_available(Task)
    <-  !work_on(Task);
        .print("Completed task energetically!").

// When tired, work slowly
@work_slow[
    temper([fatigue(0.7), diligence(0.5)]),
    effects([fatigue(0.1), satisfaction(-0.1)])
]
+!do_task
    :   task_available(Task)
    <-  !work_on(Task);
        .print("Completed task... slowly").

// Take a break to recover
@take_break[
    temper([fatigue(0.8)]),
    effects([fatigue(-0.5), satisfaction(0.2)])
]
+!do_task
    :   true
    <-  .wait(3000);
        .print("Taking a well-deserved break").
```

**Behavior Over Time:**
1. Worker starts with fatigue=0.0, selects `@work_hard`
2. After several tasks, fatigue increases (0.2 each time)
3. When fatigue > 0.5, `@work_slow` becomes more likely
4. When fatigue > 0.7, `@take_break` becomes most similar
5. Break reduces fatigue, cycle repeats

### Example 3: Competitive Game with Teams

**JCM Configuration:**
```jcm
agent player1:player.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(offensive(0.8), defensive(0.2))
    strategy:   most_similar
    beliefs:    team(red)
    port:       9080
    goals:      start
}

agent player2:player.asl {
    ag-class:   vesna.VesnaAgent
    temper:     temper(offensive(0.3), defensive(0.9))
    strategy:   most_similar
    beliefs:    team(red)
    port:       9081
    goals:      start
}
```

**Agent ASL:**
```jason
// Offensive players go for coins in enemy territory
@play_offensive[temper([offensive(0.8), defensive(0.2)])]
+!play
    :   coin_on_other_side(Coin)
    <-  .print("Going for risky coin!");
        vesna.walk(Coin);
        .wait({+movement(Status, _)}, 10000).

// Defensive players stay on their side
@play_defensive[temper([offensive(0.2), defensive(0.8)])]
+!play
    :   coin_on_my_side(Coin)
    <-  .print("Collecting safe coin");
        vesna.walk(Coin);
        .wait({+movement(Status, _)}, 10000).

// Hunt enemies in our territory
@play_hunter[temper([offensive(0.5), defensive(0.9)])]
+!play
    :   enemy_on_my_side(Enemy)
    <-  .print("Chasing intruder!");
        vesna.walk(Enemy);
        .wait({+movement(Status, _)}, 10000).
```

---

## Best Practices

### 1. Design Meaningful Traits

Choose traits that represent actual behavioral dimensions:

**Good traits:**
- `aggression` / `caution` - How the agent responds to threats
- `curiosity` / `focus` - Exploration vs. task completion
- `social` / `independent` - Team coordination preference

**Avoid:**
- Too many traits (3-5 is usually sufficient)
- Redundant traits (e.g., both `brave` and `not_cowardly`)

### 2. Balance Personality and Mood

- Use **personality** for core character that shouldn't change
- Use **mood** for situational states that fluctuate

```jcm
temper: temper(
    // Personality: Who the agent IS
    courage(0.6),
    intelligence(0.8),
    
    // Mood: How the agent FEELS now
    fear(0.0)[mood],
    excitement(0.0)[mood]
)
```

### 3. Create Fallback Plans

Always have a default plan without temper for edge cases:

```jason
@specific_behavior[temper([trait(0.9)])]
+!goal :- condition <- specific_action.

@fallback_behavior  // No temper annotation
+!goal :- true <- default_action.
```

### 4. Use Effects Sparingly

Small, incremental changes feel more natural:

```jason
// Good: Small incremental change
effects([stress(0.1)])

// Bad: Dramatic swing
effects([stress(0.9)])
```

### 5. Test with Both Strategies

- Use `most_similar` for predictable, debuggable behavior
- Use `random` for more varied, emergent behavior

### 6. Log Temper State for Debugging

Add plans to monitor agent state:

```jason
+!debug_temper
    <-  ?my_temper(Traits);
        .print("Current temper: ", Traits).
```

---

## Summary

The Temper system provides:

1. **Personality traits**: Persistent values [0.0, 1.0] defining agent character
2. **Mood traits**: Dynamic values [-1.0, 1.0] that change based on actions
3. **Plan annotations**: `temper([...])` and `effects([...])` for behavior selection
4. **Selection strategies**: `most_similar` (deterministic) or `random` (probabilistic)
5. **Automatic integration**: Overrides Jason's default plan/intention selection

This enables creating agents with consistent personalities that still exhibit situational variability based on their current emotional state.
