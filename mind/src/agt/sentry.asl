// sentry.asl - Sentry agent with player detection and ally alerting
// BDI-style: React to perceptions, delegate to goals, use context conditions
// FEAR SYSTEM: Sentries build fear from player sightings, reduce it with backup

// =============================================================================
// BELIEFS (Knowledge only - no state flags)
// =============================================================================

// None initially - beliefs come from perceptions and inter-agent communication

// =============================================================================
// PERCEPTION HANDLERS (React to body events)
// =============================================================================

// When we see the player - trigger alert goal
// The +sight belief is added by VesnaAgent.handleSight()
+sight(player, Id, pos(X, Y))
    <-  .print("PLAYER DETECTED at position (", X, ", ", Y, ")!");
        !alert_about_player(X, Y).

// Supersede pattern: when new position arrives, remove old one
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// Body found allies during alert scan - broadcast if we have position
// Fear decreases when allies arrive (strength in numbers)
@allies_found_relief[effects([fear(-0.1)])]
+allies_nearby(AllyList) : last_player_pos(X, Y)
    <-  .print("Allies found: ", AllyList);
        !broadcast_alert(AllyList, X, Y).

// Allies found but no position (edge case) - just log
+allies_nearby(AllyList) : not last_player_pos(_, _)
    <-  .print("Allies found but no player position to share: ", AllyList).

// Body finished alert sequence - clean up and ready for next detection
// Completing duty reduces fear slightly
@alert_complete[effects([fear(-0.05)])]
+signal_alert(completed, _)
    <-  .print("Alert sequence completed. Ready for next detection.");
        -signal_alert(completed, _);
        -allies_nearby(_);
        // Remove the sight belief so +sight can trigger again on next detection
        .abolish(sight(player, _, _)).

// =============================================================================
// ALERT GOAL (Sequence of actions for alerting - Fear-based variations)
// =============================================================================

// HIGH FEAR (> 0.7): Panic broadcast with emergency call
@alert_panic[temper([fear(0.8)]), effects([fear(0.25)])]
+!alert_about_player(X, Y)
    <-  .print("EMERGENCY! ENEMY CONTACT! ALL UNITS RESPOND!");
        +last_player_pos(X, Y);
        .broadcast(tell, emergency_at(X, Y)); // Extra broadcast
        vesna.alert.

// MEDIUM FEAR (0.4-0.7): Urgent alert with emphasis
@alert_nervous[temper([fear(0.5)]), effects([fear(0.2)])]
+!alert_about_player(X, Y)
    <-  .print("INTRUDER ALERT! Position logged, calling for backup!");
        +last_player_pos(X, Y);
        vesna.alert.

// LOW FEAR (< 0.4): Calm, efficient alert
@alert_calm[temper([fear(0.2)]), effects([fear(0.15)])]
+!alert_about_player(X, Y)
    <-  .print("Target acquired. Notifying squad.");
        +last_player_pos(X, Y);
        vesna.alert.

// =============================================================================
// BROADCASTING PLANS (Recursive message sending)
// =============================================================================

+!broadcast_alert([], _, _)
    <-  .print("Broadcast complete.").

+!broadcast_alert([Ally | Rest], X, Y)
    <-  .print("Sending alert to ", Ally);
        .send(Ally, tell, player_spotted_at(X, Y));
        !broadcast_alert(Rest, X, Y).

// Failure handler - continue with remaining allies
-!broadcast_alert([Ally | Rest], X, Y)
    <-  .print("Warning: Failed to alert ", Ally, ". Continuing...");
        !broadcast_alert(Rest, X, Y).

// =============================================================================
// INTEL REPORTING (Responding to Captain requests)
// =============================================================================

// Captain asks for sightings - report if we have one
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Reporting sighting at ", X, ",", Y, " to ", Captain);
        .send(Captain, tell, sighting_report(pos(X, Y)));
        // Clear after reporting so we don't report stale data
        -last_player_pos(X, Y).

// Captain asks but we have no sighting
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).
