package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;

import java.util.Set;

import org.json.JSONArray;
import org.json.JSONObject;

import static jason.asSyntax.ASSyntax.*;

public class walk extends DefaultInternalAction {

    // walk()               performs a step
    // walk( n )            performs a step of length n
    // walk( target )       goes to target
    // walk( target, id )   goes to target with id

    @Override
    public Object execute( TransitionSystem ts, Unifier un, Term[] args ) throws Exception {

        String type = "none";
        if ( args.length == 0 )
            type = "step";
        else if ( args.length == 1 ){
            if ( args[0].isNumeric() )
                type = "step";
            else if ( args[0].isLiteral() || args[0].isString() )
                type = "goto";
        } else if ( args.length == 2 && (args[0].isLiteral() || args[0].isString()) && args[1].isNumeric() )
            type = "goto";
        else if ( args.length == 2 && (args[0].isLiteral() || args[0].isString()) && !args[1].isGround() )
            type = "goto";
        else 
            return false;

        JSONObject data = new JSONObject();
        JSONArray propensions = new JSONArray();

        VesnaAgent ag = ( VesnaAgent ) ts.getAg();
        Unifier u = new Unifier();
        if ( ag.believes( createLiteral( "propensions" , new VarTerm( "Ps" ) ), u ) ) {
            ListTerm props = ( ListTerm ) u.get( "Ps" );
            for ( Term prop : props ) {
                propensions.put( prop.toString() );
            }
        }

        data.put( "type", type );
        if ( type.equals( "step" ) ){
            if ( args.length == 2 ){
                data.put( "length", ( ( NumberTerm ) args[1] ).solve() );
            }
        } else if ( type.equals( "goto" ) ) {
            String targetName = args[0].toString();
            // If it's a StringTerm, remove surrounding quotes
            if ( args[0].isString() ) {
                targetName = ((jason.asSyntax.StringTerm) args[0]).getString();
            }
            data.put( "target", targetName );
            if ( args.length == 2 && args[1].isGround() )
                data.put( "id", ( ( NumberTerm ) args[1] ).solve() );
        }

        JSONObject action = new JSONObject();
        action.put( "sender", ts.getAgArch().getAgName() );
        action.put( "receiver", "body" );
        action.put( "type", "walk" );
        action.put( "data", data );
        action.put( "propensions", propensions );

        ag.perform( action.toString() );

        return true;
    }
    
}
