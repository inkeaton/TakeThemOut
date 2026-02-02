// patrol.asl - Patrol agent with waypoint navigation and player pursuit

// =============================================================================
// INITIAL GOAL
// =============================================================================

!patrol.

// =============================================================================
// KNOWLEDGE BELIEFS 
// =============================================================================

// Track consecutive failures to increase fear
consecutive_failures(0).

// Track whether captain has been alerted during current chase
captain_alerted(no).

// Track whether we are responding to an alert 
// This prevents race conditions during hesitation waits
responding_to_alert(no).

// when new captain_alerted status arrives, remove old one
+captain_alerted(Status) : captain_alerted(OldStatus) & OldStatus \== Status
    <-  -captain_alerted(OldStatus).

// when new responding_to_alert status arrives, remove old one
+responding_to_alert(Status) : responding_to_alert(OldStatus) & OldStatus \== Status
    <-  -responding_to_alert(OldStatus).

// when new position arrives, remove old one
// we always want to keep the latest known position, to inform the captain correctly
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// =============================================================================
// PATROL LOOP
// =============================================================================

// Main patrol goal - decide next step based on personality
+!patrol
    <-  !decide_next_step.

// HIGH FEAR: Hold position/seek safety
@patrol_scared[temper([fear(0.8)])]
+!decide_next_step
    <-  .print("I'm staying right here until things calm down...");
        .wait(5000);
        !decide_next_step.

// MEDIUM FEAR: Cautious backtracking
@patrol_defensive[temper([fear(0.5)]), effects([fear(-0.02)])]
+!decide_next_step
    <-  .print("Something feels off. Checking our six...");
        vesna.patrol(prev).

// LOW FEAR: Standard patterns based on aggressiveness
@go_next_calm[temper([aggressiveness(0.1), fear(0.1)]), effects([fear(-0.01)])]
+!decide_next_step
    <-  .print("Patrolling forward...");
        vesna.patrol(next).

// Aggressive Checks - occasional backtracking (low fear)
@go_prev_low[temper([aggressiveness(0.3), fear(0.2)])]
+!decide_next_step : .random(R) & R < 0.1
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.patrol(prev).

@go_prev_mid[temper([aggressiveness(0.5), fear(0.2)])]
+!decide_next_step : .random(R) & R < 0.3
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.patrol(prev).

@go_prev_high[temper([aggressiveness(0.9), fear(0.2)])]
+!decide_next_step : .random(R) & R < 0.5
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.patrol(prev).

// =============================================================================
// NAVIGATION HANDLERS (React to body movement events)
// =============================================================================

// Arrived at patrol waypoint, rest then continue
// GUARD: Only restart patrol if NOT tracking player AND NOT responding to alert
@navigation_safe[effects([fear(-0.02)])]
+navigation(reached, Waypoint) : not tracking_player & responding_to_alert(no)
    <-  .print("Arrived at ", Waypoint);
        -navigation(reached, Waypoint);
        !rest_at_waypoint;
        !patrol.

// Arrived at waypoint while responding to alert - just acknowledge, don't restart patrol
+navigation(reached, Waypoint) : tracking_player | responding_to_alert(yes)
    <-  .print("Arrived at ", Waypoint, " (alert active, not resuming patrol)");
        -navigation(reached, Waypoint).

// Arrived at target location (from alert or move_to)
// Clear responding_to_alert since we've arrived at alert destination
+navigation(reached_target, Coords)
    <-  .print("Arrived at target location. Investigating.");
        -navigation(reached_target, Coords);
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.investigate(2).

// =============================================================================
// REST BEHAVIOR (Fear modulates personality)
// =============================================================================

// Lazy + Scared = Paralyzed
@rest_paralyzed[temper([laziness(0.8), fear(0.7)])]
+!rest_at_waypoint
    <-  .print("I'm... I'm not moving. Too dangerous.");
        .wait(10000).

// Diligent + Scared = Hypervigilant
@rest_vigilant[temper([laziness(0.2), fear(0.7)]), effects([fear(-0.03)])]
+!rest_at_waypoint
    <-  .print("Can't rest. Must stay alert.");
        .wait(500).

// Lazy + Calm = Normal long rest
@lazy_rest_calm[temper([laziness(0.8), fear(0.2)])]
+!rest_at_waypoint
    <-  .print("Ugh, my feet hurt. Taking a long break...");
        .wait(5000).

// Diligent + Calm = Normal quick move
@active_rest_calm[temper([laziness(0.2), fear(0.2)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving on immediately.");
        .wait(1000).

// Default: Standard pause
@default_rest
+!rest_at_waypoint
    <-  .print("Just a standard pause.");
        .wait(2000).

// =============================================================================
// PLAYER DETECTION (Fear modulates aggressiveness)
// =============================================================================

// Aggressive + Brave = Fearless pursuit
@chase_fearless[temper([aggressiveness(0.8), fear(0.1)]), effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("PLAYER DETECTED! HUNT THEM DOWN!");
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(20).

// Aggressive + Scared = Desperate attack
@chase_desperate[temper([aggressiveness(0.8), fear(0.7)]), effects([fear(0.15)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("THERE THEY ARE! I NEED TO END THIS!");
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(12).

// Lazy + Scared = Retreat/Minimal effort 
@chase_retreat[temper([aggressiveness(0.2), fear(0.7)]), effects([fear(0.2)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("Player detected. Too scary, I'll just check briefly...");
        +tracking_player;
        +last_player_pos(X, Y);
        vesna.investigate(1).

// Lazy + Medium Fear = Hesitant pursuit
@chase_lazy[temper([aggressiveness(0.2), fear(0.3)]), effects([fear(0.08)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("Player detected. I'll take a look, I guess...");
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(4).

// Default: Standard chase
@chase_default[effects([fear(0.1)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("Player detected! Engaging.");
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(8).

// Update position if already chasing (don't send new chase command)
+sight(player, Id, pos(X, Y)) : tracking_player
    <-  .print("Still tracking player. Position updated.");
        -last_player_pos(_, _);
        +last_player_pos(X, Y).

// =============================================================================
// TARGET LOST 
// =============================================================================

// High fear + Lazy = Token effort
@recover_scared_lazy[temper([laziness(0.8), fear(0.7)]), effects([fear(0.08)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("They're gone. Probably far away. I'm done here.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.investigate(1).

// High fear + Diligent = Paranoid search
@recover_paranoid[temper([laziness(0.2), fear(0.8)]), effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Must check EVERYWHERE. They could be hiding!");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.investigate(8).

// Low fear + Diligent = Thorough investigation
@recover_diligent_calm[temper([laziness(0.2), fear(0.2)]), effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. I will comb the area!");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.investigate(5).

// Low fear + Lazy = Minimal check
@recover_lazy_calm[temper([laziness(0.8), fear(0.2)]), effects([fear(0.08)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. I'll verify quickly.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.investigate(2).

// Default: Standard investigation
@recover_default[effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. Checking the area.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        // Log repeated failures
        if (N > 2) { .print("This is the ", N+1, "th time they've slipped away..."); };
        vesna.investigate(3).

// =============================================================================
// INVESTIGATION COMPLETE (Resume patrol, reduce fear, reset failures)
// =============================================================================

@investigation_done[effects([fear(-0.08)])]
+investigation(complete, Reason) : consecutive_failures(N)
    <-  .print("Investigation finished (", Reason, "). Nothing found.");
        -investigation(complete, Reason);
        -tracking_player;  // Clear tracking state
        -responding_to_alert(_);  // Clear alert response state
        +responding_to_alert(no);
        -last_player_pos(_, _);  // Clear last known position
        -consecutive_failures(N);
        +consecutive_failures(0);  // Reset on successful completion
        -captain_alerted(_);  // Reset captain alert status
        +captain_alerted(no);
        .abolish(sight(player, _, _));  // Clean up sight beliefs
        vesna.lock(release);  // Release body lock
        vesna.patrol(resume);
        !patrol.

// =============================================================================
// PATROL COORDINATION (When chasing patrols meet idle patrols)
// =============================================================================

// Handle empty ally list explicitly to prevent .member() failure
+allies_nearby([]) : tracking_player
    <-  .print("Scanned for allies, none found.");
        -allies_nearby([]).

// CHASER: Found idle patrol allies while tracking player
// Share our position and captain alert status so they can coordinate
// Once we share, we assume ally will handle captain alert if needed
+allies_nearby(AllyList) : tracking_player & last_player_pos(X, Y) & captain_alerted(Status) & not .empty(AllyList)
    <-  .print("Spotted idle patrol allies while chasing: ", AllyList);
        .member(Ally, AllyList);  // Iterate through all allies
        .send(Ally, tell, chase_coordination(X, Y, Status));
        -allies_nearby(AllyList);
        // Assume coordination will alert captain if needed
        -captain_alerted(_);
        +captain_alerted(yes).

// Fallback: If we don't have position info, just acknowledge
+allies_nearby(AllyList) : tracking_player
    <-  .print("Spotted allies but no position info to share.");
        -allies_nearby(AllyList).

// RECEIVER: Another patrol is chasing and needs coordination
// If captain not alerted, we alert captain then join chase
// If captain already alerted, we just join the chase
+chase_coordination(X, Y, no)[source(Chaser)] : not tracking_player
    <-  .print("Coordination from ", Chaser, ": Captain NOT alerted. I'll alert and join!");
        -chase_coordination(X, Y, no)[source(Chaser)];
        !alert_captain_directly(X, Y);
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        +captain_alerted(yes);
        vesna.move_to(X, Y).

+chase_coordination(X, Y, yes)[source(Chaser)] : not tracking_player
    <-  .print("Coordination from ", Chaser, ": Captain already alerted. Joining chase!");
        -chase_coordination(X, Y, yes)[source(Chaser)];
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        +captain_alerted(yes);  // Inherit the status
        vesna.move_to(X, Y).

// Ignore if we're already tracking
+chase_coordination(X, Y, _)[source(Chaser)] : tracking_player
    <-  .print("Coordination from ", Chaser, " ignored - already engaged.");
        -chase_coordination(X, Y, _)[source(Chaser)].

// Alert captain directly without moving to them
// TBD: we must change this in moving to the captain and alerting them
// since patrols should not be able to communicate over distance
+!alert_captain_directly(X, Y)
    <-  .print("Alerting captain directly about player at ", X, ", ", Y);
        .send(captain, tell, player_spotted_at(X, Y)).

// =============================================================================
// ALERT RESPONSE (From other agents - Fear modulates response)
// =============================================================================

// HIGH PRIORITY: Any alert when already tracking - just update position
+player_spotted_at(X, Y)[source(Sender)] : tracking_player
    <-  .print("ALERT from ", Sender, " acknowledged. Updating target position.");
        -player_spotted_at(X, Y)[source(Sender)];
        +last_player_pos(X, Y).

// High fear = Hesitate before responding (any source)
// CRITICAL: Set responding_to_alert and drop intentions BEFORE wait to prevent race conditions
@alert_response_scared[temper([fear(0.7)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)] : not tracking_player & responding_to_alert(no)
    <-  .print("Alert from ", Sender, "... are they sure? I'll... head that way.");
        -player_spotted_at(X, Y)[source(Sender)];
        // Set flags BEFORE wait to prevent navigation handlers from interfering
        -responding_to_alert(no);
        +responding_to_alert(yes);
        +tracking_player;
        .drop_all_intentions;  // Cancel patrol, rest, everything
        vesna.lock(set);  // Freeze body during hesitation
        .wait(2000); // Hesitation
        +last_player_pos(X, Y);
        vesna.move_to(X, Y);
        !patrol.  // Re-add patrol intention (will be blocked by tracking_player)

// Low fear = Standard immediate response (any source)
@alert_response_calm[temper([fear(0.3)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)] : not tracking_player & responding_to_alert(no)
    <-  .print("ALERT from ", Sender, "! Intercepting at ", X, ",", Y);
        -player_spotted_at(X, Y)[source(Sender)];
        -responding_to_alert(no);
        +responding_to_alert(yes);
        +tracking_player;
        .drop_all_intentions;
        +last_player_pos(X, Y);
        vesna.move_to(X, Y);
        !patrol.

// Already responding to an alert - just update target
+player_spotted_at(X, Y)[source(Sender)] : responding_to_alert(yes)
    <-  .print("Already responding to alert. Updating target to ", X, ",", Y);
        -player_spotted_at(X, Y)[source(Sender)];
        +last_player_pos(X, Y);
        vesna.move_to(X, Y).

// =============================================================================
// INTEL REPORTING (Responding to Captain)
// =============================================================================

+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Reporting sighting at ", X, ",", Y, " to ", Captain);
        .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// FAILURE HANDLING
// =============================================================================

// Navigation failure - clear all alert state and try to resume
+signal(navigation, failed, Reason)
    <-  .print("Navigation error: ", Reason);
        -tracking_player;
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.lock(release);
        .wait(2000);
        !patrol.

// Patrol goal failure - attempt recovery
-!patrol
    <-  .print("Warning: Patrol failed. Attempting recovery.");
        -tracking_player;
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.lock(release);
        .wait(3000);
        !patrol.

// Decide next step failure - fall back to simple forward patrol
-!decide_next_step
    <-  .print("Warning: Decision failed. Moving forward.");
        vesna.patrol(next).
