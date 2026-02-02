package vesna; // CHANGED: Matches the ASL call "vesna.transition_to"

import jason.asSemantics.DefaultInternalAction;
import jason.asSemantics.TransitionSystem;
import jason.asSemantics.Unifier;
import jason.asSyntax.ListTerm;
import jason.asSyntax.Literal;
import jason.asSyntax.NumberTerm;
import jason.asSyntax.StringTerm;
import jason.asSyntax.Term;
import org.json.JSONObject;
import java.util.HashMap;
import java.util.Map;

/**
 * Internal Action: vesna.transition_to(StateName, [Params])
 * 
 * Sends a transition_to command to the body with optional parameters.
 * 
 * Examples:
 *   vesna.transition_to("Patrol", [target("next")])
 *   vesna.transition_to("Patrol", [target(coords(100, 200))])
 *   vesna.transition_to("Chase", [patience(20)])
 *   vesna.transition_to("Investigate", [points(3)])
 *   vesna.transition_to("Alert", [duration(5)])
 */
public class transition_to extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        // 1. Get the Agent
        VesnaAgent agent = (VesnaAgent) ts.getAg();

        // 2. Parse State Name (Arg 0)
        String stateName;
        if (args[0].isString()) {
            stateName = ((StringTerm) args[0]).getString();
        } else {
            stateName = args[0].toString();
        }

        // 3. Prepare Data Payload
        Map<String, Object> stateParams = new HashMap<>();

        // 4. Parse Optional Parameters (Arg 1)
        if (args.length > 1 && args[1].isList()) {
            ListTerm params = (ListTerm) args[1];

            for (Term t : params) {
                if (t.isLiteral()) {
                    Literal l = (Literal) t;
                    String key = l.getFunctor();
                    
                    // Handle value
                    if (l.getArity() > 0) {
                        Term valueTerm = l.getTerm(0);
                        Object value = parseValue(valueTerm);
                        stateParams.put(key, value);
                    } else {
                        // Boolean flag case: param(true) implied
                        stateParams.put(key, true);
                    }
                }
            }
        }

        // 5. Construct the JSON Message
        JSONObject data = new JSONObject();
        data.put("target_state", stateName);
        if (!stateParams.isEmpty()) {
            data.put("params", new JSONObject(stateParams));
        }

        // Main envelope
        JSONObject action = new JSONObject();
        action.put("sender", ts.getAgArch().getAgName());
        action.put("receiver", "body");
        action.put("type", "transition_to");
        action.put("data", data);

        // 6. Send via perform()
        agent.perform(action.toString());

        return true;
    }
    
    /**
     * Recursively parse a Term value into a Java object.
     * Handles:
     *   - Numbers (int/double)
     *   - Strings
     *   - Atoms (converted to String)
     *   - Compound terms like coords(X, Y) -> {"x": X, "y": Y}
     */
    private Object parseValue(Term valueTerm) throws Exception {
        if (valueTerm.isNumeric()) {
            double val = ((NumberTerm) valueTerm).solve();
            // Return int if whole number
            if (val == Math.floor(val)) {
                return (int) val;
            }
            return val;
        } else if (valueTerm.isString()) {
            return ((StringTerm) valueTerm).getString();
        } else if (valueTerm.isLiteral()) {
            Literal lit = (Literal) valueTerm;
            String functor = lit.getFunctor();
            
            // Special case: coords(X, Y) -> {"x": X, "y": Y}
            if (functor.equals("coords") && lit.getArity() == 2) {
                Map<String, Object> coordMap = new HashMap<>();
                coordMap.put("x", parseValue(lit.getTerm(0)));
                coordMap.put("y", parseValue(lit.getTerm(1)));
                return coordMap;
            }
            
            // For other literals with no args, treat as string
            if (lit.getArity() == 0) {
                return functor;
            }
            
            // For other compound terms, return as string representation
            return valueTerm.toString();
        } else {
            // Fallback: convert to string
            return valueTerm.toString();
        }
    }
}