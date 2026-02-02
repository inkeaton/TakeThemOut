package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.lock(Action)
 * 
 * Arguments:
 *   Action (atom): Either "set" or "release"
 * 
 * Sends: { "type": "lock", "data": { "action": "set" | "release" } }
 * 
 * Controls the alert_lock on the body:
 * - "set": Stops movement and sets alert_lock (prevents patrol commands)
 * - "release": Releases alert_lock (allows patrol commands again)
 * 
 * Usage:
 *   vesna.lock(set)     // Stop and lock during hesitation
 *   vesna.lock(release) // Unlock when investigation completes
 */
public class lock extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("vesna.lock requires exactly 1 argument: action (set or release)");
        }

        VesnaAgent agent = (VesnaAgent) ts.getAg();

        // Get action argument
        String action = args[0].toString();
        
        // Validate action
        if (!action.equals("set") && !action.equals("release")) {
            throw new IllegalArgumentException("vesna.lock action must be 'set' or 'release', got: " + action);
        }

        JSONObject data = new JSONObject();
        data.put("action", action);
        
        JSONObject command = new JSONObject();
        command.put("type", "lock");
        command.put("data", data);

        agent.perform(command.toString());
        return true;
    }
}
