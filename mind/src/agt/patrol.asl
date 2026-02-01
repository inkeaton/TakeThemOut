// patrol.asl - Patrol agent with waypoint navigation and player pursuit
// BDI-style: React to perceptions, use goals for activities, context for decisions
// FEAR SYSTEM: Patrols build fear from threats, modified by personality traits

// =============================================================================
// INITIAL GOAL
// =============================================================================

!patrol.

// =============================================================================
// KNOWLEDGE BELIEFS 
// =============================================================================

// Track consecutive failures to compound fear
consecutive_failures(0).

// Supersede pattern for player position
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

// Arrived at patrol waypoint - rest then continue (natural fear decay)
@navigation_safe[effects([fear(-0.02)])]
+navigation(reached, Waypoint)
    <-  .print("Arrived at ", Waypoint);
        -navigation(reached, Waypoint);
        !rest_at_waypoint;
        !patrol.

// Arrived at target location (from alert or move_to)
+navigation(reached_target, Coords)
    <-  .print("Arrived at target location. Investigating.");
        -navigation(reached_target, Coords);
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
        .broadcast(tell, emergency_backup_needed(X, Y));
        vesna.chase(12).

// Lazy + Scared = Retreat/Alert only
@chase_retreat[temper([aggressiveness(0.2), fear(0.7)]), effects([fear(0.2)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("Player detected. I'M CALLING FOR BACKUP!");
        +tracking_player;
        .broadcast(tell, player_spotted_at(X, Y));
        vesna.investigate(1).

// Standard chases (medium fear)
@chase_aggressive[temper([aggressiveness(0.8), fear(0.4)]), effects([fear(0.1)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("PLAYER DETECTED! HUNT THEM DOWN!");
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(15).

@chase_lazy[temper([aggressiveness(0.2), fear(0.3)]), effects([fear(0.08)])]
+sight(player, Id, pos(X, Y)) : not tracking_player
    <-  .print("Player detected. I'll take a look, I guess...");
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(4).

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
// TARGET LOST (Fear increases, consecutive failures tracked)
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
        vesna.investigate(3).

// Multiple failures increase fear further
@target_lost_repeated[effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N) & N > 2
    <-  .print("This is the ", N, "th time they've slipped away...").

// =============================================================================
// INVESTIGATION COMPLETE (Resume patrol, reduce fear, reset failures)
// =============================================================================

@investigation_done[effects([fear(-0.08)])]
+investigation(complete, Reason) : consecutive_failures(N)
    <-  .print("Investigation finished (", Reason, "). Nothing found.");
        -investigation(complete, Reason);
        -tracking_player;  // Clear tracking state
        -last_player_pos(_, _);  // Clear last known position
        -consecutive_failures(N);
        +consecutive_failures(0);  // Reset on successful completion
        vesna.patrol(resume);
        !patrol.

// =============================================================================
// ALERT RESPONSE (From other agents - Fear modulates response)
// =============================================================================

// HIGH PRIORITY: Captain alerts always override current activity
+player_spotted_at(X, Y)[source(captain)] : tracking_player
    <-  .print("CAPTAIN OVERRIDE! Redirecting to ", X, ",", Y);
        .drop_all_intentions;  // Drop everything including investigation
        +last_player_pos(X, Y);
        vesna.move_to(X, Y).

+player_spotted_at(X, Y)[source(captain)] : not tracking_player
    <-  .print("ALERT from captain! Intercepting at ", X, ",", Y);
        +tracking_player;  // Set tracking state
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.move_to(X, Y).

// LOWER PRIORITY: Sentry alerts - acknowledged but don't interrupt
+player_spotted_at(X, Y)[source(Sender)] : tracking_player
    <-  .print("ALERT from ", Sender, " acknowledged. Currently engaged, continuing task.").

// High fear = Hesitate before responding
@alert_response_scared[temper([fear(0.7)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)] : not tracking_player
    <-  .print("Alert from ", Sender, "... are they sure? I'll... head that way.");
        .wait(2000); // Hesitation
        +tracking_player;
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.move_to(X, Y).

// Low fear = Standard immediate response
@alert_response_calm[temper([fear(0.3)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)] : not tracking_player
    <-  .print("ALERT from ", Sender, "! Intercepting at ", X, ",", Y);
        +tracking_player;
        .drop_intention(patrol);
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

+signal(navigation, failed, Reason)
    <-  .print("Navigation error: ", Reason);
        .wait(2000);
        !patrol.
