package vesna;

import jason.JasonException; 
import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.patrol(Action)
 * Argument: Action (Atom/String) -> "next", "prev", or "resume"
 * Sends: { "type": "patrol", "data": { "action": Action } }
 */
public class patrol extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        if (args.length < 1) {
            throw new JasonException("vesna.patrol requires an action argument (e.g. next, prev, resume).");
        }

        VesnaAgent agent = (VesnaAgent) ts.getAg();
        String action = args[0].toString().replace("\"", "");

        // 1. Build Data
        JSONObject data = new JSONObject();
        data.put("action", action);

        // 2. Build Wrapper (Unified Type "patrol")
        JSONObject command = new JSONObject();
        command.put("type", "patrol");
        command.put("data", data);

        // 3. Send
        agent.perform(command.toString());
        return true;
    }
}