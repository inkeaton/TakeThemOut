// patrol.asl - Patrol agent with waypoint navigation and player pursuit
// Redesigned to use transition_to pattern for all state changes

// =============================================================================
// INITIAL GOAL
// =============================================================================

!start_patrol.

// =============================================================================
// KNOWLEDGE BELIEFS 
// =============================================================================

// Track consecutive failures to increase fear
consecutive_failures(0).

// Track whether captain has been alerted during current chase
captain_alerted(no).

// Track whether we are actively chasing/tracking player
// Body handles Chase<->Track transitions autonomously
// This is set when we enter chase, cleared when we return to Idle
is_chasing(no).

// Track whether we are responding to an alert (navigating to alert coords)
// Prevents patrol loop from overriding alert response
responding_to_alert(no).

// Track whether we are acting as a messenger to inform captain
is_messenger(no).

// Track the captain we need to deliver message to
messenger_target(none).

// Track the player position to report to captain
messenger_report_pos(none).

// Track whether we've already sent a messenger during this chase
// Prevents sending multiple messengers
messenger_sent(no).

// Supersede patterns
+captain_alerted(Status) : captain_alerted(OldStatus) & OldStatus \== Status
    <-  -captain_alerted(OldStatus).

+is_chasing(Status) : is_chasing(OldStatus) & OldStatus \== Status
    <-  -is_chasing(OldStatus).

+responding_to_alert(Status) : responding_to_alert(OldStatus) & OldStatus \== Status
    <-  -responding_to_alert(OldStatus).

+is_messenger(Status) : is_messenger(OldStatus) & OldStatus \== Status
    <-  -is_messenger(OldStatus).

+messenger_target(Target) : messenger_target(OldTarget) & OldTarget \== Target
    <-  -messenger_target(OldTarget).

+messenger_report_pos(Pos) : messenger_report_pos(OldPos) & OldPos \== Pos
    <-  -messenger_report_pos(OldPos).

+messenger_sent(Status) : messenger_sent(OldStatus) & OldStatus \== Status
    <-  -messenger_sent(OldStatus).

+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// =============================================================================
// PATROL LOOP
// =============================================================================

// Initial start - transition to Patrol state
+!start_patrol
    <-  .print("Starting patrol duty.");
        vesna.transition_to("Patrol", [target("next")]).

// Main patrol goal - decide next waypoint based on personality
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
        vesna.transition_to("Patrol", [target("prev")]).

// LOW FEAR: Standard patterns based on aggressiveness
@go_next_calm[temper([aggressiveness(0.1), fear(0.1)]), effects([fear(-0.01)])]
+!decide_next_step
    <-  .print("Patrolling forward...");
        vesna.transition_to("Patrol", [target("next")]).

// Aggressive Checks - occasional backtracking (low fear)
@go_prev_low[temper([aggressiveness(0.3), fear(0.2)])]
+!decide_next_step : .random(R) & R < 0.1
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.transition_to("Patrol", [target("prev")]).

@go_prev_mid[temper([aggressiveness(0.5), fear(0.2)])]
+!decide_next_step : .random(R) & R < 0.3
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.transition_to("Patrol", [target("prev")]).

@go_prev_high[temper([aggressiveness(0.9), fear(0.2)])]
+!decide_next_step : .random(R) & R < 0.5
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.transition_to("Patrol", [target("prev")]).

// =============================================================================
// NAVIGATION HANDLERS (Body arrived at destination, now in Idle)
// =============================================================================

// Arrived at waypoint - rest then continue patrol
@navigation_waypoint[effects([fear(-0.02)])]
+navigation(reached, Waypoint) : is_chasing(no) & responding_to_alert(no)
    <-  .print("Arrived at waypoint ", Waypoint);
        -navigation(reached, Waypoint);
        !rest_at_waypoint;
        !patrol.

// Arrived at waypoint while chasing or responding to alert - ignore
+navigation(reached, Waypoint) : is_chasing(yes)
    <-  .print("Arrived at ", Waypoint, " (chasing, ignoring)");
        -navigation(reached, Waypoint).

+navigation(reached, Waypoint) : responding_to_alert(yes)
    <-  .print("Arrived at ", Waypoint, " (responding to alert, ignoring)");
        -navigation(reached, Waypoint).

// Arrived at target coordinates (from alert response)
+navigation(reached_target, Coords) : is_chasing(no)
    <-  .print("Arrived at target location. Investigating.");
        -navigation(reached_target, Coords);
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.transition_to("Investigate", [points(2)]).

// Arrived at target while chasing - shouldn't happen, but handle it
+navigation(reached_target, Coords) : is_chasing(yes)
    <-  .print("Arrived at target (chasing, ignoring)");
        -navigation(reached_target, Coords).

// =============================================================================
// REST BEHAVIOR (Fear modulates personality)
// =============================================================================

@rest_paralyzed[temper([laziness(0.8), fear(0.7)])]
+!rest_at_waypoint
    <-  .print("I'm... I'm not moving. Too dangerous.");
        .wait(10000).

@rest_vigilant[temper([laziness(0.2), fear(0.7)]), effects([fear(-0.03)])]
+!rest_at_waypoint
    <-  .print("Can't rest. Must stay alert.");
        .wait(500).

@lazy_rest_calm[temper([laziness(0.8), fear(0.2)])]
+!rest_at_waypoint
    <-  .print("Ugh, my feet hurt. Taking a long break...");
        .wait(5000).

@active_rest_calm[temper([laziness(0.2), fear(0.2)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving on immediately.");
        .wait(1000).

@default_rest
+!rest_at_waypoint
    <-  .print("Just a standard pause.");
        .wait(2000).

// =============================================================================
// PLAYER DETECTION (Body auto-chases, mind sets patience)
// =============================================================================

// Aggressive + Brave = Fearless pursuit
@chase_fearless[temper([aggressiveness(0.8), fear(0.1)]), effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("PLAYER DETECTED! HUNT THEM DOWN!");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(20)]).

// Aggressive + Scared = Desperate attack
@chase_desperate[temper([aggressiveness(0.8), fear(0.7)]), effects([fear(0.15)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("THERE THEY ARE! I NEED TO END THIS!");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(12)]).

// Lazy + Scared = Retreat/Minimal effort 
@chase_retreat[temper([aggressiveness(0.2), fear(0.7)]), effects([fear(0.2)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Player detected. Too scary, I'll just check briefly...");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        +last_player_pos(X, Y);
        vesna.transition_to("Investigate", [points(1)]).

// Lazy + Medium Fear = Hesitant pursuit
@chase_lazy[temper([aggressiveness(0.2), fear(0.3)]), effects([fear(0.08)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Player detected. I'll take a look, I guess...");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(4)]).

// Default: Standard chase
@chase_default[effects([fear(0.1)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Player detected! Engaging.");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(8)]).

// Update position if already chasing
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  .print("Still tracking player. Position updated.");
        -last_player_pos(_, _);
        +last_player_pos(X, Y).

// =============================================================================
// TARGET LOST (Body went to Idle, mind decides investigation)
// =============================================================================

@recover_scared_lazy[temper([laziness(0.8), fear(0.7)]), effects([fear(0.08)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("They're gone. Probably far away. I'm done here.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.transition_to("Investigate", [points(1)]).

@recover_paranoid[temper([laziness(0.2), fear(0.8)]), effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Must check EVERYWHERE. They could be hiding!");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.transition_to("Investigate", [points(8)]).

@recover_diligent_calm[temper([laziness(0.2), fear(0.2)]), effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. I will comb the area!");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.transition_to("Investigate", [points(5)]).

@recover_lazy_calm[temper([laziness(0.8), fear(0.2)]), effects([fear(0.08)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. I'll verify quickly.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.transition_to("Investigate", [points(2)]).

@recover_default[effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. Checking the area.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        if (N > 2) { .print("This is the ", N+1, "th time they've slipped away..."); };
        vesna.transition_to("Investigate", [points(3)]).

// =============================================================================
// INVESTIGATION COMPLETE (Body in Idle, mind decides to resume patrol)
// =============================================================================

@investigation_done[effects([fear(-0.08)])]
+signal_investigation(complete, Reason) : consecutive_failures(N)
    <-  .print("Investigation finished (", Reason, "). Nothing found.");
        -signal_investigation(complete, Reason);
        -is_chasing(_);
        +is_chasing(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        -last_player_pos(_, _);
        -consecutive_failures(N);
        +consecutive_failures(0);
        -captain_alerted(_);
        +captain_alerted(no);
        -messenger_sent(_);
        +messenger_sent(no);
        .abolish(sight(player, _, _));
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// PATROL COORDINATION (Messenger System)
// =============================================================================

// Handle empty ally list
+allies_nearby([]) : is_chasing(yes)
    <-  .print("Scanned for allies, none found.");
        -allies_nearby([]).

// Found idle patrol allies while tracking player - recruit first as messenger
+allies_nearby(AllyList) : is_chasing(yes) & last_player_pos(X, Y) & not .empty(AllyList) & messenger_sent(no)
    <-  .print("Found available allies: ", AllyList, ". Recruiting messenger.");
        -allies_nearby(AllyList);
        // Get first ally from list
        .nth(0, AllyList, FirstAlly);
        .print("Sending ", FirstAlly, " to inform captain about player at ", X, ",", Y);
        // Ask ally to become messenger with current player position
        .send(FirstAlly, achieve, become_messenger(pos(X, Y)));
        // Mark that we've already sent a messenger this chase
        -messenger_sent(no);
        +messenger_sent(yes).

// Already sent a messenger this chase - don't send another
+allies_nearby(AllyList) : is_chasing(yes) & messenger_sent(yes)
    <-  .print("Allies nearby, but already sent a messenger.");
        -allies_nearby(AllyList).

// Fallback - chasing but no position info
+allies_nearby(AllyList) : is_chasing(yes)
    <-  .print("Spotted allies but no position info to share.");
        -allies_nearby(AllyList).

// =============================================================================
// MESSENGER GOAL (Received request from another patrol)
// =============================================================================

// Become messenger - store info and navigate to nearest captain
+!become_messenger(pos(X, Y))[source(Sender)] : is_chasing(no) & is_messenger(no)
    <-  .print("Accepted messenger duty from ", Sender, ". Finding nearest captain.");
        // Store the position to report
        -messenger_report_pos(_);
        +messenger_report_pos(pos(X, Y));
        // Enter messenger mode
        -is_messenger(no);
        +is_messenger(yes);
        // Stop current intentions
        .drop_intention(patrol);
        // Navigate to find nearest captain (body computes who)
        vesna.transition_to("Patrol", [target("find_captain")]).

// Can't become messenger - already chasing
+!become_messenger(pos(X, Y))[source(Sender)] : is_chasing(yes)
    <-  .print("Can't be messenger - I'm already chasing the player!");
        .send(Sender, tell, messenger_rejected(busy_chasing)).

// Can't become messenger - already a messenger
+!become_messenger(pos(X, Y))[source(Sender)] : is_messenger(yes)
    <-  .print("Can't be messenger - I'm already on a messenger mission!");
        .send(Sender, tell, messenger_rejected(already_messenger)).

// Messenger goal failure
-!become_messenger(Pos)[source(Sender)]
    <-  .print("Failed to become messenger. Resuming patrol.");
        -is_messenger(_);
        +is_messenger(no);
        -messenger_report_pos(_);
        +messenger_report_pos(none);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// MESSENGER ARRIVAL (Reached captain, deliver message)
// =============================================================================

// Arrived at captain - deliver the message
+navigation(reached_agent, Captain) : is_messenger(yes) & messenger_report_pos(pos(X, Y))
    <-  .print("Reached captain ", Captain, ". Reporting player at ", X, ",", Y);
        -navigation(reached_agent, Captain);
        // Deliver message to captain
        .send(Captain, tell, player_spotted_at(X, Y));
        .print("Message delivered. Returning to patrol duty.");
        // Clear messenger state
        -is_messenger(yes);
        +is_messenger(no);
        -messenger_report_pos(pos(X, Y));
        +messenger_report_pos(none);
        -messenger_target(_);
        +messenger_target(none);
        // Resume patrol
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// Arrived at agent but not in messenger mode - ignore
+navigation(reached_agent, Agent) : is_messenger(no)
    <-  .print("Arrived at ", Agent, " (not messenger, ignoring)");
        -navigation(reached_agent, Agent).

// No captain found (body couldn't find one)
+navigation(no_captain_found, _) : is_messenger(yes)
    <-  .print("No captain nearby! Aborting messenger mission.");
        -navigation(no_captain_found, _);
        -is_messenger(yes);
        +is_messenger(no);
        -messenger_report_pos(_);
        +messenger_report_pos(none);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// Target agent was lost/destroyed during navigation
+navigation(agent_lost, _) : is_messenger(yes)
    <-  .print("Target captain lost! Aborting messenger mission.");
        -navigation(agent_lost, _);
        -is_messenger(yes);
        +is_messenger(no);
        -messenger_report_pos(_);
        +messenger_report_pos(none);
        -messenger_target(_);
        +messenger_target(none);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// Agent lost but not in messenger mode - just ignore
+navigation(agent_lost, _) : is_messenger(no)
    <-  .print("Agent lost (not messenger, ignoring)");
        -navigation(agent_lost, _).

// =============================================================================
// ALERT RESPONSE (From other agents)
// =============================================================================

// Messenger receives alert - drop messenger mission and respond
+player_spotted_at(X, Y)[source(Sender)] : is_messenger(yes)
    <-  .print("ALERT from ", Sender, " while on messenger duty! Dropping mission.");
        -player_spotted_at(X, Y)[source(Sender)];
        // Clear messenger state
        -is_messenger(yes);
        +is_messenger(no);
        -messenger_report_pos(_);
        +messenger_report_pos(none);
        -messenger_target(_);
        +messenger_target(none);
        // Respond to alert
        .drop_all_intentions;
        +last_player_pos(X, Y);
        -responding_to_alert(no);
        +responding_to_alert(yes);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// Already chasing - just update position
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(yes)
    <-  .print("ALERT from ", Sender, " acknowledged. Updating target position.");
        -player_spotted_at(X, Y)[source(Sender)];
        +last_player_pos(X, Y).

// Already responding to an alert - update target coordinates
+player_spotted_at(X, Y)[source(Sender)] : responding_to_alert(yes)
    <-  .print("ALERT from ", Sender, " - updating intercept coordinates.");
        -player_spotted_at(X, Y)[source(Sender)];
        +last_player_pos(X, Y);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// High fear = Hesitate before responding
@alert_response_scared[temper([fear(0.7)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, "... are they sure? I'll... head that way.");
        -player_spotted_at(X, Y)[source(Sender)];
        .drop_all_intentions;
        +last_player_pos(X, Y);
        -responding_to_alert(no);
        +responding_to_alert(yes);
        .wait(2000); // Hesitation
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// Low fear = Immediate response
@alert_response_calm[temper([fear(0.3)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("ALERT from ", Sender, "! Intercepting at ", X, ",", Y);
        -player_spotted_at(X, Y)[source(Sender)];
        .drop_all_intentions;
        +last_player_pos(X, Y);
        -responding_to_alert(no);
        +responding_to_alert(yes);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

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

// Navigation failure - clear state and resume patrol
+signal(navigation, failed, Reason)
    <-  .print("Navigation error: ", Reason);
        -is_chasing(_);
        +is_chasing(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .wait(2000);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// Patrol goal failure
-!patrol
    <-  .print("Warning: Patrol failed. Attempting recovery.");
        -is_chasing(_);
        +is_chasing(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .wait(3000);
        vesna.transition_to("Patrol", [target("next")]);
        !patrol.

// Decide next step failure
-!decide_next_step
    <-  .print("Warning: Decision failed. Moving forward.");
        vesna.transition_to("Patrol", [target("next")]).
