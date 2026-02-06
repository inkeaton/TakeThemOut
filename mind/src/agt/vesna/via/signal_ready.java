package vesna;

import jason.asSemantics.DefaultInternalAction;
import jason.asSemantics.TransitionSystem;
import jason.asSemantics.Unifier;
import jason.asSyntax.Term;
import org.json.JSONObject;

/**
 * Internal Action: vesna.signal_ready
 * 
 * Sends a "signal_ready" message to the Godot body (ServerManager on port 9200),
 * informing it that the Jason mind has fully initialized and all agents are running.
 * 
 * Takes no arguments.
 * 
 * Sends: { "sender": "director", "receiver": "body", "type": "signal_ready", "data": {} }
 * 
 * Usage:
 *   vesna.signal_ready;
 */
public class signal_ready extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {

        VesnaAgent agent = (VesnaAgent) ts.getAg();

        // Build the ready signal message
        JSONObject data = new JSONObject();

        JSONObject action = new JSONObject();
        action.put("sender", ts.getAgArch().getAgName());
        action.put("receiver", "body");
        action.put("type", "signal_ready");
        action.put("data", data);

        // Send to body via WebSocket
        agent.perform(action.toString());

        ts.getLogger().info("Signal ready sent to Godot.");

        return true;
    }
}
