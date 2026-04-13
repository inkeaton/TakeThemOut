// ready_agent.asl

!start.

// =============================================================================
// BOOTSTRAP
// =============================================================================

/* STARTUP: Waits briefly, then signals Godot that the mind is ready. */
+!start : true 
   <- .wait(1000); // Wait for 1 second to ensure everything is initialized
      .print("MIND IS READY - Sending signal to Godot...");
      vesna.signal_ready.

// =============================================================================
// SQUAD COMMUNICATION & SETUP
// =============================================================================

/* SETUP INPUT: Receives batch sympathy updates and starts distribution. */
+sympathy_updates(List)
    <- .print("Received sympathy updates: ", List);
       !distribute_updates(List).

/* DISTRIBUTE BASE: Stops recursion when update list is exhausted. */
+!distribute_updates([]).

/* DISTRIBUTE STEP: Sends one update, then continues with remaining agents. */
+!distribute_updates([ [Agent, Value] | Rest ])
    <- .print("Updating ", Agent, " with sympathy ", Value);
       .send(Agent, achieve, update_sympathy(Value));
       !distribute_updates(Rest).

/* REPORT IGNORE: Discards captain intel requests for the director role. */
+!report_sightings[source(_)].