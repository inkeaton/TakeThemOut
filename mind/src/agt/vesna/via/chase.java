package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import org.json.JSONObject;

public class chase extends DefaultInternalAction {

    @Override
    public Object execute( TransitionSystem ts, Unifier un, Term[] args ) throws Exception {
        
        // 1. Default patience value
        int patience = 5;

        // 2. Check if an argument was passed
        if (args.length > 0 && args[0].isNumeric()) {
            patience = (int)((NumberTerm) args[0]).solve();
        }

        // 3. Build the Data Payload
        JSONObject data = new JSONObject();
        data.put( "type", "start" );
        data.put( "patience", patience ); // <--- Sending the value

        // 4. Build the Action Wrapper
        JSONObject action = new JSONObject();
        action.put( "sender", ts.getAgArch().getAgName() );
        action.put( "receiver", "body" );
        action.put( "type", "chase" );
        action.put( "data", data );

        // 5. Send
        VesnaAgent ag = ( VesnaAgent ) ts.getAg();
        ag.perform( action.toString() );

        return true;
    }
}