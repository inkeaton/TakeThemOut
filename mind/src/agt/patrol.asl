// patrol.asl

/* --- Goals --- */
!patrol. // Start the loop

/* --- Patrol Loop --- */

+!patrol
    <-  !decide_next_step; // Make a choice based on personality
        // The choice (sub-goal) will trigger the actual movement
        // logic below, and then we wait for arrival.
        .print("Step decision made.").

// CHOICE A: Standard Patrol
@go_next[temper([aggressiveness(0.1)])]
+!decide_next_step
    <-  .print("Patrolling forward...");
        vesna.continue_patrol(next). // Passing the atom 'next'

// CHOICE B: Aggressive Checks
@go_prev_low[temper([aggressiveness(0.3)])]
+!decide_next_step
    :   math.random(R) & R < 0.1 
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.continue_patrol(prev).

@go_prev_mid[temper([aggressiveness(0.5)])]
+!decide_next_step
    :   math.random(R) & R < 0.3 
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.continue_patrol(prev).

@go_prev_high[temper([aggressiveness(0.9)])]
+!decide_next_step
    :   math.random(R) & R < 0.5 
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.continue_patrol(prev).

// TRIGGER: navigation(reached, Waypoint)
// This matches the belief created by handleNavigation in Java
+navigation(reached, Waypoint)
    <-  .print("Arrived at ", Waypoint);
        
        -navigation(reached, Waypoint);
        !rest_at_waypoint;
        !patrol.

/* --- Plan Selection (The Personality) --- */

// Option A: The "Lazy" Plan
// Selected if agent's temper is close to laziness(0.8)
@lazy_rest[temper([laziness(0.8)])]
+!rest_at_waypoint
    <-  .print("Ugh, my feet hurt. Taking a long break...");
        .wait(5000).

// Option B: The "Diligent" Plan
// Selected if agent's temper is close to laziness(0.2)
@active_rest[temper([laziness(0.2)])]
+!rest_at_waypoint
    <-  .print("Sector clear. Moving on immediately.");
        .wait(1000).

// Option C: Fallback
// Selected if no specific temper matches or strategy is random
@default_rest
+!rest_at_waypoint
    <-  .print("Just a standard pause.");
        .wait(2000).

/* --- Failure Handling --- */
+signal(navigation, failed, Reason)
    <-  .print("Navigation error: ", Reason);
        .wait(2000);
        !patrol.