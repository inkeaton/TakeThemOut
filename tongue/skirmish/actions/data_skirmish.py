from typing import Dict, Any

# Skirmish static tuning data.
# This module contains no runtime logic; actions.py consumes it to compute
# a normalized persuasion score and to pick guard-specific response lines.

# Gameplay constants for score blend and pass/fail boundary.
DEFAULT_GUARD_NAME: str = "rosanna"
INTENT_WEIGHT_FACTOR: float = 0.7
SENTIMENT_WEIGHT_FACTOR: float = 0.3
SCORE_MIN: float = -1.0
SCORE_MAX: float = 1.0
SUCCESS_THRESHOLD: float = 0.0
FALLBACK_INTENT: str = "logic"
UNKNOWN_RESPONSE: str = "..."

# Per-guard scoring profile.
# - intent_weights: tactic preference by intent.
# - sentiment_direction: whether positive tone helps (1) or hurts (-1).
PERSONALITY_PROFILES: Dict[str, Dict[str, Any]] = {
    "rosanna": {
        "intent_weights": {"flattery": 1.0, "bribe": 0.5, "pity": -0.5, "logic": 0.2, "aggression": -1.0},
        "sentiment_direction": 1
    },
    "susanna": {
        "intent_weights": {"flattery": 0.2, "bribe": -0.5, "pity": 0.8, "logic": 0.9, "aggression": -1.0},
        "sentiment_direction": 1
    },
    "polyanna": {
        "intent_weights": {"flattery": -0.8, "bribe": -0.5, "pity": 0.7, "logic": -0.2, "aggression": 0.4},
        "sentiment_direction": -1
    },
    "marianna": {
        "intent_weights": {"flattery": 0.6, "bribe": 0.2, "pity": -0.8, "logic": -0.6, "aggression": -0.5},
        "sentiment_direction": 1
    },
}

# Dialogue mapping used after scoring.
# The bool key maps to success/failure branch for tone.
RESPONSES: Dict[str, Dict[str, Dict[bool, str]]] = {
    "rosanna": {
        "flattery": {
            True: "(Rosanna preens, checking her reflection.) Oh, stop it. Actually, don't. You can go in.",
            False: "(Rosanna rolls her eyes.) You're trying too hard, darling. It's pathetic."
        },
        "bribe": {
            True: "(Rosanna snatches the offering.) Well, I suppose I can look the other way just this once.",
            False: "(Rosanna looks offended.) Is that all? My dignity costs more than that."
        },
        "aggression": {
            True: "(Rosanna looks surprised.) Okay, okay! No need to shout. Just go.",
            False: "(Rosanna glares icy daggers.) Excuse me? Do you know who I am? Security!"
        },
        "pity": {
            True: "(Rosanna sighs dramatically.) Fine, you're ruining my makeup with this sad story.",
            False: "(Rosanna yawns.) tragedy is so last season. Not my problem."
        },
        "logic": {
            True: "(Rosanna checks her nails.) If the paperwork says so, fine. Just hurry up.",
            False: "(Rosanna waves you off.) Bore someone else with the details."
        }
    },
    "susanna": {
        "flattery": {
            True: "(Susanna blushes deeply.) O-oh... you really think so? Um, okay, you can pass.",
            False: "(Susanna hides her face.) Please don't look at me like that... it's uncomfortable."
        },
        "bribe": {
            True: "(Susanna looks around nervously.) I... I shouldn't... but I really need this. Go, quickly!",
            False: "(Susanna shakes her head frantically.) No! That's against the rules! I can't!"
        },
        "aggression": {
            True: "(Susanna trembles.) P-please don't hurt me! Just take whatever you want!",
            False: "(Susanna squeaks.) Eek! G-guard! Help! This person is scary!"
        },
        "pity": {
            True: "(Susanna's eyes water.) Oh no, that's awful. Of course you can come in. Here, take a tissue.",
            False: "(Susanna looks confused.) I... I don't know if I can help you with that."
        },
        "logic": {
            True: "(Susanna nods aggressively.) Yes! The rules say this is allowed. Please proceed.",
            False: "(Susanna frowns at the paper.) I don't think this form is signed correctly... I'm sorry."
        }
    },
    "polyanna": {
        "flattery": {
            True: "(Polyanna sighs.) I guess even a broken clock is right twice a day. Go in.",
            False: "(Polyanna sneers.) Your fake compliments are empty. Like my soul."
        },
        "bribe": {
            True: "(Polyanna takes it without looking.) Material possessions are fleeting. But fine.",
            False: "(Polyanna drops the money.) I can't be bought. I'm already owned by the darkness."
        },
        "aggression": {
            True: "(Polyanna nods slowly.) Finally, someone who understands pain. Proceed.",
            False: "(Polyanna stares into the void.) Your anger is shallow. Come back when you've really suffered."
        },
        "pity": {
            True: "(Polyanna looks at you.) Life is suffering. We are all alone. Go ahead.",
            False: "(Polyanna shrugs.) Cry me a river. We're all dying anyway."
        },
        "logic": {
            True: "(Polyanna shrugs.) Rules are just a construct to control the chaos. Whatever.",
            False: "(Polyanna ignores you.) Order is an illusion."
        }
    },
    "marianna": {
        "flattery": {
            True: "(Marianna beams.) Aww! You are too sweet! Get in here, you charmer!",
            False: "(Marianna tilts her head.) Eh, a bit much, don't you think?"
        },
        "bribe": {
            True: "(Marianna winks.) Ooh, lunch is on you today! Thanks, buddy!",
            False: "(Marianna laughs.) Nice try, but I'm not that cheap!"
        },
        "aggression": {
            True: "(Marianna salutes.) Whoa, tough guy! Alright, alright, you're the boss!",
            False: "(Marianna stops smiling.) Hey, chill out! No bad vibes allowed here."
        },
        "pity": {
            True: "(Marianna pats your back.) Oh, buddy! cheer up! Go inside and have a cookie!",
            False: "(Marianna frowns.) Don't be such a downer. You're killing the mood."
        },
        "logic": {
            True: "(Marianna salutes playfully.) Aye aye captain! Everything looks... boringly correct!",
            False: "(Marianna groans.) Paperwork? Seriously? Booooooring."
        }
    }
}
