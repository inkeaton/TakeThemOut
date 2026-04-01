// patrol.asl - Patrol agent with Full Temper System

!start_patrol.

// =============================================================================
// BOOTSTRAP
// =============================================================================

/* STARTUP: Announces patrol activation and enters patrol state. */
+!start_patrol <- .print("Starting patrol."); vesna.transition_to("Patrol", [target("next")]).

// =============================================================================
// KNOWLEDGE & STATE MANAGEMENT
// =============================================================================

consecutive_failures(0).
is_chasing(no).
responding_to_alert(no).
is_messenger(no).
messenger_target(none).
messenger_report_pos(none).
messenger_sent(no).
messenger_failed(no).

/* STATE UPDATE: Keeps a single authoritative chase-state value. */
+is_chasing(S) : is_chasing(Old) & Old \== S <- -is_chasing(Old).
/* STATE UPDATE: Keeps one alert-response state at a time. */
+responding_to_alert(S) : responding_to_alert(Old) & Old \== S <- -responding_to_alert(Old).
/* STATE UPDATE: Keeps one messenger-state value at a time. */
+is_messenger(S) : is_messenger(Old) & Old \== S <- -is_messenger(Old).
/* STATE UPDATE: Keeps one messenger-failure lock value at a time. */
+messenger_failed(S) : messenger_failed(Old) & Old \== S <- -messenger_failed(Old).
/* STATE UPDATE: Stores only the latest observed player position. */
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y) <- -last_player_pos(OldX, OldY).
/* STATE UPDATE: Stores only the latest consecutive-failure counter. */
+consecutive_failures(N) : consecutive_failures(Old) & Old \== N <- -consecutive_failures(Old).

// =============================================================================
// MAIN ROLE LOOP
// =============================================================================

/* LOOP ENTRY: Patrol cycle starts by choosing next movement strategy. */
+!patrol <- !decide_next_step.

/* STEP FEARFUL: Holds position when the environment feels unsafe. */
@step_fearful[temper([fear(0.8)])]
+!decide_next_step
    <-  .print("Too quiet... I'm holding position.");
        .wait(4000);
        !decide_next_step.

/* STEP AGGRESSIVE: Occasionally backtracks to check rear approach. */
@step_aggressive[temper([aggressiveness(0.8), fear(0.4)])]
+!decide_next_step : .random(R) & R < 0.3
    <-  .print("Checking my six! (Aggressive Check)");
        vesna.transition_to("Patrol", [target("prev")]).

/* STEP DEFAULT: Advances toward the next patrol waypoint. */
@step_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0)])]
+!decide_next_step
    <-  vesna.transition_to("Patrol", [target("next")]).

// =============================================================================
// WAYPOINT ARRIVAL & REST
// =============================================================================

/* WAYPOINT ARRIVAL: Rests at waypoint, then resumes patrol loop. */
@navigation_waypoint[effects([fear(-0.02)])]
+navigation(reached, Waypoint) : is_chasing(no) & responding_to_alert(no) & is_messenger(no)
    <-  .print("Reached ", Waypoint);
        -navigation(reached, Waypoint);
        !rest_at_waypoint;
        !patrol.

/* WAYPOINT IGNORE: Discards waypoint events while busy in other modes. */
+navigation(reached, W) : is_chasing(yes) | responding_to_alert(yes) | is_messenger(yes)
    <- -navigation(reached, W).

/* REST SYMPATHETIC: Takes a long break instead of rotating quickly. */
@rest_sympathetic[temper([sympathy(0.8)])]
+!rest_at_waypoint
    <-  .print("Taking a smoke break. (Corrupt)");
        .wait(8000).

/* REST LAZY: Stays paused longer before moving again. */
@rest_lazy[temper([laziness(0.8)])]
+!rest_at_waypoint
    <-  .print("Ugh, feet hurt. Resting.");
        .wait(6000).

/* REST AGGRESSIVE: Minimizes rest duration to keep pressure high. */
@rest_aggressive[temper([aggressiveness(0.8)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving.");
        .wait(500).

/* REST DEFAULT: Uses a short neutral rest cadence at waypoint. */
@rest_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!rest_at_waypoint
    <-  .wait(2000).

// =============================================================================
// INTEL REPORTING
// =============================================================================

/* REPORT SYMPATHETIC: Hides target intel from captain. */
@report_sympathetic[temper([sympathy(0.8)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Lying to Captain (Corrupt)");
        .send(Captain, tell, sighting_report(none));
        -last_player_pos(X, Y).

/* REPORT DEFAULT: Sends truthful last known player position. */
@report_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Reporting sighting to ", Captain);
        .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

/* REPORT EMPTY: Returns none when no intel is available. */
@report_none
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// DIRECT DETECTION & CHASE
// =============================================================================

/* CHASE TRIGGER: Enters chase mode on first player contact. */
@chase_trigger[effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("CONTACT!");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        -messenger_sent(_); +messenger_sent(no);
        -messenger_failed(_); +messenger_failed(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        !start_chase.

/* CHASE UPDATE: Refreshes last known position while already chasing. */
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  -last_player_pos(_, _); +last_player_pos(X, Y).

/* CHASE SYMPATHETIC: Feigns pursuit with very low patience. */
@chase_sympathetic[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!start_chase
    <-  .print("Oh no, he's fast... (Feigning effort)");
        vesna.transition_to("Chase", [patience(2)]).

/* CHASE VENGEFUL: Pursues relentlessly with high persistence. */
@chase_vengeful[temper([sympathy(-0.8), aggressiveness(0.8)]), effects([fear(-0.05)])]
+!start_chase
    <-  .print("YOU CAN'T HIDE!");
        vesna.transition_to("Chase", [patience(25)]).

/* CHASE LAZY: Performs short pursuit before giving up. */
@chase_lazy[temper([laziness(0.8)])]
+!start_chase
    <-  .print("I'll check, but I'm not running.");
        vesna.transition_to("Chase", [patience(5)]).

/* CHASE DEFAULT: Uses standard pursuit patience and behavior. */
@chase_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!start_chase
    <-  .print("Engaging target.");
        vesna.transition_to("Chase", [patience(10)]).

// =============================================================================
// RECOVERY & RESET
// =============================================================================

/* TARGET LOST: Increments failure count and starts area investigation. */
@target_lost_trigger[effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost at ", X, ",", Y);
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N); +consecutive_failures(N+1);
        !investigate_area.

/* RECOVER SYMPATHETIC: Performs minimal follow-up investigation. */
@recover_sympathetic[temper([sympathy(0.8)])]
+!investigate_area
    <-  .print("Gone. Oh well. (Corrupt)");
        vesna.transition_to("Investigate", [points(1)]).

/* RECOVER LAZY: Performs short low-effort sweep. */
@recover_lazy[temper([laziness(0.8)])]
+!investigate_area
    <-  .print("Probably gone.");
        vesna.transition_to("Investigate", [points(1)]).

/* RECOVER VENGEFUL: Performs wider and more persistent sweep. */
@recover_vengeful[temper([sympathy(-0.8)])]
+!investigate_area
    <-  .print("I know you're here somewhere...");
        vesna.transition_to("Investigate", [points(8)]).

/* RECOVER DEFAULT: Performs standard investigation pattern. */
@recover_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!investigate_area
    <-  .print("Scanning area.");
        vesna.transition_to("Investigate", [points(3)]).

/* INVESTIGATION DONE: Resets chase state and resumes patrol cycle. */
@investigation_done[effects([fear(-0.05)])]
+signal_investigation(complete, Reason)
    <-  .print("Area secure.");
        -signal_investigation(complete, Reason);
        -is_chasing(_); +is_chasing(no);
        -responding_to_alert(_); +responding_to_alert(no);
        -last_player_pos(_, _);
        -consecutive_failures(_); +consecutive_failures(0);
        -messenger_sent(_); +messenger_sent(no);
        -messenger_failed(_); +messenger_failed(no);
        .abolish(sight(player, _, _));
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// MESSENGER SYSTEM
// =============================================================================

/* MESSENGER RECRUIT: Assigns the first nearby ally to report intel. */
+allies_nearby(AllyList) : is_chasing(yes) & last_player_pos(X, Y) & not .empty(AllyList) & messenger_sent(no) & messenger_failed(no)
    <-  .nth(0, AllyList, FirstAlly);
        .print("Recruiting ", FirstAlly, " as messenger.");
        .send(FirstAlly, achieve, become_messenger(pos(X, Y)));
        -messenger_sent(no); +messenger_sent(yes);
        -allies_nearby(AllyList).

/* MESSENGER ACCEPT: Idle ally accepts duty and seeks nearest captain. */
@messenger_accept[temper([fear(0.0)])]
+!become_messenger(pos(X, Y))[source(Sender)] : is_chasing(no) & is_messenger(no)
    <-  .print("Messenger duty accepted. Finding Captain.");
        -messenger_report_pos(_); +messenger_report_pos(pos(X, Y));
        -is_messenger(no); +is_messenger(yes);
        .drop_intention(patrol);
        vesna.transition_to("Patrol", [target("find_captain")]).

/* MESSENGER REJECT: Declines messenger request while actively chasing. */
+!become_messenger(_)[source(Sender)] : is_chasing(yes)
    <- .send(Sender, tell, messenger_rejected(busy)).

/* MESSENGER REJECT: Declines messenger request while already assigned. */
+!become_messenger(_)[source(Sender)] : is_messenger(yes)
    <- .send(Sender, tell, messenger_rejected(already_messenger)).

/* MESSENGER FAIL: Locks messenger dispatch for this chase after rejection. */
+messenger_rejected(Reason)[source(Ally)] : messenger_sent(yes) & messenger_failed(no) & is_chasing(yes)
    <-  .print("Messenger rejected by ", Ally, " (", Reason, "). No retry this chase.");
        -messenger_rejected(Reason)[source(Ally)];
        -messenger_failed(no); +messenger_failed(yes);
        -messenger_sent(_); +messenger_sent(no).

/* MESSENGER CLEANUP: Removes stale rejection beliefs when not relevant. */
+messenger_rejected(Reason)[source(Ally)]
    <- -messenger_rejected(Reason)[source(Ally)].

/* MESSENGER SUCCESS: Delivers intel to captain and returns to patrol. */
+navigation(reached_agent, Captain) : is_messenger(yes) & messenger_report_pos(pos(X, Y))
    <-  .print("Reporting to ", Captain);
        -navigation(reached_agent, Captain);
        .send(Captain, tell, player_spotted_at(X, Y));
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        vesna.set_var(is_messenger, false);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

/* MESSENGER FALLBACK: Aborts duty when no captain can be located. */
+navigation(no_captain_found, _) : is_messenger(yes)
    <-  .print("No captain found. Aborting messenger duty.");
        -navigation(no_captain_found, _);
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        -messenger_failed(no); +messenger_failed(yes);
        -messenger_sent(_); +messenger_sent(no);
        vesna.set_var(is_messenger, false);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

/* MESSENGER FALLBACK: Aborts duty when captain target becomes invalid. */
+navigation(agent_lost, _) : is_messenger(yes)
    <-  .print("Lost captain during navigation. Aborting messenger duty.");
        -navigation(agent_lost, _);
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        -messenger_failed(no); +messenger_failed(yes);
        -messenger_sent(_); +messenger_sent(no);
        vesna.set_var(is_messenger, false);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// INCOMING ALERTS
// =============================================================================

/* ALERT RESPOND SYMPATHETIC: Delays response before reacting to squad alert. */
@alert_respond_sympathetic[temper([sympathy(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". I'll get there... eventually.");
        .wait(3000);
        !respond_to_alert(X, Y).

/* ALERT RESPOND DEFAULT: Immediately redirects toward alerted position. */
@alert_respond_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, "! Intercepting.");
        !respond_to_alert(X, Y).

/* ALERT HANDLER: Drops active intentions and navigates to reported coords. */
+!respond_to_alert(X, Y)
    <-  .drop_all_intentions;
        +last_player_pos(X, Y);
        -responding_to_alert(no); +responding_to_alert(yes);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

/* ALERT CLEANUP: Removes stale alert beliefs after handling. */
+player_spotted_at(X, Y) <- -player_spotted_at(X, Y).

/* ALERT CLEANUP: Removes stale ally-scan beliefs after handling. */
+allies_nearby(L) <- -allies_nearby(L).

/* ALERT ARRIVAL: Starts quick investigation on reaching alert position. */
+navigation(reached_target, _) : is_chasing(no)
    <- -navigation(reached_target, _); vesna.transition_to("Investigate", [points(2)]).

// =============================================================================
// SETUP & CONFIGURATION
// =============================================================================

/* SETUP: Applies sympathy updates received from director setup phase. */
+!update_sympathy(Value)[source(Sender)]
    <-  .print("Received sympathy update: ", Value, " from ", Sender);
        vesna.add_temper(sympathy, Value).