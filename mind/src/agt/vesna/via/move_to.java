package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.move_to(X, Y)
 * Arguments: X (Number), Y (Number) -> Target coordinates
 * Sends: { "type": "move_to", "data": { "pos_x": X, "pos_y": Y } }
 */
public class move_to extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        // Validate arguments
        if (args.length < 2) {
            throw new Exception("vesna.move_to requires two arguments: X and Y coordinates.");
        }

        // Parse coordinates
        double x = ((NumberTerm) args[0]).solve();
        double y = ((NumberTerm) args[1]).solve();

        // 1. Build Data Payload
        JSONObject data = new JSONObject();
        data.put("pos_x", x);
        data.put("pos_y", y);

        // 2. Build Wrapper
        JSONObject command = new JSONObject();
        command.put("type", "move_to");
        command.put("sender", ts.getAgArch().getAgName());
        command.put("receiver", "body");
        command.put("data", data);

        // 3. Send
        VesnaAgent agent = (VesnaAgent) ts.getAg();
        agent.perform(command.toString());

        return true;
    }
}