// captain.asl - Captain Agent with Full Temper System

!start_patrol.

// =============================================================================
// KNOWLEDGE & STATE MANAGEMENT
// =============================================================================

consecutive_failures(0).
is_chasing(no).
responding_to_alert(no).

// Supersede patterns
+is_chasing(S) : is_chasing(Old) & Old \== S <- -is_chasing(Old).
+responding_to_alert(S) : responding_to_alert(Old) & Old \== S <- -responding_to_alert(Old).
+last_player_pos(X, Y) : last_player_pos(OldX, OldY) & (OldX \== X | OldY \== Y) <- -last_player_pos(OldX, OldY).
+last_alert_pos(X, Y) : last_alert_pos(OldX, OldY) & (OldX \== X | OldY \== Y) <- -last_alert_pos(OldX, OldY).
+consecutive_failures(N) : consecutive_failures(Old) & Old \== N <- -consecutive_failures(Old).

// =============================================================================
// PATROL & INTEL GATHERING LOOP
// =============================================================================

+!start_patrol <- .print("Captain on deck."); vesna.transition_to("Patrol", [target("next")]).

+!patrol <- !gather_intel.

// 1. Gather Intel (Ask Squad)
+!gather_intel
    <-  .print("Checkpoint reached. Requesting sitrep.");
        .broadcast(achieve, report_sightings);
        .wait(2000);
        !analyze_intel.

// 2. Analyze Intel (Decision Logic)

/* SABOTEUR: Ignores reports to help player.
   "Looks clear to me." -> Patrols Randomly.
*/
@analyze_saboteur[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)], Reports);
        .abolish(sighting_report(_));
        .print("Intel ignored. (Sabotage)");
        vesna.transition_to("Patrol", [target("random")]).

/* ARMCHAIR GENERAL: Too scared/lazy to coordinate complex maneuvers.
   Just goes to next waypoint.
*/
@analyze_lazy[temper([laziness(0.8), fear(0.6)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)], Reports);
        .abolish(sighting_report(_));
        .print("Too much noise. Maintaining course.");
        vesna.transition_to("Patrol", [target("next")]).

/* TACTICIAN/WARLORD: Processes intel properly. */
@analyze_default[temper([fear(0.0)]), effects([fear(-0.05)])]
+!analyze_intel
    <-  .findall(Pos, sighting_report(Pos)[source(_)], Reports);
        .abolish(sighting_report(_));
        .print("Analyzing intel: ", Reports);
        !act_on_intel(Reports).

// 3. Act on Intel (Intercept Logic)

// No Reports -> Patrol Randomly (Aggro) or Next (Default)
@no_intel_aggro[temper([aggressiveness(0.8)])]
+!act_on_intel([]) <- .print("No targets. Hunting randomly."); vesna.transition_to("Patrol", [target("random")]).

@no_intel_default[temper([fear(0.0)])]
+!act_on_intel([]) <- .print("Sector clear. Proceeding."); vesna.transition_to("Patrol", [target("next")]).

// Reports Exist -> Intercept

/* WARLORD: Precision Intercept */
@intercept_warlord[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("INTERCEPT COURSE SET: ", AvgX, ",", AvgY);
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

/* CAUTIOUS: Hesitate */
@intercept_cautious[temper([fear(0.8)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("Multiple contacts... Proceeding with caution.");
        .wait(1500);
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

/* DEFAULT */
@intercept_default[temper([fear(0.0)])]
+!act_on_intel(Reports) : not .empty(Reports)
    <-  vesna.calc_centroid(Reports, AvgX, AvgY);
        .print("Converging on target.");
        vesna.transition_to("Patrol", [target(coords(AvgX, AvgY))]).

// =============================================================================
// HANDLING SIGHTING REPORTS (Input from Squad)
// =============================================================================

+sighting_report(pos(X, Y))[source(Sender)]
    <- .print("Received report from ", Sender).
+sighting_report(none)[source(_)].

// =============================================================================
// NAVIGATION & ARRIVAL
// =============================================================================

// Reaching patrol waypoint -> Loop
@nav_waypoint[effects([fear(-0.02)])]
+navigation(reached, W) : is_chasing(no) & responding_to_alert(no)
    <-  .print("Arrived at ", W);
        -navigation(reached, W);
        !patrol.

// Reaching Intercept Point -> Investigate
@nav_intercept[effects([fear(-0.05)])]
+navigation(reached_target, C) : is_chasing(no)
    <-  .print("Intercept complete. Investigating.");
        -navigation(reached_target, C);
        -responding_to_alert(_); +responding_to_alert(no);
        vesna.transition_to("Investigate", [points(5)]).

// Clean up stray nav messages
+navigation(Status, _) : is_chasing(yes) <- -navigation(Status, _).

// =============================================================================
// PLAYER DETECTION (Direct Combat)
// =============================================================================

@chase_saboteur[temper([sympathy(0.8)]), effects([sympathy(0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Oh, it's you. Run away. (Saboteur)");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        // Does NOT broadcast location
        vesna.transition_to("Chase", [patience(5)]).

@chase_warlord[temper([aggressiveness(0.8)]), effects([fear(-0.05)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("TARGET ACQUIRED! ALL UNITS CONVERGE!");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y)); // Lead the charge
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(25)]).

@chase_default[temper([fear(0.0)])]
+sight(player, Id, pos(X, Y)) : is_chasing(no)
    <-  .print("Contact! Taking command.");
        -is_chasing(no); +is_chasing(yes);
        -responding_to_alert(_); +responding_to_alert(no);
        .broadcast(tell, player_spotted_at(X, Y));
        .drop_intention(patrol);
        +last_player_pos(X, Y);
        vesna.transition_to("Chase", [patience(15)]).

// Tracking updates
+sight(player, Id, pos(X, Y)) : is_chasing(yes)
    <-  -last_player_pos(_, _); +last_player_pos(X, Y).

// =============================================================================
// INCOMING ALERTS (From Squad)
// =============================================================================

/* SABOTEUR: Breaks the chain of command.
   Does NOT re-broadcast. Does NOT intercept effectively.
*/
@alert_saboteur[temper([sympathy(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". Disregarding. (Sabotage)");
        -player_spotted_at(X, Y)[source(Sender)];
        // Fake response - just patrol to random point
        vesna.transition_to("Patrol", [target("random")]).

/* ARMCHAIR GENERAL: Broadcasts but stays put (or moves slowly).
*/
@alert_lazy[temper([laziness(0.8)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". Squad, handle it.");
        -player_spotted_at(X, Y)[source(Sender)];
        .broadcast(tell, player_spotted_at(X, Y)); // Delegate
        // Minimal effort response
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

/* DEFAULT/WARLORD: Relays and Intercepts. */
@alert_default[temper([fear(0.0)])]
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(no)
    <-  .print("Alert from ", Sender, ". Redirecting squad.");
        -player_spotted_at(X, Y)[source(Sender)];
        
        // CHECK: Only broadcast if sender is NOT another captain
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

// Already busy
+player_spotted_at(X, Y)[source(Sender)] : is_chasing(yes) | responding_to_alert(yes)
    <-  .print("Update from ", Sender);
        -player_spotted_at(X, Y)[source(Sender)];
        
        // CHECK: Only broadcast if sender is NOT another captain
        .term2string(Sender, SenderStr);
        if (not .substring("captain", SenderStr)) {
            .broadcast(tell, player_spotted_at(X, Y)); 
        }
        
        +last_alert_pos(X, Y);
        vesna.transition_to("Patrol", [target(coords(X, Y))]).

// =============================================================================
// RECOVERY & FAILURE
// =============================================================================

@target_lost_trigger[effects([fear(0.1)])]
+target_lost(pos(X, Y), Reason) : consecutive_failures(N)
    <-  .print("Target lost. Frustration rising.");
        -target_lost(pos(X, Y), Reason);
        -consecutive_failures(N); +consecutive_failures(N+1);
        !investigate_area.

@recover_frustrated[temper([fear(0.6)])]
+!investigate_area : consecutive_failures(N) & N > 2
    <-  .print("They are gone. I'm not wasting time.");
        vesna.transition_to("Investigate", [points(2)]).

@recover_default[temper([fear(0.0)])]
+!investigate_area
    <-  vesna.transition_to("Investigate", [points(5)]).

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

// Fallback failures
-!gather_intel <- .print("Intel failed."); vesna.transition_to("Patrol", [target("random")]).
-!analyze_intel <- .print("Analysis failed."); vesna.transition_to("Patrol", [target("random")]).

// Ignore Captain's requests for intel (If we knew, we'd tell)
+!report_sightings[source(_)].