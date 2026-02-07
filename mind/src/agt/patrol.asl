// patrol.asl - Patrol agent with Full Temper System

!start_patrol.

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

// Supersede patterns (State Management)
+is_chasing(S) : is_chasing(Old) & Old \== S <- -is_chasing(Old).
+responding_to_alert(S) : responding_to_alert(Old) & Old \== S <- -responding_to_alert(Old).
+is_messenger(S) : is_messenger(Old) & Old \== S <- -is_messenger(Old).
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y) <- -last_player_pos(OldX, OldY).
+consecutive_failures(N) : consecutive_failures(Old) & Old \== N <- -consecutive_failures(Old).

// =============================================================================
// PATROL LOOP
// =============================================================================

+!start_patrol <- .print("Starting patrol."); vesna.transition_to("Patrol", [target("next")]).

+!patrol <- !decide_next_step.

/* DECISION LOGIC:
   - Scared: Freeze or Backtrack.
   - Aggressive: Backtrack (Check Six).
   - Default: Forward.
*/

@step_scared[temper([fear(0.8)])]
+!decide_next_step
    <-  .print("Too quiet... I'm holding position.");
        .wait(4000);
        !decide_next_step.

@step_paranoid[temper([aggressiveness(0.5), fear(0.4)])]
+!decide_next_step : .random(R) & R < 0.3
    <-  .print("Checking my six! (Aggressive Check)");
        vesna.transition_to("Patrol", [target("prev")]).

@step_default[temper([fear(0.0)])]
+!decide_next_step
    <-  vesna.transition_to("Patrol", [target("next")]).

// =============================================================================
// REST BEHAVIOR (Waypoint Arrival)
// =============================================================================

@navigation_waypoint[effects([fear(-0.02)])]
+navigation(reached, Waypoint) : is_chasing(no) & responding_to_alert(no) & is_messenger(no)
    <-  .print("Reached ", Waypoint);
        -navigation(reached, Waypoint);
        !rest_at_waypoint;
        !patrol.

// Ignore nav events in other states
+navigation(reached, W) : is_chasing(yes) | responding_to_alert(yes) | is_messenger(yes)
    <- -navigation(reached, W).

/* REST LOGIC:
   - Corrupt: Long wait (Let player pass).
   - Lazy: Long wait (Tired).
   - Vigilant (Aggro): Short wait.
*/

@rest_corrupt[temper([sympathy(0.8)])]
+!rest_at_waypoint
    <-  .print("Taking a smoke break. (Corrupt)");
        .wait(8000).

@rest_lazy[temper([laziness(0.8)])]
+!rest_at_waypoint
    <-  .print("Ugh, feet hurt. Resting.");
        .wait(6000).

@rest_vigilant[temper([aggressiveness(0.8)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving.");
        .wait(500).

@rest_default[temper([fear(0.0)])]
+!rest_at_waypoint
    <-  .wait(2000).

// =============================================================================
// INTEL REPORTING (Responding to Captain) - ADDED THIS SECTION
// =============================================================================

/* If I like the player (Corrupt), I lie to the captain saying I saw nothing.
   This protects the player from a coordinated intercept.
*/
@report_corrupt[temper([sympathy(0.8)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Lying to Captain (Corrupt)");
        .send(Captain, tell, sighting_report(none));
        -last_player_pos(X, Y).

/* Default behavior: Report the position and clear memory 
   so we don't report stale data next time.
*/
@report_default[temper([fear(0.0)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Reporting sighting to ", Captain);
        .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

/* No intel to report */
@report_none[temper([fear(0.0)])]
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// CHASE BEHAVIOR (Player Detection)
// =============================================================================

// Sight increases Fear slightly (startle)
@chase_trigger[effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("CONTACT!");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        !start_chase.

// Keep tracking
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  -last_player_pos(_, _); +last_player_pos(X, Y).

/* CHASE LOGIC:
   - Corrupt: Fake chase (2 crumbs patience).
   - Relentless: Long chase (25 crumbs patience).
   - Lazy: Short chase (5 crumbs patience).
*/

@chase_corrupt[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!start_chase
    <-  .print("Oh no, he's fast... (Feigning effort)");
        vesna.transition_to("Chase", [patience(2)]).

@chase_relentless[temper([sympathy(-0.8), aggressiveness(0.8)]), effects([fear(-0.05)])]
+!start_chase
    <-  .print("YOU CAN'T HIDE!");
        vesna.transition_to("Chase", [patience(25)]).

@chase_lazy[temper([laziness(0.8)])]
+!start_chase
    <-  .print("I'll check, but I'm not running.");
        vesna.transition_to("Chase", [patience(5)]).

@chase_default[temper([fear(0.0)])]
+!start_chase
    <-  .print("Engaging target.");
        vesna.transition_to("Chase", [patience(10)]).

// =============================================================================
// RECOVERY (Target Lost -> Investigate)
// =============================================================================

// Losing target increases fear
@target_lost_trigger[effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost at ", X, ",", Y);
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N); +consecutive_failures(N+1);
        !investigate_area.

/* INVESTIGATE LOGIC:
   - Corrupt/Lazy: 1 point (Give up).
   - Vengeful/Paranoid: 8 points (Thorough).
*/

@recover_corrupt[temper([sympathy(0.8)])]
+!investigate_area
    <-  .print("Gone. Oh well. (Corrupt)");
        vesna.transition_to("Investigate", [points(1)]).

@recover_lazy[temper([laziness(0.8)])]
+!investigate_area
    <-  .print("Probably gone.");
        vesna.transition_to("Investigate", [points(1)]).

@recover_vengeful[temper([sympathy(-0.8)])]
+!investigate_area
    <-  .print("I know you're here somewhere...");
        vesna.transition_to("Investigate", [points(8)]).

@recover_default[temper([fear(0.0)])]
+!investigate_area
    <-  .print("Scanning area.");
        vesna.transition_to("Investigate", [points(3)]).

// Investigation Complete (Reset State)
@investigation_done[effects([fear(-0.05)])]
+signal_investigation(complete, Reason)
    <-  .print("Area secure.");
        -signal_investigation(complete, Reason);
        -is_chasing(_); +is_chasing(no);
        -responding_to_alert(_); +responding_to_alert(no);
        -last_player_pos(_, _);
        -consecutive_failures(_); +consecutive_failures(0);
        -messenger_sent(_); +messenger_sent(no);
        .abolish(sight(player, _, _));
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// MESSENGER SYSTEM (Coordination)
// =============================================================================

// 1. RECRUITING (We are chasing, see an ally)
+allies_nearby(AllyList) : is_chasing(yes) & last_player_pos(X, Y) & not .empty(AllyList) & messenger_sent(no)
    <-  .nth(0, AllyList, FirstAlly);
        .print("Recruiting ", FirstAlly, " as messenger.");
        .send(FirstAlly, achieve, become_messenger(pos(X, Y)));
        -messenger_sent(no); +messenger_sent(yes);
        -allies_nearby(AllyList).

// 2. BECOMING MESSENGER
// TBD: If Corrupt/Lazy, we might reject the duty
//      If Scared, we might accept eagerly.

@messenger_accept[temper([fear(0.0)])]
+!become_messenger(pos(X, Y))[source(Sender)] : is_chasing(no) & is_messenger(no)
    <-  .print("Messenger duty accepted. Finding Captain.");
        -messenger_report_pos(_); +messenger_report_pos(pos(X, Y));
        -is_messenger(no); +is_messenger(yes);
        .drop_intention(patrol);
        vesna.transition_to("Patrol", [target("find_captain")]).

// Rejection cases
+!become_messenger(_)[source(Sender)] : is_chasing(yes)
    <- .send(Sender, tell, messenger_rejected(busy)).
+!become_messenger(_)[source(Sender)] : is_messenger(yes)
    <- .send(Sender, tell, messenger_rejected(already_messenger)).

// 3. DELIVERING MESSAGE
+navigation(reached_agent, Captain) : is_messenger(yes) & messenger_report_pos(pos(X, Y))
    <-  .print("Reporting to ", Captain);
        -navigation(reached_agent, Captain);
        .send(Captain, tell, player_spotted_at(X, Y));
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// INCOMING ALERTS
// =============================================================================

@alert_respond_corrupt[temper([sympathy(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". I'll get there... eventually.");
        .wait(3000); // Drag feet
        !respond_to_alert(X, Y).

@alert_respond_default[temper([fear(0.0)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, "! Intercepting.");
        !respond_to_alert(X, Y).

+!respond_to_alert(X, Y)
    <-  .drop_all_intentions;
        +last_player_pos(X, Y);
        -responding_to_alert(no); +responding_to_alert(yes);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// Clean up
+player_spotted_at(X, Y) <- -player_spotted_at(X, Y).
+allies_nearby(L) <- -allies_nearby(L).
+navigation(reached_target, _) : is_chasing(no) 
    <- -navigation(reached_target, _); vesna.transition_to("Investigate", [points(2)]).