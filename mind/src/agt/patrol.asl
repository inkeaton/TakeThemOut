// patrol.asl

/* --- Goals --- */
!patrol. // Start the loop
state(patrolling).  // patrolling | chasing | searching

/* --- Patrol Loop --- */

+!patrol
    :   state(patrolling)
    <-  !decide_next_step; // Make a choice based on personality
        // The choice (sub-goal) will trigger the actual movement
        // logic below, and then we wait for arrival.
        .print("Step decision made.").

// CHOICE A: Standard Patrol
@go_next[temper([aggressiveness(0.1)])]
+!decide_next_step
    <-  .print("Patrolling forward...");
        vesna.patrol(next). // Passing the atom 'next'

// CHOICE B: Aggressive Checks
@go_prev_low[temper([aggressiveness(0.3)])]
+!decide_next_step
    :   math.random(R) & R < 0.1 
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.patrol(prev).

@go_prev_mid[temper([aggressiveness(0.5)])]
+!decide_next_step
    :   math.random(R) & R < 0.3 
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.patrol(prev).

@go_prev_high[temper([aggressiveness(0.9)])]
+!decide_next_step
    :   math.random(R) & R < 0.5 
    <-  .print("Backtracking! (Aggressive Check)");
        vesna.patrol(prev).

// TRIGGER: navigation(reached, Waypoint)
// This matches the belief created by handleNavigation in Java
+navigation(reached, Waypoint)
    :   state(patrolling)
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

/* --- Player detection & Response --- */

// 1. High Aggressiveness: Relentless pursuit (Track 15 crumbs)
@chase_aggressive[temper([aggressiveness(0.8)])]
+sight(player, Id, pos(X, Y))
    :   state(patrolling)
    <-  .print("PLAYER DETECTED! HUNT THEM DOWN!");
        -state(patrolling);
        +state(chasing);
        +last_player_pos(X, Y);
        vesna.chase(15). // <--- Passing High Patience

// 2. Low Aggressiveness: Weak pursuit (Track only 4 crumbs)
@chase_lazy[temper([aggressiveness(0.2)])]
+sight(player, Id, pos(X, Y))
    :   state(patrolling)
    <-  .print("Player detected. I'll take a look, I guess...");
        -state(patrolling);
        +state(chasing);
        +last_player_pos(X, Y);
        vesna.chase(4).  // <--- Passing Low Patience

// 3. Default Fallback (Track 8 crumbs)
@chase_default
+sight(player, Id, pos(X, Y))
    :   state(patrolling)
    <-  .print("Player detected! Engaging.");
        -state(patrolling);
        +state(chasing);
        +last_player_pos(X, Y);
        vesna.chase(8).

/* --- Target Lost Recovery --- */

// Aggressive/Diligent Agent: Investigates thoroughly (5 points)
@recover_diligent[temper([laziness(0.2)])]
+target_lost(pos(X,Y), Reason)
    <-  .print("Target lost. I will comb the area!");
        -state(chasing);
        +state(investigating);
        -target_lost(pos(X,Y), Reason);
        
        vesna.investigate(5). // <--- Action

// Lazy Agent: Minimal check (2 points)
@recover_lazy[temper([laziness(0.8)])]
+target_lost(pos(X,Y), Reason)
    <-  .print("Target lost. I'll verify quickly.");
        -state(chasing);
        +state(investigating);
        -target_lost(pos(X,Y), Reason);
        
        vesna.investigate(2). // <--- Action

// Completion Handler
// Triggered when Godot sends {"type": "investigation", "status": "complete", ...}
+investigation(complete, Reason)
    :   state(investigating)
    <-  .print("Investigation finished (", Reason, "). Nothing found.");
        -state(investigating);
        +state(patrolling);
        
        vesna.patrol(resume);
        !patrol.