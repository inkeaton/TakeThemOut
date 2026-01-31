// captain.asl

/* --- Initial Goals --- */
!patrol. // Start the loop
state(patrolling).
sightings([]). // Initialize memory for incoming reports

/* --- The Captain's Loop --- */

// 1. Decision Trigger
+!patrol
    :   state(patrolling)
    <-  !decide_next_step.

// 2. The Decision Logic
// Instead of just picking random/next, we ask the squad first.
+!decide_next_step
    <-  .print("Reaching checkpoint. Gathering intel from squad...");
        
        // A. Reset memory
        -sightings(_);
        +sightings([]);
        
        // B. Ask everyone
        .broadcast(achieve, report_sightings);
        
        // C. Wait for replies (2 seconds)
        .wait(2000);
        
        // D. Analyze results
        !analyze_intel.

/* --- Intel Analysis --- */

// Case A: We have sightings!
+!analyze_intel
    :   sightings(List) & not .empty(List)
    <-  .print("Intel received: ", List);
        
        // 1. Calculate the interception point (Centroid)
        vesna.calc_centroid(List, AvgX, AvgY);
        .print("Calculated intercept vector: ", AvgX, ",", AvgY);
        
        // 2. Move to that location
        vesna.move_to(AvgX, AvgY).
        // Note: When we arrive, the 'TravelState' will trigger 'Investigate'
        // automatically, just like with the Patrol agent.

// Case B: No sightings (List is empty)
+!analyze_intel
    <-  .print("No intel received. Choosing random sector.");
        
        // Command the body to pick a random known waypoint
        vesna.patrol(random).

/* --- Handling Replies --- */

// When a squad member reports a position
+sighting_report(pos(X,Y))[source(Sender)]
    :   sightings(List)
    <-  .print("Received report from ", Sender, ": ", pos(X,Y));
        -sightings(List);
        // Add to our list using list concatenation
        +sightings([pos(X,Y)|List]).

// When a squad member reports nothing (ignore it)
+sighting_report(none).

/* --- Movement & Arrival --- */

// Standard Arrival (Waypoint)
+navigation(reached, Waypoint)
    :   state(patrolling)
    <-  .print("Arrived at standard waypoint ", Waypoint);
        -navigation(reached, Waypoint);
        !patrol. // Restart loop

// Intel Arrival (Calculated Point)
// Logic reused from Patrol's alert response:
// Arrive -> TravelState switches to Investigate -> Investigate finishes -> Resume Patrol
+navigation(reached_target, Coords)
    :   state(patrolling)
    <-  .print("Arrived at intercept point. Checking area.");
        -navigation(reached_target, Coords);
        // We explicitly trigger an investigation here
        // (If your TravelState doesn't do it automatically)
        vesna.investigate(5). 

// Finished Investigating
+investigation(complete, Reason)
    <-  .print("Area clear. Resuming patrol.");
        !patrol.

/* --- Alert Logic (Captain sees player) --- */

+sight(player, Id, pos(X, Y))
    :   state(patrolling)
    <-  .print("CONTACT! Taking command!");
        
        // 1. Alert the Squad (Just like Sentry)
        .broadcast(tell, player_spotted_at(X, Y));
        
        // 2. Switch to Chase (Just like Patrol)
        -state(patrolling);
        +state(chasing);
        vesna.chase(20). // Captains are very persistent!

/* --- Fallback for lost target --- */
+target_lost(pos(X,Y), Reason)
    <-  .print("Lost contact. Re-evaluating.");
        -state(chasing);
        +state(patrolling);
        !patrol.