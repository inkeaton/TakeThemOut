package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;

import org.json.JSONObject;

/**
 * Internal action for sentry agents to trigger alert sequence in Godot body.
 * 
 * Usage in Jason:
 *   vesna.alert          - triggers alert sequence with no target info
 * 
 * Sends message to body:
 *   { "type": "alert", "data": { "type": "start" } }
 */
public class alert extends DefaultInternalAction {

    @Override
    public Object execute( TransitionSystem ts, Unifier un, Term[] args ) throws Exception {

        JSONObject data = new JSONObject();
        data.put( "type", "start" );

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
