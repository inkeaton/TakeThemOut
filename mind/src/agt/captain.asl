// captain.asl - Captain Agent with Full Temper System

!start_patrol.

// =============================================================================
// BOOTSTRAP
// =============================================================================

/* STARTUP: Announces captain activation and enters patrol state. */
+!start_patrol <- .print("Captain on deck."); vesna.transition_to("Patrol", [target("next")]).

// =============================================================================
// KNOWLEDGE & STATE MANAGEMENT
// =============================================================================

consecutive_failures(0).
is_chasing(no).
responding_to_alert(no).

/* STATE UPDATE: Keeps a single authoritative chase-state value. */
+is_chasing(S) : is_chasing(Old) & Old \== S <- -is_chasing(Old).
/* STATE UPDATE: Keeps one alert-response state at a time. */
+responding_to_alert(S) : responding_to_alert(Old) & Old \== S <- -responding_to_alert(Old).
/* STATE UPDATE: Stores only the latest known player position. */
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y) <- -last_player_pos(OldX, OldY).
/* STATE UPDATE: Stores only the latest known alert position. */
+last_alert_pos(X, Y) : last_alert_pos(OldX, OldY) & (OldX \== X | OldY \== Y) <- -last_alert_pos(OldX, OldY).
/* STATE UPDATE: Stores only the latest consecutive-failure counter. */
+consecutive_failures(N) : consecutive_failures(Old) & Old \== N <- -consecutive_failures(Old).

// =============================================================================
// MAIN ROLE LOOP
// =============================================================================

/* LOOP ENTRY: Starts intel-driven patrol command cycle. */
+!patrol <- !gather_intel.

/* INTEL GATHER: Requests sighting reports from all squad agents. */
+!gather_intel
    <-  .print("Checkpoint reached. Requesting sitrep.");
        .broadcast(achieve, report_sightings);
        .wait(2000);
        !analyze_intel.

/* ANALYZE SYMPATHETIC: Ignores intel and avoids useful interception. */
@analyze_sympathetic[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)] & Pos \== none, Reports);
        .abolish(sighting_report(_));
        .print("Intel ignored. (Sabotage)");
        vesna.transition_to("Patrol", [target("random")]).

/* ANALYZE LAZY: Discards intel and maintains current patrol route. */
@analyze_lazy[temper([laziness(0.8), fear(0.6)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)] & Pos \== none, Reports);
        .abolish(sighting_report(_));
        .print("Too much noise. Maintaining course.");
        vesna.transition_to("Patrol", [target("next")]).

/* ANALYZE DEFAULT: Collects reports and delegates to intercept logic. */
@analyze_default[temper([sympathy(0.0), laziness(0.5), fear(0.0)]), effects([fear(-0.05)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)] & Pos \== none, Reports);
        .abolish(sighting_report(_));
        .print("Analyzing intel: ", Reports);
        !act_on_intel(Reports).

/* ACT EMPTY DEFAULT: Continues waypoint patrol with no actionable intel. */
@act_empty_default[temper([aggressiveness(0.5), fear(0.0)])]
+!act_on_intel([])
    <-  .print("No actionable intel (Sector clear).");
        vesna.transition_to("Patrol", [target("next")]).

/* ACT EMPTY AGGRESSIVE: Hunts randomly when reports are empty. */
@act_empty_aggressive[temper([aggressiveness(0.8)])]
+!act_on_intel([])
    <- .print("No targets. Hunting randomly.");
       vesna.transition_to("Patrol", [target("random")]).

/* ACT INTERCEPT AGGRESSIVE: Drives squad toward centroid aggressively. */
@act_intercept_aggressive[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("INTERCEPT COURSE SET: ", AvgX, ",", AvgY);
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

/* ACT INTERCEPT FEARFUL: Delays and approaches reported area cautiously. */
@act_intercept_fearful[temper([fear(0.8)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("Multiple contacts... Proceeding with caution.");
        .wait(1500);
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

/* ACT INTERCEPT DEFAULT: Moves to centroid with standard urgency. */
@act_intercept_default[temper([aggressiveness(0.5), fear(0.0)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("Converging on target.");
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

// =============================================================================
// HANDLING SIGHTING REPORTS
// =============================================================================

/* REPORT IN: Logs concrete positional report from a squad member. */
+sighting_report(pos(X, Y))[source(Sender)]
    <- .print("Received report from ", Sender).

/* REPORT IN: Accepts explicit no-sighting reports for aggregation. */
+sighting_report(none)[source(_)].

// =============================================================================
// NAVIGATION & ARRIVAL
// =============================================================================

/* NAV WAYPOINT: Resumes patrol cycle after reaching a waypoint. */
@nav_waypoint[effects([fear(-0.02)])]
+navigation(reached, W) : is_chasing(no) & responding_to_alert(no)
    <-  .print("Arrived at ", W);
        -navigation(reached, W);
        !patrol.

/* NAV INTERCEPT: Begins investigate phase after reaching intercept target. */
@nav_intercept[effects([fear(-0.05)])]
+navigation(reached_target, C) : is_chasing(no)
    <-  .print("Intercept complete. Investigating.");
        -navigation(reached_target, C);
        -responding_to_alert(_); +responding_to_alert(no);
        vesna.transition_to("Investigate", [points(5)]).

/* NAV IGNORE: Drops navigation events while actively chasing. */
+navigation(Status, _) : is_chasing(yes) <- -navigation(Status, _).

// =============================================================================
// DIRECT DETECTION & CHASE
// =============================================================================

/* CHASE SYMPATHETIC: Starts short chase and withholds squad broadcast. */
@chase_sympathetic[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Oh, it's you. Run away. (Saboteur)");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(5)]).

/* CHASE AGGRESSIVE: Broadcasts contact and leads full-squad pursuit. */
@chase_aggressive[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("TARGET ACQUIRED! ALL UNITS CONVERGE!");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(25)]).

/* CHASE DEFAULT: Broadcasts contact and runs standard command pursuit. */
@chase_default[temper([sympathy(0.0), aggressiveness(0.5), fear(0.0)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Contact! Taking command.");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(15)]).

/* CHASE UPDATE: Refreshes target position while already in chase mode. */
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  -last_player_pos(_, _); +last_player_pos(X, Y).

// =============================================================================
// INCOMING ALERTS
// =============================================================================

/* ALERT SYMPATHETIC: Discards alert and avoids engagement. */
@alert_sympathetic[temper([sympathy(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". Disregarding. (Sabotage)");
        -player_spotted_at(X, Y)[source(Sender)];
        vesna.transition_to("Patrol", [target("random")]).

/* ALERT LAZY: Delegates work and relays only if sender is not captain. */
@alert_lazy[temper([laziness(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". Squad, handle it.");
        -player_spotted_at(X, Y)[source(Sender)];
        .term2string(Sender, SenderStr);
        if (not .substring("captain", SenderStr)) {
            .broadcast(tell, player_spotted_at(X, Y));
        } else {
            .print("Received from HQ/Captain. Not echoing.");
        }
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

/* ALERT DEFAULT: Relays alert safely and redirects squad to position. */
@alert_default[temper([sympathy(0.0), laziness(0.5), fear(0.0)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". Redirecting squad.");
        -player_spotted_at(X, Y)[source(Sender)];
        .term2string(Sender, SenderStr);
        if (not .substring("captain", SenderStr)) {
            .broadcast(tell, player_spotted_at(X, Y));
        } else {
            .print("Received from HQ/Captain. Not echoing.");
        }
        .drop_all_intentions;
        -responding_to_alert(no); +responding_to_alert(yes);
        +last_alert_pos(X, Y);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

/* ALERT BUSY: Updates destination while already chasing or rerouting. */
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(yes) | responding_to_alert(yes)
    <-  .print("Update from ", Sender);
        -player_spotted_at(X, Y)[source(Sender)];
        .term2string(Sender, SenderStr);
        if (not .substring("captain", SenderStr)) {
            .broadcast(tell, player_spotted_at(X, Y));
        }
        +last_alert_pos(X, Y);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// =============================================================================
// RECOVERY & RESET
// =============================================================================

/* TARGET LOST: Raises failure counter and triggers investigation routine. */
@target_lost_trigger[effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. Frustration rising.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N); +consecutive_failures(N+1);
        !investigate_area.

/* RECOVER FEARFUL: Cuts investigation short after repeated failures. */
@recover_fearful[temper([fear(0.6)])]
+!investigate_area : consecutive_failures(N) & N > 2
    <-  .print("They are gone. I'm not wasting time.");
        vesna.transition_to("Investigate", [points(2)]).

/* RECOVER DEFAULT: Performs standard investigation routine. */
@recover_default[temper([fear(0.0)])]
+!investigate_area
    <-  vesna.transition_to("Investigate", [points(5)]).

/* INVESTIGATION DONE: Resets operational state and resumes patrol loop. */
@investigation_done[effects([fear(-0.05)])]
+signal_investigation(complete, Reason)
    <-  .print("Area secured.");
        -signal_investigation(complete, Reason);
        -is_chasing(_); +is_chasing(no);
        -responding_to_alert(_); +responding_to_alert(no);
        -last_player_pos(_, _); -last_alert_pos(_, _);
        -consecutive_failures(_); +consecutive_failures(0);
        .abolish(sight(player, _, _));
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

/* FAILURE FALLBACK: Returns to random patrol when intel gather fails. */
-!gather_intel <- .print("Intel failed."); vesna.transition_to("Patrol", [target("random")]).

/* FAILURE FALLBACK: Returns to random patrol when intel analysis fails. */
-!analyze_intel <- .print("Analysis failed."); vesna.transition_to("Patrol", [target("random")]).

/* REPORT IGNORE: Discards external report-sightings requests for captain. */
+!report_sightings[source(_)].

/* MESSENGER REJECT: Captains do not accept messenger-role reassignment. */
+!become_messenger(_)[source(Sender)]
    <- .send(Sender, tell, messenger_rejected(not_patrol_role)).

// =============================================================================
// SETUP & CONFIGURATION
// =============================================================================

/* SETUP: Applies sympathy update from the director at game start. */
+!update_sympathy(Value)[source(Sender)]
    <-  .print("Received sympathy update: ", Value, " from ", Sender);
        vesna.add_temper(sympathy, Value).