// sentry.asl - Sentry agent with player detection and ally alerting
// This agent reacts to visual input and coordinates with other allies

// --- Initial Beliefs ---
state(scanning).  // scanning | alerting

// --- Perception Handlers ---

// When we see the player (body sends sight with position)
+sight(player, Id, pos(X, Y))
    :   state(scanning)
    <-  .print("PLAYER DETECTED at position (", X, ", ", Y, ")!");
        -state(scanning);
        +state(alerting);
        +last_player_pos(X, Y);
        // Tell body to trigger alert sequence
        vesna.alert(X, Y).

// When we see the player but no position data (fallback)
+sight(player, Id)
    :   state(scanning)
    <-  .print("PLAYER DETECTED (no position data)!");
        -state(scanning);
        +state(alerting);
        // Tell body to trigger alert sequence
        vesna.alert.

// --- Allies Found Handler ---

// Body completed scan and found allies nearby
+allies_nearby(AllyList)
    :   state(alerting) & last_player_pos(X, Y)
    <-  .print("Allies found: ", AllyList);
        !broadcast_alert(AllyList, X, Y).

// Body completed scan but no position recorded
+allies_nearby(AllyList)
    :   state(alerting)
    <-  .print("Allies found: ", AllyList);
        !broadcast_alert_no_pos(AllyList).

// --- Broadcasting Plans ---

// Broadcast alert to all allies with position
+!broadcast_alert([], _, _)
    <-  .print("Broadcast complete.").

+!broadcast_alert([Ally | Rest], X, Y)
    <-  .print("Sending alert to ", Ally);
        .send(Ally, tell, player_alert(X, Y));
        !broadcast_alert(Rest, X, Y).

// Broadcast alert without position
+!broadcast_alert_no_pos([])
    <-  .print("Broadcast complete.").

+!broadcast_alert_no_pos([Ally | Rest])
    <-  .print("Sending alert to ", Ally);
        .send(Ally, tell, player_alert);
        !broadcast_alert_no_pos(Rest).

// --- Receiving Alerts ---

// When another sentry alerts us (with position)
+player_alert(X, Y)[source(Sender)]
    <-  .print("ALERT received from ", Sender, "! Player reported at (", X, ", ", Y, ")");
        +aware_of_player(X, Y, Sender).

// When another sentry alerts us (without position)
+player_alert[source(Sender)]
    <-  .print("ALERT received from ", Sender, "! Player reported nearby");
        +aware_of_player_nearby(Sender).

// --- Signal Handlers ---

// Body finished alert sequence (arrives as belief via sense() mechanism)
+signal_alert(completed, _)
    :   state(alerting)
    <-  .print("Alert sequence completed. Returning to scan.");
        -state(alerting);
        +state(scanning);
        -last_player_pos(_, _);
        -allies_nearby(_);
        -signal_alert(completed, _).

// --- Utility ---

// Failure handler for broadcast
-!broadcast_alert(_, _, _)
    <-  .print("Warning: Failed to broadcast alert").

-!broadcast_alert_no_pos(_)
    <-  .print("Warning: Failed to broadcast alert").
