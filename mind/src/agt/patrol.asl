// patrol.asl - Patrol agent with Full Temper System

!start_patrol.

// =============================================================================
// KNOWLEDGE & STATE MANAGEMENT
// =============================================================================

// Initial beliefs - track agent state across behaviors
consecutive_failures(0).      // How many times target was lost in a row
is_chasing(no).               // Currently in chase/track mode
responding_to_alert(no).      // Currently moving toward an alert location
is_messenger(no).             // Currently acting as messenger to captain
messenger_target(none).       // Which captain to report to
messenger_report_pos(none).   // Player position to report
messenger_sent(no).           // Whether a messenger was already dispatched this chase

// Supersede patterns (State Management)
// Automatically retract old values when a belief is updated
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

@step_paranoid[temper([aggressiveness(0.8), fear(0.4)])]
+!decide_next_step : .random(R) & R < 0.3
    <-  .print("Checking my six! (Aggressive Check)");
        vesna.transition_to("Patrol", [target("prev")]).

/* DEFAULT:
   Represents "Average" personality.
   An aggressive agent (0.8) is closer to 'step_paranoid' (Dist 0.0) than 'step_default' (Dist 0.3).
*/
@step_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0)])]
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

/* REST LOGIC */

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

// DEFAULT: Added sympathy(0.0) so it loses to Corrupt(0.8) for sympathetic agents
@rest_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!rest_at_waypoint
    <-  .wait(2000).

// =============================================================================
// INTEL REPORTING (Responding to Captain)
// =============================================================================

@report_corrupt[temper([sympathy(0.8)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Lying to Captain (Corrupt)");
        .send(Captain, tell, sighting_report(none));
        -last_player_pos(X, Y).

// DEFAULT: Added sympathy(0.0)
@report_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!report_sightings[source(Captain)] : last_player_pos(X, Y)
    <-  .print("Reporting sighting to ", Captain);
        .send(Captain, tell, sighting_report(pos(X, Y)));
        -last_player_pos(X, Y).

/* No intel to report - Context specific, no temper needed */
@report_none
+!report_sightings[source(Captain)] : not last_player_pos(_, _)
    <-  .send(Captain, tell, sighting_report(none)).

// =============================================================================
// CHASE BEHAVIOR
// =============================================================================

// First sighting: switch to chase mode, drop patrol intentions
@chase_trigger[effects([fear(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("CONTACT!");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        !start_chase.

// Already chasing: just update the player's last known position
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  -last_player_pos(_, _); +last_player_pos(X, Y).

/* CHASE LOGIC
   Patience determines how many navigation cycles before giving up.
   - Corrupt: barely tries (patience 2), gains sympathy for letting player go
   - Relentless: hostile & aggressive, won't stop (patience 25)
   - Lazy: minimal effort (patience 5)
   - Default: standard pursuit (patience 10)
*/

/* 1. THE CORRUPT (High Sympathy)
   Feigns effort, gives up almost immediately.
   Effect: becomes even more sympathetic over time.
*/
@chase_corrupt[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!start_chase
    <-  .print("Oh no, he's fast... (Feigning effort)");
        vesna.transition_to("Chase", [patience(2)]).

/* 2. THE RELENTLESS (Low Sympathy + High Aggression)
   Maximum persistence - never stops hunting.
*/
@chase_relentless[temper([sympathy(-0.8), aggressiveness(0.8)]), effects([fear(-0.05)])]
+!start_chase
    <-  .print("YOU CAN'T HIDE!");
        vesna.transition_to("Chase", [patience(25)]).

/* 3. THE LAZY
   Does the bare minimum.
*/
@chase_lazy[temper([laziness(0.8)])]
+!start_chase
    <-  .print("I'll check, but I'm not running.");
        vesna.transition_to("Chase", [patience(5)]).

// DEFAULT: Added sympathy(0.0)
@chase_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!start_chase
    <-  .print("Engaging target.");
        vesna.transition_to("Chase", [patience(10)]).

// =============================================================================
// RECOVERY (Target Lost -> Investigate)
// =============================================================================

// When the Godot body loses sight of the player, it sends target_lost.
// The agent increments failure count and investigates the area.
@target_lost_trigger[effects([fear(0.05)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost at ", X, ",", Y);
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N); +consecutive_failures(N+1);
        !investigate_area.

/* INVESTIGATE LOGIC
   'points' = number of random investigation spots to check.
   - Corrupt: barely looks (1 point)
   - Lazy: minimal effort (1 point)
   - Vengeful: thorough search (8 points)
   - Default: standard sweep (3 points)
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

// DEFAULT: Added sympathy(0.0)
@recover_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+!investigate_area
    <-  .print("Scanning area.");
        vesna.transition_to("Investigate", [points(3)]).

// Investigation complete: full state reset and return to normal patrol.
// Clears all chase-related beliefs and resets messenger_sent so a new
// messenger can be dispatched next chase.
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
// MESSENGER SYSTEM
// =============================================================================

// RECRUITMENT: A chasing patrol with nearby allies recruits one as a messenger
// to report the player's position to the nearest captain.
// Only recruits once per chase (messenger_sent flag).
+allies_nearby(AllyList) : is_chasing(yes) & last_player_pos(X, Y) & not .empty(AllyList) & messenger_sent(no)
    <-  .nth(0, AllyList, FirstAlly);
        .print("Recruiting ", FirstAlly, " as messenger.");
        .send(FirstAlly, achieve, become_messenger(pos(X, Y)));
        -messenger_sent(no); +messenger_sent(yes);
        -allies_nearby(AllyList).

// ACCEPTANCE: Ally accepts messenger duty if idle (not chasing, not already a messenger).
// Drops patrol intentions and navigates to nearest captain via Godot's find_captain.
@messenger_accept[temper([fear(0.0)])]
+!become_messenger(pos(X, Y))[source(Sender)] : is_chasing(no) & is_messenger(no)
    <-  .print("Messenger duty accepted. Finding Captain.");
        -messenger_report_pos(_); +messenger_report_pos(pos(X, Y));
        -is_messenger(no); +is_messenger(yes);
        .drop_intention(patrol);
        vesna.transition_to("Patrol", [target("find_captain")]).

// REJECTION: Can't accept if busy chasing or already a messenger
+!become_messenger(_)[source(Sender)] : is_chasing(yes)
    <- .send(Sender, tell, messenger_rejected(busy)).
+!become_messenger(_)[source(Sender)] : is_messenger(yes)
    <- .send(Sender, tell, messenger_rejected(already_messenger)).

// SUCCESS: Reached the captain - deliver intel, reset messenger state on both
// Jason side (beliefs) and Godot side (body.is_messenger via set_var), then resume patrol.
+navigation(reached_agent, Captain) : is_messenger(yes) & messenger_report_pos(pos(X, Y))
    <-  .print("Reporting to ", Captain);
        -navigation(reached_agent, Captain);
        .send(Captain, tell, player_spotted_at(X, Y));
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        vesna.set_var(is_messenger, false);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// FALLBACK: No captain found in scene (none in "captains" group or all too far).
// Abort messenger duty and resume normal patrol.
+navigation(no_captain_found, _) : is_messenger(yes)
    <-  .print("No captain found. Aborting messenger duty.");
        -navigation(no_captain_found, _);
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        vesna.set_var(is_messenger, false);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// FALLBACK: Captain node was destroyed or became invalid during navigation.
+navigation(agent_lost, _) : is_messenger(yes)
    <-  .print("Lost captain during navigation. Aborting messenger duty.");
        -navigation(agent_lost, _);
        -is_messenger(yes); +is_messenger(no);
        -messenger_report_pos(_); +messenger_report_pos(none);
        vesna.set_var(is_messenger, false);
        vesna.transition_to("Patrol", [target("resume")]);
        !patrol.

// =============================================================================
// INCOMING ALERTS
// =============================================================================

/* Alert response varies by personality:
   - Corrupt: delays 3 seconds before responding (drags feet)
   - Default: responds immediately
*/
@alert_respond_corrupt[temper([sympathy(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". I'll get there... eventually.");
        .wait(3000); // Drag feet
        !respond_to_alert(X, Y).

// DEFAULT: Added sympathy(0.0)
@alert_respond_default[temper([aggressiveness(0.5), laziness(0.5), fear(0.0), sympathy(0.0)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, "! Intercepting.");
        !respond_to_alert(X, Y).

// Shared alert response: drop everything and navigate to reported position
+!respond_to_alert(X, Y)
    <-  .drop_all_intentions;
        +last_player_pos(X, Y);
        -responding_to_alert(no); +responding_to_alert(yes);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// Cleanup rules: discard stale alerts and ally reports
+player_spotted_at(X, Y) <- -player_spotted_at(X, Y).
+allies_nearby(L) <- -allies_nearby(L).
// Arrived at alert location: investigate the area
+navigation(reached_target, _) : is_chasing(no) 
    <- -navigation(reached_target, _); vesna.transition_to("Investigate", [points(2)]).

// =============================================================================
// SETUP & CONFIGURATION
// =============================================================================

// Received from the director agent after Rasa skirmish dialogue.
// Adjusts the patrol's sympathy mood, which influences plan selection
// (e.g., corrupt vs default behavior).
+!update_sympathy(Value)[source(Sender)]
    <-  .print("Received sympathy update: ", Value, " from ", Sender);
        vesna.add_temper(sympathy, Value).