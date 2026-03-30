import re

def format_javadoc(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # Just standardizing the SETUP block as requested
    setup_replacement = """// =============================================================================
// SETUP & CONFIGURATION
// =============================================================================

/**
 * GOAL/EVENT  : +!update_sympathy(Value)
 * DESCRIPTION : Triggered by the Director at game start to configure personality.
 * CONTEXT     : Receives an integer value from the Director's setup burst.
 * ACTIONS     : Calls vesna.add_temper(sympathy, Value).
 */
+!update_sympathy(Value)[source(Sender)]"""
    
    content = re.sub(
        r'// (={77}\n// )?SETUP & CONFIGURATION\n// ={77}\n+.*?\+!update_sympathy\(Value\)\[source\(Sender\)\]',
        setup_replacement,
        content,
        flags=re.DOTALL
    )

    with open(file_path, 'w') as f:
        f.write(content)

for p in ['mind/src/agt/patrol.asl', 'mind/src/agt/captain.asl', 'mind/src/agt/sentry.asl']:
    format_javadoc(p)
