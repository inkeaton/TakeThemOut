package vesna;

import jason.JasonException;
import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

/**
 * Internal Action: vesna.set_var(Name, Value)
 * Arguments:
 *   - Name (Atom/String): The variable name to set on the Godot body
 *   - Value (Term): The value to assign (number, string, or boolean)
 * 
 * Sends: { "type": "set_var", "data": { "name": "...", "value": ... } }
 * 
 * Usage example: vesna.set_var(switch_time, 1.0)   // Set scan rate
 */
public class set_var extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        if (args.length < 2) {
            throw new JasonException("vesna.set_var requires two arguments: name and value.");
        }

        VesnaAgent agent = (VesnaAgent) ts.getAg();
        
        // Extract variable name (remove quotes if string)
        String varName = args[0].toString().replace("\"", "");
        
        // Extract value - handle different types
        Term valueTerm = args[1];
        Object value;
        
        if (valueTerm.isNumeric()) {
            // Numeric value (int or float)
            NumberTerm numTerm = (NumberTerm) valueTerm;
            double numValue = numTerm.solve();
            // Send as integer if it's a whole number, otherwise as double
            if (numValue == Math.floor(numValue) && !Double.isInfinite(numValue)) {
                value = (int) numValue;
            } else {
                value = numValue;
            }
        } else if (valueTerm.isAtom()) {
            // Atom - check for boolean values
            String atomStr = valueTerm.toString();
            if (atomStr.equals("true")) {
                value = true;
            } else if (atomStr.equals("false")) {
                value = false;
            } else {
                value = atomStr;
            }
        } else if (valueTerm.isString()) {
            // String literal
            value = ((StringTerm) valueTerm).getString();
        } else {
            // Default: convert to string
            value = valueTerm.toString();
        }

        // Build message
        JSONObject data = new JSONObject();
        data.put("name", varName);
        data.put("value", value);

        JSONObject command = new JSONObject();
        command.put("type", "set_var");
        command.put("data", data);

        // Send to body
        agent.perform(command.toString());
        return true;
    }
}
