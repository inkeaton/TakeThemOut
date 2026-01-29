// patrol.asl - Temper-based Patrol Agent

{ include("vesna.asl") }

// --- Initial Beliefs ---
// Define your waypoints here. These names must match Node names in Godot.
// need to add beliefs for waypoints at startup
state(patrolling).

/* ========================================================================= */
/* BEHAVIOR 1: PATROLLING                        */
/* ========================================================================= */

// Start patrolling when we have waypoints
+!start_patrol
    :   waypoints(WPs)
    <-  .print("Starting patrol!");
        // Wait for WebSocket connection to be ready
        .wait(1000);
        // Clean any stale movement beliefs from previous cycles
        .abolish(signal_movement(_, _));
        !patrol(WPs).

// Loop through waypoints
+!patrol([])
    :   waypoints(WPs)
    <-  !patrol(WPs).

+!patrol([NextWP | Rest])
    :   state(patrolling)
    <-  .print("Moving to waypoint: ", NextWP);
        vesna.walk(NextWP);
        // Wait for arrival signal from Body
        .wait({+signal_movement(completed, _)});
        !rest_at_waypoint;
        !patrol(Rest).

// Handle interruption (e.g., if we started chasing mid-patrol)
+!patrol(_)
    :   not state(patrolling)
    <-  .print("Patrol paused for emergency.").

// --- Temper-based Resting ---

// Lazy Guard: Takes a long break
@lazy_rest[temper([laziness(0.8)])]
+!rest_at_waypoint
    <-  .print("Ugh, my feet hurt. Taking a break...");
        .wait(5000).

// Diligent Guard: Short pause
@active_rest[temper([laziness(0.2)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving on.");
        .wait(1000).

// Default fallback
@default_rest
+!rest_at_waypoint
    <-  .wait(2000).

/* ========================================================================= */
/* BEHAVIOR 2: CHASING                           */
/* ========================================================================= */

// Trigger: Visual Contact
+sight(player, Id)
    :   not state(chasing)
    <-  .print("CONTACT! Engaging target ", Id);
        // 1. Change State
        -state(patrolling);
        +state(chasing);
        .drop_all_desires; // Stop patrolling immediately
        
        // 2. Command Body
        vesna.chase(Id).

// Trigger: Lost Visuals (LKP Logic)
+signal_sight(lost, _)
    :   state(chasing)
    <-  .print("Visual lost! Moving to Last Known Position...");
        // Body automatically moves to LKP. We just wait for arrival.
        !wait_for_lkp.

+!wait_for_lkp
    <-  .wait({+signal_movement(completed, lkp_reached)}, 10000, _); 
        // If we timeout (10s), force search
        -state(chasing);
        +state(searching);
        // Clean up sight beliefs to allow re-detection
        .abolish(sight(player, _));
        !search_area.

// Trigger: Arrived at LKP
+signal_movement(completed, lkp_reached)
    :   state(chasing)
    <-  .print("Arrived at LKP. Target gone.");
        -state(chasing);
        +state(searching);
        // Clean up sight beliefs to allow re-detection
        .abolish(sight(player, _));
        !search_area.

/* ========================================================================= */
/* BEHAVIOR 3: SEARCHING                         */
/* ========================================================================= */

// Aggressive Guard: Searches thoroughly
@angry_search[temper([aggressiveness(0.8)])]
+!search_area
    <-  .print("COME OUT! I KNOW YOU'RE HERE!");
        !check_random_spots(3). // Check 3 spots

// Calm Guard: Gives up easily
@calm_search[temper([aggressiveness(-0.5)])]
+!search_area
    <-  .print("Must have been rats.");
        !check_random_spots(1). // Check 1 spot

// Search Loop
+!check_random_spots(0)
    <-  .print("Search complete. Returning to patrol.");
        // Clean up all state beliefs to ensure clean transition
        .abolish(state(_));
        +state(patrolling);
        !start_patrol.

+!check_random_spots(N)
    <-  // Pick a random point relative to current position (simplified)
        .print("Checking spot ", N);
        // In a real implementation, you'd calculate coordinates. 
        // For now, we wait to simulate searching.
        .wait(2000);
        !check_random_spots(N-1).

/* ========================================================================= */
/* BEHAVIOR 4: COORDINATION                      */
/* ========================================================================= */

// If I see an Ally while chasing
+sight(Ally, _)
    :   state(chasing) & not negotiating(_) & .substring("patrol", Ally)
    <-  +negotiating(Ally);
        .send(Ally, askOne, dist_to_base(_), Reply);
        !resolve_chase(Reply).

+!resolve_chase(dist_to_base(AllyDist))
    :   my_dist(MyDist)
    <-  if (MyDist < AllyDist) {
            .print("I'm closer to base. I'll alert them!");
            -state(chasing);
            !alert_base;
        } else {
            .print("You go alert base! I'm staying on target!");
        }.