package vesna;

import jason.JasonException; 
import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.continue_patrol(Direction)
 * Argument: Direction (Atom/String) -> "next" or "prev"
 */
public class continue_patrol extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        // Validate argument count
        if (args.length < 1) {
            throw new JasonException("continue_patrol requires a direction ('next' or 'prev').");
        }

        VesnaAgent agent = (VesnaAgent) ts.getAg();
        
        // Get the direction (remove quotes if it's a string)
        String direction = args[0].toString().replace("\"", "");

        // 1. Build Data: {"action": "next"} or {"action": "prev"}
        JSONObject data = new JSONObject();
        data.put("action", direction);

        // 2. Build Wrapper
        JSONObject command = new JSONObject();
        command.put("type", "move");
        command.put("data", data);

        // 3. Send
        agent.perform(command.toString());
        return true;
    }
}