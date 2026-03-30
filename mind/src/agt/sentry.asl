// sentry.asl - Sentry agent with unified style

!start.

// =============================================================================
// BOOTSTRAP
// =============================================================================

/* STARTUP: Announces sentry activation at boot. */
+!start <- .print("Sentry online.").

// =============================================================================
// KNOWLEDGE & STATE MANAGEMENT
// =============================================================================

/* MEMORY UPDATE: Keeps only the latest known player position. */
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y)
    <-  -last_player_pos(OldX, OldY).

// =============================================================================
// DIRECT DETECTION
// =============================================================================

/* AGGRESSIVE: Reacts instantly and becomes slightly less fearful. */
@detect_aggressive[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+sight(player, Id, pos(X, Y))
    <-  .print("Target sighted! Engaging!");
        !alert_about_player(X, Y).

/* FEARFUL: Startles on contact and gains fear. */
@detect_fearful[temper([fear(0.8)]), effects([fear(0.1)])]
+sight(player, Id, pos(X, Y))
    <-  .print("Target sighted! (Scared)");
        !alert_about_player(X, Y).

/* DEFAULT: Balanced reaction profile. */
@detect_default[temper([aggressiveness(0.5), fear(0.0)])]
+sight(player, Id, pos(X, Y))
    <-  !alert_about_player(X, Y).

// =============================================================================
// ALERT EXECUTION
// =============================================================================

/* SYMPATHETIC: Minimizes response and quickly drops alert state. */
@alert_sympathetic[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!alert_about_player(X, Y)
    <-  .print("Must be the wind... (Corrupt)");
        +last_player_pos(X, Y);
        vesna.transition_to("Alert", [duration(1)]).

/* AGGRESSIVE: Locks the area down for longer duration. */
@alert_aggressive[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+!alert_about_player(X, Y)
    <-  .print("TARGET LOCKED!");
        +last_player_pos(X, Y);
        vesna.transition_to("Alert", [duration(12)]).

/* FEARFUL: Panics and calls for support. */
@alert_fearful[temper([fear(0.8)]), effects([fear(0.1)])]
+!alert_about_player(X, Y)
    <-  .print("THEY'RE HERE! HELP!");
        +last_player_pos(X, Y);
        vesna.transition_to("Alert", [duration(5)]).

/* LAZY: Performs only a short alert cycle. */
@alert_lazy[temper([laziness(0.8)])]
+!alert_about_player(X, Y)
    <-  .print("Calling it in. (Lazy)");
        +last_player_pos(X, Y);
        vesna.transition_to("Alert", [duration(3)]).

/* DEFAULT: Average profile for non-extreme traits. */
@alert_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0)])]
+!alert_about_player(X, Y)
    <-  .print("Intruder detected. Alerting squad.");
        +last_player_pos(X, Y);
        vesna.transition_to("Alert", [duration(5)]).

// =============================================================================
// BROADCASTING
// =============================================================================

/* BROADCAST TRIGGER: Starts alert relay when allies are in range. */
@broadcast_default[effects([fear(-0.1)])]
+allies_nearby(AllyList) : last_player_pos(X, Y)
    <-  .print("Allies nearby: ", AllyList);
        !broadcast_alert(AllyList, X, Y).

/* BROADCAST BASE CASE: Stops recursion when no allies remain. */
+!broadcast_alert([], _, _).
/* BROADCAST STEP: Sends alert to one ally and continues recursively. */
+!broadcast_alert([Ally|Rest], X, Y)
    <-  .send(Ally, tell, player_spotted_at(X, Y));
        !broadcast_alert(Rest, X, Y).

// =============================================================================
// INCOMING ALERTS
// =============================================================================

/* INCOMING LAZY: Dismisses external alert and keeps current posture. */
@incoming_alert_lazy[temper([laziness(0.8)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, ". Too far away.");
        -player_spotted_at(X, Y)[source(Sender)].

/* INCOMING VENGEFUL: Increases scan speed after external alert. */
@incoming_alert_vengeful[temper([sympathy(-0.7)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, "! Hunting mode engaged.");
        vesna.set_var(switch_time, 1.0);
        -player_spotted_at(X, Y)[source(Sender)].

/* INCOMING DEFAULT: Heightens vigilance with moderate scan speed. */
@incoming_alert_default[temper([laziness(0.5), sympathy(0.0)])]
+player_spotted_at(X, Y)[source(Sender)]
    <-  .print("Alert from ", Sender, ". Heightening security.");
        vesna.set_var(switch_time, 2.0);
        -player_spotted_at(X, Y)[source(Sender)].

// =============================================================================
// RECOVERY & RESET
// =============================================================================

/* RECOVERY LAZY: Returns to slow scanning after alert completion. */
@recover_lazy[temper([laziness(0.8)])]
+signal_alert(completed, _)
    <-  .print("All clear. Relaxing.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.transition_to("Scan", [switch_time(6.0)]).

/* RECOVERY FEARFUL: Keeps faster scanning due to lingering anxiety. */
@recover_fearful[temper([fear(0.8)])]
+signal_alert(completed, _)
    <-  .print("Staying alert... just in case.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.transition_to("Scan", [switch_time(2.0)]).

/* RECOVERY DEFAULT: Restores standard scan rhythm after alert. */
@recover_default[temper([laziness(0.5), fear(0.0)])]
+signal_alert(completed, _)
    <-  .print("Resuming patrol scan.");
        -signal_alert(completed, _);
        .abolish(sight(player, _, _));
        vesna.transition_to("Scan", [switch_time(4.0)]).

// =============================================================================
// CAPTAIN REPORTING
// =============================================================================

/* REPORT SYMPATHETIC: Hides player position from captain. */
@report_sympathetic[temper([sympathy(0.8)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .send(Captain, tell, sighting_report(none));
        -last_player_pos(X, Y).

/* REPORT DEFAULT: Sends truthful last known player position. */
@report_default[temper([sympathy(0.0)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

/* REPORT EMPTY: Returns no intel when no position is available. */
@report_none
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// EDGE CASES
// =============================================================================

/* EDGE CASE: Clears empty ally-list events once consumed. */
+allies_nearby([]) : last_player_pos(_, _) <- -allies_nearby([]).
/* EDGE CASE: Drops ally events if no tracked player position exists. */
+allies_nearby(L) : not last_player_pos(_, _) <- .print("Allies found, no target."); -allies_nearby(L).

// =============================================================================
// SETUP & CONFIGURATION
// =============================================================================

/* SETUP: Applies sympathy updates sent by the director agent. */
+!update_sympathy(Value)[source(Sender)]
    <-  .print("Received sympathy update: ", Value, " from ", Sender);
        vesna.add_temper(sympathy, Value).