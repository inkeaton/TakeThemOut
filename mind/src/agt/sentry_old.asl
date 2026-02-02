// sentry.asl - Sentry agent with player detection and ally alerting

// =============================================================================
// PERCEPTION HANDLERS 
// =============================================================================

// When we see the player trigger alert goal
// The +sight belief is added by VesnaAgent.handleSight()
// seeing the player scares a bit the sentry
@player_seen[effects([fear(0.1)])]
+sight(player, Id, pos(X, Y))
    <-  .print("PLAYER DETECTED at position (", X, ", ", Y, ")!");
        !alert_about_player(X, Y).

// when new position arrives, remove old one
// we always want to keep the latest known position, to inform the captain correctly
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// =============================================================================
// ALERT GOAL
// =============================================================================

// HIGH FEAR (> 0.7): Panic alert with faster scanning
@alert_panic[temper([fear(0.8)]), effects([fear(0.25)])]
+!alert_about_player(X, Y)
    <-  .print("EMERGENCY! ENEMY CONTACT!");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 1.0); // Panic scanning
        vesna.alert.

// MEDIUM FEAR (0.4-0.7): Urgent alert with emphasis
@alert_nervous[temper([fear(0.5)]), effects([fear(0.2)])]
+!alert_about_player(X, Y)
    <-  .print("INTRUDER ALERT! Position logged");
        +last_player_pos(X, Y);
        vesna.alert.

// LOW FEAR (< 0.4): Calm, efficient alert
@alert_calm[temper([fear(0.2)]), effects([fear(0.15)])]
+!alert_about_player(X, Y)
    <-  .print("Target acquired. Notifying squad.");
        +last_player_pos(X, Y);
        vesna.alert.

// =============================================================================
// FOUND ALLIES AND CONTACT THEM
// =============================================================================

// Body found allies during alert scan, call them for help if we have position
// Fear decreases when we find allies 
@allies_found_relief[effects([fear(-0.1)])]
+allies_nearby(AllyList) : last_player_pos(X, Y)
    <-  .print("Allies found: ", AllyList);
        !broadcast_alert(AllyList, X, Y).

+!broadcast_alert([], _, _)
    <-  .print("Broadcast complete.").

+!broadcast_alert([Ally | Rest], X, Y)
    <-  .print("Sending alert to ", Ally);
        .send(Ally, tell, player_spotted_at(X, Y));
        !broadcast_alert(Rest, X, Y).

// Failure handler, continue with remaining allies
-!broadcast_alert([Ally | Rest], X, Y)
    <-  .print("Warning: Failed to alert ", Ally, ". Continuing...");
        !broadcast_alert(Rest, X, Y).

// =============================================================================
// ALERT PHASE ENDS
// =============================================================================

// Body finished alert sequence, clean up and adjust scan rate based on fear
// Completing duty reduces fear slightly
@alert_complete_scared[temper([fear(0.6)]), effects([fear(-0.05)])]
+signal_alert(completed, _)
    <-  .print("Alert complete. Staying vigilant!");
        vesna.set_var(switch_time, 2.0); // Fast scanning
        // need to reset beliefs
        -signal_alert(completed, _);
        -allies_nearby(_);
        .abolish(sight(player, _, _)).

@alert_complete_calm[temper([fear(0.2)]), effects([fear(-0.05)])]
+signal_alert(completed, _)
    <-  .print("Alert sequence completed. Resuming normal patrol.");
        vesna.set_var(switch_time, 5.0); // Normal scanning
        // need to reset beliefs
        -signal_alert(completed, _);
        -allies_nearby(_);
        .abolish(sight(player, _, _)).

// =============================================================================
// INTEL REPORTING TO CAPTAIN
// =============================================================================

// Captain asks for sightings, report if we have one
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Reporting sighting at ", X, ",", Y, " to ", Captain);
        .send(Captain, tell, sighting_report(pos(X, Y)));
        // Clear after reporting so we don't report stale data
        -last_player_pos(X, Y).

// Captain asks but we have no sighting
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// RECEIVING ALERTS FROM CAPTAIN
// =============================================================================

// Alert received, increase vigilance
// we do not store the player position from allies, since we only need it to tell the captain,
// and it is the captain that told us this to begin with
@alert_received_scared[temper([fear(0.5)]), effects([fear(0.1)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("ALERT from ", Sender, "! Scanning faster!");
        vesna.set_var(switch_time, 1.5); // Heightened alertness
        -player_spotted_at(X, Y)[source(Sender)].

@alert_received_calm[temper([fear(0.2)]), effects([fear(0.05)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, ". Noted.");
        vesna.set_var(switch_time, 3.0); // Slightly faster
        -player_spotted_at(X, Y)[source(Sender)].

// =============================================================================
// EDGE CASES
// =============================================================================

// Allies found but no position 
+allies_nearby(AllyList) : not last_player_pos(_, _)
    <-  .print("Allies found but no player position to share: ", AllyList).

// Handle empty ally list explicitly to prevent .member() failure
+allies_nearby([]) : last_player_pos(_, _)
    <-  .print("No allies nearby to alert.");
        -allies_nearby([]).
