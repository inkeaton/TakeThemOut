package vesna;

import jason.asSemantics.DefaultInternalAction;
import jason.asSemantics.TransitionSystem;
import jason.asSemantics.Unifier;
import jason.asSyntax.Term;
import vesna.VesnaAgent;
import org.json.JSONObject;

public class chase extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        // Usage: vesna.chase(TargetId)
        
        // 1. Validate arguments
        if (args.length < 1) {
            ts.getLogger().warning("The internal action 'chase' requires a Target ID argument.");
            return false;
        }

        // 2. Prepare Data Payload
        JSONObject data = new JSONObject();
        
        // Check if the argument is a number (ID) or string
        if (args[0].isNumeric()) {
            // Godot expects an integer ID for instance_from_id()
            long id = (long) ((jason.asSyntax.NumberTerm) args[0]).solve();
            data.put("id", id);
        } else {
            // Fallback if we pass a name string, though ID is preferred for robustness
            data.put("target_name", args[0].toString());
        }

        // 3. Construct the Full Message
        JSONObject action = new JSONObject();
        action.put("sender", ts.getAgArch().getAgName());
        action.put("receiver", "body");
        action.put("type", "chase"); // Matches the match string in patrol.gd
        action.put("data", data);

        // 4. Send via VesnaAgent
        VesnaAgent ag = (VesnaAgent) ts.getAg();
        ag.perform(action.toString());

        return true;
    }
}