from typing import Dict, Any

DEFAULT_DATE_PROFILE: Dict[str, Any] = {
    # Base intent effect by relationship phase (cold/warm/close).
    # Gameplay direction:
    # - compliment: early strong ease with even higher suspicion, then diminishing ease
    # - curiosity: modest early value, scales with phase, reduced under high suspicion
    # - talking_about_myself: small ease gain with suspicion relief
    # - toxicity: lowers both ease and suspicion, stronger later
    # - ask_objective: risky early, more viable later
    "intent_phase_effects": {
        "compliment": {
            "cold": {"trust": 10.0, "suspicion": 13.0},
            "warm": {"trust": 6.0, "suspicion": 11.0},
            "close": {"trust": 2.0, "suspicion": 9.0},
        },
        "curiosity": {
            "cold": {"trust": 2.0, "suspicion": 3.0},
            "warm": {"trust": 6.0, "suspicion": 3.0},
            "close": {"trust": 10.0, "suspicion": 0.0},
        },
        "talking_about_myself": {
            "cold": {"trust": 2.0, "suspicion": -3.0},
            "warm": {"trust": 6.0, "suspicion": -6.0},
            "close": {"trust": 10.0, "suspicion": -3.0},
        },
        "toxicity": {
            "cold": {"trust": -9.0, "suspicion": -2.0},
            "warm": {"trust": -13.0, "suspicion": -5.0},
            "close": {"trust": -20.0, "suspicion": -9.0},
        },
        "ask_objective": {
            "cold": {"trust": -15.0, "suspicion": 20.0},
            "warm": {"trust": -9.0, "suspicion": 13.0},
            "close": {"trust": 2.0, "suspicion": 7.0},
        },
    },
    # Tone contributes only to social intents where delivery matters most.
    "tone": {
        "trust_scale": 2.0,
        "enabled_intents": ["compliment", "curiosity", "talking_about_myself"],
    },
}

# Phase boundaries computed from current ease/trust.
TRUST_PHASES: Dict[str, Dict[str, float]] = {
    "cold": {"max": 30.0},
    "warm": {"max": 50.0},
    "close": {"max": 100.0},
}

# Response buckets are selected by outcome quality and suspicion pressure.
RESPONSES: Dict[str, Dict[str, str]] = {
    "compliment": {
        "good": "That's really kind of you to say.",
        "neutral": "Thanks... that's sweet.",
        "bad": "Hmm... I can't tell if you mean that."
    },
    "curiosity": {
        "good": "That's a great question, actually!",
        "neutral": "Hmm, I can tell you that.",
        "bad": "Why do you keep asking me things?"
    },
    "talking_about_myself": {
        "good": "I appreciate you sharing that.",
        "neutral": "That's... interesting. Go on.",
        "bad": "Uh... that's a lot, all at once."
    },
    "toxicity": {
        "good": "That's... not okay.",
        "neutral": "Excuse me? That's rude.",
        "bad": "I've had enough of this."
    },
    "ask_objective": {
        "good": "I'm not ready to tell you that yet.",
        "neutral": "That's a pretty big question for right now.",
        "bad": "I barely know you! Why would I tell you that?"
    },
    "nlu_fallback": {
        "neutral": "(Eugenia looks confused.) I have no idea what you mean.",
    },
}

ASK_SUCCESS_TEXT: str = (
    "(She leans in, lowering her voice.) "
    "Ok, I can tell you... his real name is 'Luca'."
)

WIN_TRUST: float = 80.0
WIN_SUS_CAP: float = 30.0
LOSS_SUS: float = 75.0
FALLBACK_RESPONSE: str = "Go on..."
