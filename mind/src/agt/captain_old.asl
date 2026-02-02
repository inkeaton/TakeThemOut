// captain.asl - Squad leader with intel gathering and coordination
// BDI-style: React to perceptions, goal-driven intel analysis, no state flags
// FEAR SYSTEM: Captain has confidence baseline (-0.2) and 50% fear resistance

// =============================================================================
// INITIAL GOAL
// =============================================================================

!patrol.

// =============================================================================
// KNOWLEDGE BELIEFS (not state flags)
// =============================================================================

// Track consecutive failures to compound fear (but at reduced rate)
consecutive_failures(0).

// Track whether we are actively pursuing player
tracking_player(no).

// Track whether we are responding to an alert
responding_to_alert(no).

// Supersede pattern for tracking_player
+tracking_player(Status) : tracking_player(OldStatus) & OldStatus \== Status
    <-  -tracking_player(OldStatus).

// Supersede pattern for responding_to_alert
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

// Main patrol - gather intel then decide where to go
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
        vesna.patrol(random).

// Cautious: Methodical next-waypoint progression
@patrol_methodical[temper([fear(0.5)])]
+!act_on_intel([])
    <-  .print("No immediate threats. Maintaining standard patrol.");
        vesna.patrol(next).

// Got intel - calculate intercept point (fear affects approach)
// Confident: Direct intercept
@intercept_bold[temper([fear(0.2)]), effects([fear(0.02)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  .print("Intel received: ", Reports);
        vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("Intercept course set: ", AvgX, ",", AvgY);
        vesna.move_to(AvgX, AvgY).

// Cautious: Brief hesitation before intercept
@intercept_cautious[temper([fear(0.6)]), effects([fear(0.04)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  .print("Multiple sightings confirmed. Proceeding with caution.");
        vesna.calc_centroid(Reports, AvgX, AvgY);
        .wait(1000);
        vesna.move_to(AvgX, AvgY).

// =============================================================================
// HANDLING SIGHTING REPORTS (From squad)
// =============================================================================

// Store position reports (will be collected by .findall in analyze_intel)
+sighting_report(pos(X, Y))[source(Sender)]
    <-  .print("Received report from ", Sender, ": pos(", X, ",", Y, ")").

// Ignore "nothing to report" messages
+sighting_report(none)[source(_)].

// =============================================================================
// NAVIGATION HANDLERS
// =============================================================================

// Arrived at patrol waypoint - continue intel loop (confidence boost)
// GUARD: Only restart patrol if NOT tracking player AND NOT responding to alert
@navigation_checkpoint[effects([fear(-0.03)])]
+navigation(reached, Waypoint) : tracking_player(no) & responding_to_alert(no)
    <-  .print("Arrived at waypoint ", Waypoint);
        -navigation(reached, Waypoint);
        !patrol.

// Arrived at waypoint while in alert mode - just acknowledge
+navigation(reached, Waypoint) : tracking_player(yes) | responding_to_alert(yes)
    <-  .print("Arrived at ", Waypoint, " (alert active, not resuming patrol)");
        -navigation(reached, Waypoint).

// Arrived at intercept point - investigate (confidence from arrival)
// Clear responding_to_alert since we've arrived
@navigation_intercept[effects([fear(-0.08)])]
+navigation(reached_target, Coords)
    <-  .print("Arrived at intercept point. Checking area.");
        -navigation(reached_target, Coords);
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.investigate(5).

// Investigation complete - resume patrol (area secured)
@investigation_secured[effects([fear(-0.05)])]
+investigation(complete, Reason)
    <-  .print("Area clear (", Reason, "). Resuming patrol.");
        -investigation(complete, Reason);
        -tracking_player(_);
        +tracking_player(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        -last_player_pos(_, _);
        -last_alert_pos(_, _);
        .abolish(sight(player, _, _));
        vesna.lock(release);
        !patrol.

// =============================================================================
// PLAYER DETECTION (Captain sees player - reduced fear gain)
// =============================================================================

// Already tracking - just update position
+sight(player, Id, pos(X, Y)) : tracking_player(yes)
    <-  .print("Still tracking. Position updated.");
        -last_player_pos(_, _);
        +last_player_pos(X, Y).

// Confident Captain: Extended pursuit
@chase_leader_confident[temper([fear(0.1)]), effects([fear(0.03)])]
+sight(player, Id, pos(X, Y)) : tracking_player(no)
    <-  .print("CONTACT! Taking command!");
        -tracking_player(no);
        +tracking_player(yes);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(25). // Very long patience

// Shaken Captain: Shorter pursuit (no emergency broadcast)
@chase_leader_shaken[temper([fear(0.6)]), effects([fear(0.08)])]
+sight(player, Id, pos(X, Y)) : tracking_player(no)
    <-  .print("Enemy spotted! Engaging with caution.");
        -tracking_player(no);
        +tracking_player(yes);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(15). // Reduced patience

// Default: Assertive leadership
@chase_leader_default[effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : tracking_player(no)
    <-  .print("CONTACT! Taking command!");
        -tracking_player(no);
        +tracking_player(yes);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.chase(20).

// =============================================================================
// RECEIVING ALERTS (From sentries/patrols - minimal fear increase)
// =============================================================================

// Already responding or tracking - update target
+player_spotted_at(X, Y)[source(Sender)] : tracking_player(yes) | responding_to_alert(yes)
    <-  .print("ALERT from ", Sender, " acknowledged. Updating target.");
        -player_spotted_at(X, Y)[source(Sender)];
        +last_alert_pos(X, Y).

// New alert - interrupt patrol and investigate
@alert_received[effects([fear(0.03)])]
+player_spotted_at(X, Y)[source(Sender)] : tracking_player(no) & responding_to_alert(no)
    <-  .print("ALERT received from ", Sender, "! Redirecting to (", X, ", ", Y, ")");
        -player_spotted_at(X, Y)[source(Sender)];
        -responding_to_alert(no);
        +responding_to_alert(yes);
        .drop_all_intentions;
        +last_alert_pos(X, Y);
        vesna.move_to(X, Y);
        !patrol.

// =============================================================================
// TARGET LOST (Resume intel-gathering - 50% reduced fear gain)
// =============================================================================

// Multiple failures increase frustration (but less than patrols)
@target_lost_repeated[effects([fear(0.04)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N) & N > 2
    <-  .print("Lost contact at (", X, ", ", Y, "). This is getting frustrating.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        !patrol.

// Standard target lost (reduced fear for captain)
@target_lost_standard[effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Lost contact at (", X, ", ", Y, "). Re-evaluating.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N);
        +consecutive_failures(N+1);
        !patrol.

// =============================================================================
// FAILURE HANDLING
// =============================================================================

-!gather_intel
    <-  .print("Warning: Intel gathering failed. Patrolling randomly.");
        vesna.patrol(random).

-!analyze_intel
    <-  .abolish(sighting_report(_)); // Clean up stale reports
        .print("Warning: Intel analysis failed. Patrolling randomly.");
        vesna.patrol(random).

// =============================================================================
// NAVIGATION FAILURE HANDLING
// =============================================================================

+signal(navigation, failed, Reason)
    <-  .print("Navigation error: ", Reason, ". Re-evaluating.");
        -tracking_player(_);
        +tracking_player(no);
        -responding_to_alert(_);
        +responding_to_alert(no);
        vesna.lock(release);
        .wait(2000);
        !patrol.
