// ready_agent.asl
!start.

/* When this agent starts, it means the Jason infrastructure is up.
   It sends a signal_ready message to Godot via the WebSocket connection
   on port 9200 (handled by ServerManager). Godot reads the JSON message
   and emits jason_service_ready to unblock the maze.
*/
+!start : true 
   <- .print("MIND IS READY - Sending signal to Godot...");
      vesna.signal_ready;
      .print("Signal sent successfully.").