// sentry.asl - Fixed Temper Annotations

!start.
+!start <- .print("Sentry online.").

// =============================================================================
// PLAYER DETECTION
// =============================================================================

@player_seen_aggr[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+sight(player, Id, pos(X, Y))
    <-  .print("Target sighted! Engaging!");
        !alert_about_player(X, Y).

@player_seen_fear[temper([fear(0.8)]), effects([fear(0.1)])]
+sight(player, Id, pos(X, Y))
    <-  .print("Target sighted! (Scared)");
        !alert_about_player(X, Y).

// Added temper to default so it is considered
@player_seen_default[temper([fear(0.0)])]
+sight(player, Id, pos(X, Y))
    <-  !alert_about_player(X, Y).

+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// =============================================================================
// ALERT GOAL
// =============================================================================

/* 1. THE CORRUPT (High Sympathy) */
@alert_corrupt[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!alert_about_player(X, Y)
    <-  .print("Must be the wind... (Corrupt)");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 8.0);
        vesna.transition_to("Alert", [duration(1)]).

/* 2. THE BLOODHOUND (High Aggressiveness) */
@alert_bloodhound[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+!alert_about_player(X, Y)
    <-  .print("TARGET LOCKED!");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 0.5);
        vesna.transition_to("Alert", [duration(12)]).

/* 3. THE COWARD (High Fear) */
@alert_panic[temper([fear(0.8)]), effects([fear(0.1)])]
+!alert_about_player(X, Y)
    <-  .print("THEY'RE HERE! HELP!");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 1.0);
        vesna.transition_to("Alert", [duration(5)]).

/* 4. DEFAULT (Neutral Fear)
   Critical: Added temper so this plan is not skipped. 
   Distance to fear(0.0) is 0 for a normal agent, making this the winner over Corrupt.
*/
@alert_default[temper([fear(0.0)])]
+!alert_about_player(X, Y)
    <-  .print("Intruder detected. Alerting squad.");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 3.0);
        vesna.transition_to("Alert", [duration(5)]).

// =============================================================================
// BROADCASTING
// =============================================================================

@broadcast_relief[effects([fear(-0.1)])]
+allies_nearby(AllyList) : last_player_pos(X, Y)
    <-  .print("Allies nearby: ", AllyList);
        !broadcast_alert(AllyList, X, Y).

+!broadcast_alert([], _, _).
+!broadcast_alert([Ally|Rest], X, Y)
    <-  .send(Ally, tell, player_spotted_at(X, Y));
        !broadcast_alert(Rest, X, Y).

// =============================================================================
// POST-ALERT RECOVERY
// =============================================================================

@resume_lazy[temper([laziness(0.7)])]
+signal_alert(completed, _)
    <-  .print("All clear. Relaxing.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.set_var(switch_time, 6.0);
        vesna.transition_to("Scan").

@resume_scared[temper([fear(0.7)])]
+signal_alert(completed, _)
    <-  .print("Staying alert... just in case.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.set_var(switch_time, 2.0);
        vesna.transition_to("Scan").

// Added temper to default
@resume_default[temper([fear(0.0)])]
+signal_alert(completed, _)
    <-  .print("Resuming patrol scan.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.set_var(switch_time, 4.0);
        vesna.transition_to("Scan").

// =============================================================================
// CAPTAIN REPORTING (Fixing "No Relevant Plan")
// =============================================================================

@report_lie[temper([sympathy(0.8)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .send(Captain, tell, sighting_report(none)); 
        -last_player_pos(X, Y).

// Added temper so this is visible to the engine
@report_truth[temper([fear(0.0)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

// Added temper to catch-all
@report_none[temper([fear(0.0)])]
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// INCOMING ALERTS
// =============================================================================

@alert_received_lazy[temper([laziness(0.8)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, ". Too far away.");
        -player_spotted_at(X, Y)[source(Sender)].

@alert_received_vengeful[temper([sympathy(-0.7)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, "! Hunting mode engaged.");
        vesna.set_var(switch_time, 1.0);
        -player_spotted_at(X, Y)[source(Sender)].

// Added temper to default
@alert_received_default[temper([fear(0.0)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, ". Heightening security.");
        vesna.set_var(switch_time, 2.0);
        -player_spotted_at(X, Y)[source(Sender)].

// =============================================================================
// EDGE CASES
// =============================================================================

+allies_nearby([]) : last_player_pos(_, _) <- -allies_nearby([]).
+allies_nearby(L) : not last_player_pos(_, _) <- .print("Allies found, no target."); -allies_nearby(L).