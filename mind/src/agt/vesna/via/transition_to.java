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

public class transition_to extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        // 1. Get the Agent (No import needed since we are in package vesna)
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
                        if (valueTerm.isNumeric()) {
                            stateParams.put(key, ((NumberTerm) valueTerm).solve());
                        } else if (valueTerm.isString()) {
                            stateParams.put(key, ((StringTerm) valueTerm).getString());
                        } else {
                            stateParams.put(key, valueTerm.toString());
                        }
                    } else {
                        // Boolean flag case: param(true) implied
                        stateParams.put(key, true);
                    }
                }
            }
        }

        // 5. Construct the JSON Message
        // Inner "data" object
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
}