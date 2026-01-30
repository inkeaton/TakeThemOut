# Chase Logic Implementation - Summary

## Overview
Successfully implemented chase logic with player detection and crumb following for patrol agents. The system allows patrols to:
1. Detect and chase the player
2. Follow crumbs when player is lost
3. Switch between player and crumb targets dynamically
4. Give up chase after exhausting crumb trail
5. Return to patrol after chase ends

## Implementation Details

### Phase 1: Vision Detection System (✅ Complete)
**File**: `bodies/guards/patrols/patrol.gd`

**Changes**:
- Added vision tracking variables: `player_visible`, `visible_crumbs`, `seen_crumbs`
- Connected vision cone signals: `body_entered` and `body_exited`
- Implemented detection handlers:
  - `_on_vision_body_entered()`: Detects player and crumbs, sends events to mind
  - `_on_vision_body_exited()`: Tracks when player/crumbs leave vision
- Vision cone rotates to match movement direction in `_physics_process()`

**Key Features**:
- Tracks all seen crumbs with timestamps for "most recent" selection
- Distinguishes between visible crumbs (currently in vision) and seen crumbs (history)
- Sends detailed events to mind with target type and status

---

### Phase 2: Chase State Management (✅ Complete)
**File**: `bodies/guards/patrols/patrol.gd`

**Changes**:
- Added State enum: `PATROLLING`, `CHASING_PLAYER`, `CHASING_CRUMB`, `SEARCHING`
- Added chase tracking variables:
  - `current_state`: Current behavior state
  - `chase_target`: Current chase target node
  - `crumbs_followed_count`: Exhaustion counter
  - `current_chase_crumb`: Specific crumb being chased
  - `max_crumbs_before_giving_up`: Configurable exhaustion limit (default: 3)

**Command Handlers**:
- `chase`: Starts chasing player or specific crumb
- `stop_chase`: Stops chase and halts movement
- `return_patrol`: Returns to patrol state and clears memory

**Control Functions**:
- `start_chase_player()`: Initiates player chase, resets crumb counter
- `start_chase_crumb(crumb_id)`: Initiates crumb chase, increments counter
- `stop_chase()`: Stops all chase movement
- `return_to_patrol()`: Cleans up and returns to patrolling

---

### Phase 3: Crumb Following Logic (✅ Complete)
**File**: `bodies/guards/patrols/patrol.gd`

**Changes**:
- Updated `_physics_process()` to handle dynamic target switching:
  - **CHASING_PLAYER**: Continuously updates player position, switches to crumb if player lost
  - **CHASING_CRUMB**: Monitors for player reappearance, follows crumb target
- Added `get_most_recent_crumb(exclude_crumb)` helper function:
  - Sorts seen crumbs by timestamp (most recent first)
  - Excludes specified crumb (for selecting "next" crumb)
  - Validates crumb nodes are still valid

**Navigation Updates**:
- `_on_navigation_finished()` now handles different states:
  - **PATROLLING**: Normal waypoint arrival notification
  - **CHASING_CRUMB**: Crumb reached notification with exhaustion check
  - **CHASING_PLAYER**: Player position reached notification

---

### Phase 4: Crumb Exhaustion (✅ Complete)
**Implementation**: Integrated into Phase 2 and 3

**Logic**:
- Counter increments each time `start_chase_crumb()` is called
- Counter resets when player becomes visible during chase
- When reaching crumb, checks if `crumbs_followed_count >= max_crumbs_before_giving_up`
- If exhausted, sends `signal_chase(exhausted, ...)` event to mind
- Mind triggers `!stop_chase` goal to end chase

**Configurable**:
```gdscript
@export var max_crumbs_before_giving_up : int = 3
```

---

### Phase 5: Mind Logic (✅ Complete)
**File**: `mind/src/agt/patrol.asl`

**Changes**:
- Added state management: `state(patrolling)` vs `state(chasing)`
- Modified `!patrol` goal to check state before continuing patrol loop

**New Goals & Plans**:

1. **Player Detection**:
   ```jason
   +signal_sight(detected, Data)
       :   .member(target("player"), Data) & not state(chasing)
       <- !set_state(chasing);
          vesna.chase(player).
   ```

2. **Player Re-detection**:
   ```jason
   +signal_sight(redetected, Data)
       :   .member(target("player"), Data) & state(chasing)
       <- -+crumbs_followed(0);  // Reset counter
          vesna.chase(player).
   ```

3. **Switch to Crumb**:
   ```jason
   +signal_chase(switching_to_crumb, Data)
       :   state(chasing) & .member(crumb_id(CrumbId), Data)
       <- vesna.chase(crumb, CrumbId).
   ```

4. **Crumb Reached**:
   ```jason
   +signal_chase(crumb_reached, Data)
       <- !handle_crumb_reached.
   ```

5. **Exhaustion & Termination**:
   ```jason
   +signal_chase(exhausted, Data)
       <- !stop_chase.
   
   +!stop_chase
       <- vesna.stop_chase;
          vesna.return_patrol;
          !set_state(patrolling);
          !patrol.
   ```

**Internal Actions Created**:
- `vesna.chase(player)`: Sends chase command with player target
- `vesna.chase(crumb, CrumbId)`: Sends chase command with specific crumb
- `vesna.stop_chase`: Sends stop_chase command
- `vesna.return_patrol`: Sends return_patrol command

**Files Created**:
- `mind/src/agt/vesna/via/chase.java`
- `mind/src/agt/vesna/via/stop_chase.java`
- `mind/src/agt/vesna/via/return_patrol.java`

---

## Message Flow

### Player Detection Flow
```
Body: vision_cone detects player
Body → Mind: signal_sight(detected, {target: "player"})
Mind: Evaluates plan (+signal_sight handler)
Mind → Body: chase command {type: "chase", data: {target: "player"}}
Body: start_chase_player() → follows player
```

### Player Lost → Crumb Switch Flow
```
Body: player exits vision_cone
Body → Mind: signal_sight(lost, {target: "player"})
Body: Detects best crumb available
Body → Mind: signal_chase(switching_to_crumb, {crumb_id: "Crumb_123"})
Mind: Evaluates plan (+signal_chase(switching_to_crumb) handler)
Mind → Body: chase command {type: "chase", data: {target: "crumb", crumb_id: "Crumb_123"}}
Body: start_chase_crumb("Crumb_123") → follows crumb
```

### Crumb Reached Flow
```
Body: navigation_finished() while CHASING_CRUMB
Body: Increments crumbs_followed_count
Body → Mind: signal_chase(crumb_reached, {crumb_id: "Crumb_123"})
Mind: !handle_crumb_reached waits for follow-up

Body: Checks situation (player visible? more crumbs? exhausted?)
Body → Mind: One of:
  - signal_chase(player_found_at_crumb) → chase player
  - signal_chase(next_crumb_available, {crumb_id: "Crumb_456"}) → chase next
  - signal_chase(no_more_crumbs) → stop chase
  - signal_chase(exhausted, {crumbs_followed: 3}) → stop chase
```

### Exhaustion Flow
```
Body: crumbs_followed_count >= max_crumbs_before_giving_up
Body → Mind: signal_chase(exhausted, {crumbs_followed: 3})
Mind: Evaluates plan (+signal_chase(exhausted) handler)
Mind: !stop_chase goal triggered
Mind → Body: stop_chase command
Mind → Body: return_patrol command
Body: Clears chase memory, returns to PATROLLING state
Mind: -+state(patrolling), resumes !patrol loop
```

---

## Testing Requirements

### Godot Editor Setup (REQUIRED - Apply These Changes)

#### 1. Create Crumb Scene
Create `crumb.tscn`:
- Root: `Area2D` (name: "Crumb")
- Add to group: `crumb`
- Child: `Sprite2D` or `ColorRect` for visual
- Child: `CollisionShape2D`

#### 2. Player Crumb Dropping
Add to player script:
```gdscript
var crumb_scene = preload("res://path/to/crumb.tscn")
var crumb_drop_timer : float = 0.0
var crumb_drop_interval : float = 0.5

func _physics_process(delta):
    # ... existing code ...
    
    if velocity.length() > 0.1:
        crumb_drop_timer += delta
        if crumb_drop_timer >= crumb_drop_interval:
            drop_crumb()
            crumb_drop_timer = 0.0

func drop_crumb():
    var crumb = crumb_scene.instantiate()
    crumb.global_position = global_position
    crumb.name = "Crumb_" + str(Time.get_ticks_msec())
    get_parent().add_child(crumb)
```

#### 3. Configure Vision Cone in patrol.tscn
Open `patrol.tscn` in editor:
- Select `VisionCone` node
- Set appropriate CollisionShape2D (wedge/sector shape)
- Configure Collision Layer/Mask to detect:
  - Player (group: `player`)
  - Crumbs (group: `crumb`)
- Position slightly forward from patrol body
- Ensure it can rotate freely

#### 4. Verify Groups
- Player must be in group: `player`
- Crumbs must be in group: `crumb`
- Waypoints must be in group: `waypoints`

---

## Testing Procedure

### 1. Build and Run Mind
```bash
cd /home/inkeaton/Documenti/Godot/take-them-out/mind
gradle build
gradle run
```

### 2. Run Godot Scene
- Open project in Godot
- Run `test_maze.tscn`
- Both patrols should connect and start patrolling

### 3. Test Scenarios

**Scenario A: Basic Chase**
1. Move player into patrol vision cone
2. Expected: Patrol chases player
3. Console: "PLAYER DETECTED! Starting chase..."

**Scenario B: Crumb Following**
1. Patrol chases player
2. Move player out of vision (but leave crumb trail)
3. Expected: Patrol switches to following crumbs
4. Console: "Player lost, switching to crumb: Crumb_XXX"

**Scenario C: Player Re-detection**
1. Patrol following crumbs
2. Move player back into vision
3. Expected: Patrol immediately switches back to player
4. Console: "Player re-detected during crumb chase!"

**Scenario D: Exhaustion**
1. Patrol follows 3+ crumbs without seeing player
2. Expected: Patrol gives up and returns to waypoint patrol
3. Console: "Chase exhausted after following 3 crumbs."

**Scenario E: Return to Patrol**
1. After any chase ends
2. Expected: Patrol resumes normal waypoint loop
3. Console: "Returning to patrol" → "Patrolling forward..."

---

## Configuration Options

### Body (patrol.gd)
```gdscript
@export var max_crumbs_before_giving_up : int = 3  # Exhaustion limit
@export var speed : float = 80.0                    # Movement speed
@export var navigation_tolerance : float = 50.0     # Target arrival distance
```

### Mind (patrol.asl)
- Temper-based behavior still applies during patrol
- Chase logic is state-based (no temper variants yet)
- Can extend with temper-based chase aggressiveness

---

## Expected Console Output Examples

### Player Detection
```
[PatrolBody] Player detected!
[Mind] PLAYER DETECTED! Starting chase...
[Mind] Step decision made. (patrol interrupted)
```

### Crumb Switch
```
[PatrolBody] Player lost from sight
[PatrolBody] Player lost, switching to crumb: Crumb_1738257841234
[Mind] Player lost, switching to crumb: Crumb_1738257841234
[Mind] Following next crumb: Crumb_1738257841234
```

### Crumb Progress
```
[PatrolBody] Reached crumb: Crumb_1738257841234
[Mind] Reached crumb: Crumb_1738257841234
[Mind] Checking for next chase target...
[PatrolBody] Next crumb available: Crumb_1738257842567
[Mind] Following next crumb: Crumb_1738257842567
[PatrolBody] Starting chase: CRUMB Crumb_1738257842567 (count: 2/3)
```

### Exhaustion
```
[PatrolBody] Reached crumb: Crumb_1738257843890
[PatrolBody] Crumb exhaustion limit reached!
[Mind] Chase exhausted after following 3 crumbs.
[Mind] Stopping chase, returning to patrol.
[PatrolBody] Stopping chase
[PatrolBody] Returning to patrol
[Mind] Patrolling forward...
```

---

## Known Limitations & Future Enhancements

### Current Limitations
1. Vision cone doesn't account for obstacles (uses Area2D overlap only)
2. No temper-based chase behavior (all patrols chase identically)
3. Crumb memory persists until return_patrol (no timeout)
4. No coordinated multi-patrol chases

### Suggested Enhancements
1. **Temper-Based Chase**:
   - Aggressive: Longer pursuit, more crumbs before giving up
   - Lazy: Shorter pursuit, fewer crumbs

2. **Coordinated Chase**:
   - Share player LKP between nearby patrols
   - Call for backup when player detected

3. **Smarter Crumb Following**:
   - Predict player direction from crumb trail
   - Skip intermediate crumbs if player trail is clear

4. **Vision Improvements**:
   - Raycast-based vision for obstacle occlusion
   - Dynamic vision cone size based on lighting/temper

---

## Files Modified/Created

### Modified
- `bodies/guards/patrols/patrol.gd` (major changes: 200+ lines added)
- `mind/src/agt/patrol.asl` (major changes: 70+ lines added)

### Created
- `mind/src/agt/vesna/via/chase.java` (new internal action)
- `mind/src/agt/vesna/via/stop_chase.java` (new internal action)
- `mind/src/agt/vesna/via/return_patrol.java` (new internal action)

---

## Compilation Status
✅ All Java files compile successfully
✅ No errors in patrol.asl
✅ Minor warning in patrol.gd (unused parameter in update_animation - expected)

---

## Next Steps
1. **Apply Godot Editor changes** (crumb scene, player script, vision cone)
2. **Test basic chase** (player detection → chase)
3. **Test crumb following** (player loss → crumb trail)
4. **Test exhaustion** (3+ crumbs → return to patrol)
5. **Tune parameters** (max_crumbs_before_giving_up, speed, etc.)
6. **Consider temper enhancements** (optional)
