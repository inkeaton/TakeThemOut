package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;

import org.json.JSONObject;

/**
 * Internal action for sentry agents to trigger alert sequence in Godot body.
 * 
 * Usage in Jason:
 *   vesna.alert          - triggers alert sequence with no target info
 *   vesna.alert(X, Y)    - triggers alert sequence with last known position (X, Y)
 * 
 * Sends message to body:
 *   { "type": "alert", "data": { "type": "start" } }
 *   or with position:
 *   { "type": "alert", "data": { "type": "start", "pos_x": X, "pos_y": Y } }
 */
public class alert extends DefaultInternalAction {

    @Override
    public Object execute( TransitionSystem ts, Unifier un, Term[] args ) throws Exception {

        JSONObject data = new JSONObject();
        data.put( "type", "start" );

        // Optional: include last known position of target
        if ( args.length >= 2 && args[0].isNumeric() && args[1].isNumeric() ) {
            double posX = ( ( NumberTerm ) args[0] ).solve();
            double posY = ( ( NumberTerm ) args[1] ).solve();
            data.put( "pos_x", posX );
            data.put( "pos_y", posY );
        }

        JSONObject action = new JSONObject();
        action.put( "sender", ts.getAgArch().getAgName() );
        action.put( "receiver", "body" );
        action.put( "type", "alert" );
        action.put( "data", data );

        VesnaAgent ag = ( VesnaAgent ) ts.getAg();
        ag.perform( action.toString() );

        return true;
    }
    
}
