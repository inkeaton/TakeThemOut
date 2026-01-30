package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.move_next
 * Sends a command to the body to proceed to the next waypoint in its sorted list.
 */
public class move_next extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        VesnaAgent agent = (VesnaAgent) ts.getAg();

        // 1. Construct the data payload: {"action": "next"}
        JSONObject data = new JSONObject();
        data.put("action", "next");

        // 2. Construct the main message: {"type": "move", "data": ...}
        JSONObject command = new JSONObject();
        command.put("type", "move");
        command.put("data", data);

        // 3. Send to Godot
        agent.perform(command.toString());
        return true;
    }
}