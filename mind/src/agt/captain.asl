// captain.asl - Squad leader with intel gathering and coordination
// BDI-style: React to perceptions, goal-driven intel analysis, no state flags
// FEAR SYSTEM: Captain has confidence baseline (-0.2) and 50% fear resistance

// =============================================================================
// INITIAL GOAL
// =============================================================================

!start_patrol.

// =============================================================================
// KNOWLEDGE BELIEFS (not state flags)
// =============================================================================

// Track consecutive failures to compound fear (but at reduced rate)
consecutive_failures(0).

// Track whether we are actively chasing/tracking player
// Body handles Chase<->Track transitions autonomously
is_chasing(no).

// Track whether we are responding to an alert (navigating to alert coords)
// Prevents patrol loop from overriding alert response
responding_to_alert(no).

// Supersede patterns
+is_chasing(Status) : is_chasing(OldStatus) & OldStatus \== Status
    <-  -is_chasing(OldStatus).

+responding_to_alert(Status) : responding_to_alert(OldStatus) & OldStatus \== Status
    <-  -responding_to_alert(OldStatus).

// Supersede pattern for player position
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// Supersede pattern for alert position (only keep latest)
+last_alert_pos(X, Y) : last_alert_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_alert_pos(OldX, OldY).

// =============================================================================
// CAPTAIN'S PATROL LOOP (Intel-driven)
// =============================================================================

// Initial start - transition to Patrol state
+!start_patrol
    <-  .print("Captain reporting for duty.");
        vesna.transition_to("Patrol", [target("next")]).

// Main patrol goal - gather intel then decide where to go
+!patrol
    <-  !gather_intel.

// Gather intel from squad
+!gather_intel
    <-  .print("Reaching checkpoint. Gathering intel from squad...");
        // Ask everyone for their sightings
        .broadcast(achieve, report_sightings);
        // Wait for replies
        .wait(2000);
        // Process what we received
        !analyze_intel.

// Analyze collected intel and act (fear affects decisiveness)
// Confident Captain (low/negative fear)
@analyze_confident[temper([fear(0.1)]), effects([fear(-0.02)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)], Reports);
        .abolish(sighting_report(_));
        .print("Intel received: ", Reports);
        !act_on_intel(Reports).

// Stressed Captain (medium fear)
@analyze_cautious[temper([fear(0.4)]), effects([fear(0.02)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)], Reports);
        .abolish(sighting_report(_));
        .print("Multiple reports... need to prioritize...");
        .wait(1000); // Slight hesitation
        !act_on_intel(Reports).

// Overwhelmed Captain (high fear - rare)
@analyze_overwhelmed[temper([fear(0.7)]), effects([fear(0.05)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)], Reports);
        .abolish(sighting_report(_));
        .print("Too many threats! Choosing closest...");
        !act_on_intel(Reports).

// No intel - patrol based on confidence level
// Confident: Random aggressive patrols
@patrol_aggressive[temper([fear(0.1)]), effects([fear(-0.01)])]
+!act_on_intel([])
    <-  .print("No intel. Taking initiative on random sector.");
        vesna.transition_to("Patrol", [target("random")]).

// Cautious: Methodical next-waypoint progression
@patrol_methodical[temper([fear(0.5)])]
+!act_on_intel([])
    <-  .print("No immediate threats. Maintaining standard patrol.");
        vesna.transition_to("Patrol", [target("next")]).

// Got intel - calculate intercept point (fear affects approach)
// Confident: Direct intercept
@intercept_bold[temper([fear(0.2)]), effects([fear(0.02)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  .print("Intel received: ", Reports);
        vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("Intercept course set: ", AvgX, ",", AvgY);
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

// Cautious: Brief hesitation before intercept
@intercept_cautious[temper([fear(0.6)]), effects([fear(0.04)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  .print("Multiple sightings confirmed. Proceeding with caution.");
        vesna.calc_centroid(Reports, AvgX, AvgY);
        .wait(1000);
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

// =============================================================================
// HANDLING SIGHTING REPORTS (From squad)
// =============================================================================

// Store position reports (will be collected by .findall in analyze_intel)
+sighting_report(pos(X, Y))[source(Sender)]
    <-  .print("Received report from ", Sender, ": pos(", X, ",", Y, ")").

// Ignore "nothing to report" messages
+sighting_report(none)[source(_)].

// =============================================================================
// NAVIGATION HANDLERS (Body arrived at destination, now in Idle)
// =============================================================================

// Arrived at patrol waypoint - continue intel loop (confidence boost)
// GUARD: Only restart patrol if NOT chasing AND NOT responding to alert
@navigation_checkpoint[effects([fear(-0.03)])]
+navigation(reached, Waypoint) : is_chasing(no) & responding_to_alert(no)
    <-  .print("Arrived at waypoint ", Waypoint);
        -navigation(reached, Waypoint);
        !patrol.

// Arrived at waypoint while chasing or responding to alert - ignore
+navigation(reached, Waypoint) : is_chasing(yes)
    <-  .print("Arrived at ", Waypoint, " (chasing, ignoring)");
        -navigation(reached, Waypoint).

+navigation(reached, Waypoint) : responding_to_alert(yes)
    <-  .print("Arrived at ", Waypoint, " (responding to alert, ignoring)");
        -navigation(reached, Waypoint).

// Arrived at intercept point - investigate (confidence from arrival)
@navigation_intercept[effects([fear(-0.08)])]
+navigation(reached_target, Coords) : is_chasing(no)
    <-  .print("Arrived at intercept point. Investigating area.");
        -navigation(reached_target, Coords);
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.transition_to("Investigate", [points(5)]).

// Arrived at target while chasing - shouldn't happen, but handle it
+navigation(reached_target, Coords) : is_chasing(yes)
    <-  .print("Arrived at target (chasing, ignoring)");
        -navigation(reached_target, Coords).

// =============================================================================
// INVESTIGATION COMPLETE (Body in Idle, mind decides to resume patrol)
// =============================================================================

// Investigation complete - resume patrol (area secured)
@investigation_secured[effects([fear(-0.05)])]
+signal_investigation(complete, Reason)
    <-  .print("Area clear (", Reason, "). Resuming patrol.");
        -signal_investigation(complete, Reason);
        -is_chasing(_);
        +is_chasing(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        -last_player_pos(_, _);
        -last_alert_pos(_, _);
        -consecutive_failures(_);
        +consecutive_failures(0);
        .abolish(sight(player, _, _));
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// PLAYER DETECTION (Captain sees player - broadcasts to squad)
// =============================================================================

// Already tracking - just update position
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  .print("Still tracking. Position updated.");
        -last_player_pos(_, _);
        +last_player_pos(X, Y).

// Confident Captain: Extended pursuit
@chase_leader_confident[temper([fear(0.1)]), effects([fear(0.03)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("CONTACT! Taking command!");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(25)]). // Very long patience

// Shaken Captain: Shorter pursuit
@chase_leader_shaken[temper([fear(0.6)]), effects([fear(0.08)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Enemy spotted! Engaging with caution.");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(15)]). // Reduced patience

// Default: Assertive leadership
@chase_leader_default[effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("CONTACT! Taking command!");
        -is_chasing(no);
        +is_chasing(yes);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(20)]).

// =============================================================================
// RECEIVING ALERTS (From sentries/patrols/messengers)
// =============================================================================

// Already chasing - acknowledge but continue chase (message from messenger)
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(yes)
    <-  .print("ALERT from ", Sender, " acknowledged. I'm already engaged!");
        -player_spotted_at(X, Y)[source(Sender)];
        +last_player_pos(X, Y).

// Already responding to an alert - update target coordinates
+player_spotted_at(X, Y)[source(Sender)] : responding_to_alert(yes)
    <-  .print("ALERT from ", Sender, " - updating intercept coordinates.");
        -player_spotted_at(X, Y)[source(Sender)];
        +last_alert_pos(X, Y);
        // Re-broadcast to ensure everyone knows
        .broadcast(tell, player_spotted_at(X, Y));
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// New alert - interrupt patrol, broadcast to all, and respond (from messenger/sentry)
@alert_received[effects([fear(0.03)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no) & responding_to_alert(no)
    <-  .print("ALERT received from ", Sender, "! Broadcasting and redirecting to (", X, ", ", Y, ")");
        -player_spotted_at(X, Y)[source(Sender)];
        -responding_to_alert(no);
        +responding_to_alert(yes);
        // Broadcast alert to all agents
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_all_intentions;
        +last_alert_pos(X, Y);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// =============================================================================
// TARGET LOST (Body went to Idle, mind decides investigation)
// =============================================================================

// Multiple failures increase frustration (but less than patrols)
@target_lost_repeated[effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N) & N > 2
    <-  .print("Lost contact at (", X, ", ", Y, "). This is getting frustrating.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.transition_to("Investigate", [points(3)]).

// Standard target lost (reduced fear for captain)
@target_lost_standard[effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Lost contact at (", X, ", ", Y, "). Searching area.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        vesna.transition_to("Investigate", [points(5)]).

// =============================================================================
// PATROL COORDINATION (Stub for future implementation)
// =============================================================================

// Handle empty ally list
+allies_nearby([]) : is_chasing(yes)
    <-  .print("Scanned for allies, none found nearby.");
        -allies_nearby([]).

// STUB: Found patrol allies while tracking player
// Future: Could coordinate multi-agent encirclement
+allies_nearby(AllyList) : is_chasing(yes) & last_player_pos(X, Y) & not .empty(AllyList)
    <-  .print("STUB: Found allies while chasing: ", AllyList);
        .print("TODO: Coordinate encirclement maneuver");
        -allies_nearby(AllyList).

// Fallback
+allies_nearby(AllyList) : is_chasing(yes)
    <-  .print("Spotted allies but no position info to share.");
        -allies_nearby(AllyList).

// =============================================================================
// FAILURE HANDLING
// =============================================================================

-!gather_intel
    <-  .print("Warning: Intel gathering failed. Patrolling randomly.");
        vesna.transition_to("Patrol", [target("random")]).

-!analyze_intel
    <-  .abolish(sighting_report(_)); // Clean up stale reports
        .print("Warning: Intel analysis failed. Patrolling randomly.");
        vesna.transition_to("Patrol", [target("random")]).

-!patrol
    <-  .print("Warning: Patrol failed. Attempting recovery.");
        -is_chasing(_);
        +is_chasing(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .wait(3000);
        vesna.transition_to("Patrol", [target("next")]);
        !patrol.

// Navigation failure - clear state and resume patrol
+signal(navigation, failed, Reason)
    <-  .print("Navigation error: ", Reason, ". Re-evaluating.");
        -is_chasing(_);
        +is_chasing(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        .wait(2000);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.
