package vesna;

import jason.asSemantics.*;
import jason.asSyntax.*;
import java.util.List;

/**
 * Internal Action: vesna.calc_centroid(List, AvgX, AvgY)
 * * Arguments:
 * - List: A list of position terms, e.g., [pos(10,10), pos(20,20)]
 * - AvgX: (Output) The calculated average X coordinate
 * - AvgY: (Output) The calculated average Y coordinate
 */
public class calc_centroid extends DefaultInternalAction {

    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
        // Validate arguments
        if (args.length < 3) {
            throw new Exception("vesna.calc_centroid requires 3 arguments: List, OutputX, OutputY.");
        }

        ListTerm list = (ListTerm) args[0];
        
        // If list is empty, return false (cannot calculate)
        if (list.isEmpty()) {
            return false;
        }

        double sumX = 0;
        double sumY = 0;
        int count = 0;

        // Iterate through the list
        for (Term t : list) {
            // Check if term is structure pos(X, Y)
            if (t.isStructure()) {
                Structure pos = (Structure) t;
                if (pos.getArity() >= 2) {
                    // Extract numeric values
                    double x = ((NumberTerm) pos.getTerm(0)).solve();
                    double y = ((NumberTerm) pos.getTerm(1)).solve();
                    
                    sumX += x;
                    sumY += y;
                    count++;
                }
            }
        }

        if (count == 0) return false;

        // Calculate Averages
        double avgX = sumX / count;
        double avgY = sumY / count;

        // Unify the results with the output variables (args[1] and args[2])
        return un.unifies(args[1], new NumberTermImpl(avgX)) &&
               un.unifies(args[2], new NumberTermImpl(avgY));
    }
}