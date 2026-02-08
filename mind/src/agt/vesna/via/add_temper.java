package vesna;

import jason.asSemantics.DefaultInternalAction;
import jason.asSemantics.TransitionSystem;
import jason.asSemantics.Unifier;
import jason.asSyntax.NumberTerm;
import jason.asSyntax.Term;

/**
 * Internal Action: vesna.add_temper(Trait, Value)
 * Example: vesna.add_temper(sympathy, 0.5)
 */
public class add_temper extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        VesnaAgent agent = (VesnaAgent) ts.getAg();
        
        String trait = args[0].toString();
        double value = ((NumberTerm) args[1]).solve();

        if (agent.getTemper() != null) {
            agent.getTemper().modifyMood(trait, value);
            return true;
        }
        return false;
    }
}