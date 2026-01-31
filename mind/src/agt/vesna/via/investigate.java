package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.investigate(Points)
 * Argument: Points (Integer) -> Number of random spots to check
 */
public class investigate extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        int points = 3; // Default

        if (args.length > 0 && args[0].isNumeric()) {
            points = (int)((NumberTerm) args[0]).solve();
        }

        JSONObject data = new JSONObject();
        data.put("points", points);

        JSONObject command = new JSONObject();
        command.put("type", "investigate");
        command.put("data", data);

        VesnaAgent agent = (VesnaAgent) ts.getAg();
        agent.perform(command.toString());
        return true;
    }
}