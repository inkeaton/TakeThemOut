// sentry.asl - Revised Temper Annotations

!start.
+!start <- .print("Sentry online.").

// =============================================================================
// PLAYER DETECTION
// =============================================================================

// Aggressive agents react instantly
@player_seen_aggr[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+sight(player, Id, pos(X, Y))
    <-  .print("Target sighted! Engaging!");
        !alert_about_player(X, Y).

// Scared agents startle
@player_seen_fear[temper([fear(0.8)]), effects([fear(0.1)])]
+sight(player, Id, pos(X, Y))
    <-  .print("Target sighted! (Scared)");
        !alert_about_player(X, Y).

// DEFAULT:
// Added 'aggressiveness(0.5)' to compete with the specific plans.
// An agent with Aggressiveness 0.8 will now prefer 'player_seen_aggr' (Dist 0.0) 
// over this default (Dist 0.3).
@player_seen_default[temper([aggressiveness(0.5), fear(0.0)])]
+sight(player, Id, pos(X, Y))
    <-  !alert_about_player(X, Y).

+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// =============================================================================
// ALERT GOAL (Decision Matrix)
// =============================================================================

/* 1. THE CORRUPT (High Sympathy)
   Ignores duty.
*/
@alert_corrupt[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!alert_about_player(X, Y)
    <-  .print("Must be the wind... (Corrupt)");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 8.0); // Slow scan
        vesna.transition_to("Alert", [duration(1)]). // Short duration

/* 2. THE BLOODHOUND (High Aggressiveness)
   Locks down the area.
*/
@alert_bloodhound[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+!alert_about_player(X, Y)
    <-  .print("TARGET LOCKED!");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 0.5); // Fast scan
        vesna.transition_to("Alert", [duration(12)]).

/* 3. THE COWARD (High Fear)
   Panics.
*/
@alert_panic[temper([fear(0.8)]), effects([fear(0.1)])]
+!alert_about_player(X, Y)
    <-  .print("THEY'RE HERE! HELP!");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 1.0);
        vesna.transition_to("Alert", [duration(5)]).

/* 4. THE JOBSWORTH (High Laziness)
   Does the bare minimum.
*/
@alert_lazy[temper([laziness(0.8)])]
+!alert_about_player(X, Y)
    <-  .print("Calling it in. (Lazy)");
        +last_player_pos(X, Y);
        vesna.set_var(switch_time, 4.0);
        vesna.transition_to("Alert", [duration(3)]).

/* 5. DEFAULT (Average Personality)
   We assume 'Average' is Aggro 0.5, Laziness 0.5, Fear 0.0.
   This ensures it loses to extreme personalities.
*/
@alert_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0)])]
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

@resume_lazy[temper([laziness(0.8)])]
+signal_alert(completed, _)
    <-  .print("All clear. Relaxing.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.set_var(switch_time, 6.0);
        vesna.transition_to("Scan").

@resume_scared[temper([fear(0.8)])]
+signal_alert(completed, _)
    <-  .print("Staying alert... just in case.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.set_var(switch_time, 2.0);
        vesna.transition_to("Scan").

// Default assumes average laziness (0.5)
@resume_default[temper([laziness(0.5), fear(0.0)])]
+signal_alert(completed, _)
    <-  .print("Resuming patrol scan.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.set_var(switch_time, 4.0);
        vesna.transition_to("Scan").

// =============================================================================
// CAPTAIN REPORTING
// =============================================================================

// High sympathy = Lie
@report_lie[temper([sympathy(0.8)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .send(Captain, tell, sighting_report(none)); 
        -last_player_pos(X, Y).

// Low/Neutral Sympathy = Truth
// We use sympathy(0.0) so it beats the lie for anyone with sympathy < 0.4
@report_truth[temper([sympathy(0.0)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

// Catch-all (No temper needed as it handles a different context condition)
@report_none
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

// Default assumes average laziness/sympathy
@alert_received_default[temper([laziness(0.5), sympathy(0.0)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, ". Heightening security.");
        vesna.set_var(switch_time, 2.0);
        -player_spotted_at(X, Y)[source(Sender)].

// =============================================================================
// EDGE CASES
// =============================================================================

+allies_nearby([]) : last_player_pos(_, _) <- -allies_nearby([]).
+allies_nearby(L) : not last_player_pos(_, _) <- .print("Allies found, no target."); -allies_nearby(L).

// =============================================================================
// SETUP & CONFIGURATION
// =============================================================================

+!update_sympathy(Value)[source(Sender)]
    <-  .print("Received sympathy update: ", Value, " from ", Sender);
        vesna.add_temper(sympathy, Value).