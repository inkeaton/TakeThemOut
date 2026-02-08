// ready_agent.asl

!start.

+!start : true 
   <- .wait(1000); // Wait for 1 second to ensure everything is initialized
      .print("MIND IS READY - Sending signal to Godot...");
      vesna.signal_ready.

// Handle the setup signal from Godot
// Belief format: sympathy_updates([[agent_name, value], [agent_name, value]])
+sympathy_updates(List)
    <- .print("Received sympathy updates: ", List);
       !distribute_updates(List).

+!distribute_updates([]).
+!distribute_updates([ [Agent, Value] | Rest ])
    <- .print("Updating ", Agent, " with sympathy ", Value);
       .send(Agent, achieve, update_sympathy(Value));
       !distribute_updates(Rest).

// Ignore Captain's requests for intel (we have no body/eyes)
+!report_sightings[source(_)].