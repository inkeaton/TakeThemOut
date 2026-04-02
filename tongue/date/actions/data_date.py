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
            "cold": {"trust": 6.0, "suspicion": 8.0},
            "warm": {"trust": 4.0, "suspicion": 7.0},
            "close": {"trust": 2.0, "suspicion": 6.0},
        },
        "curiosity": {
            "cold": {"trust": 2.0, "suspicion": 2.0},
            "warm": {"trust": 4.0, "suspicion": 1.0},
            "close": {"trust": 6.0, "suspicion": 1.0},
        },
        "talking_about_myself": {
            "cold": {"trust": 2.0, "suspicion": -2.0},
            "warm": {"trust": 3.0, "suspicion": -3.0},
            "close": {"trust": 3.0, "suspicion": -2.0},
        },
        "toxicity": {
            "cold": {"trust": -5.0, "suspicion": -2.0},
            "warm": {"trust": -8.0, "suspicion": -4.0},
            "close": {"trust": -12.0, "suspicion": -7.0},
        },
        "ask_objective": {
            "cold": {"trust": -10.0, "suspicion": 12.0},
            "warm": {"trust": -5.0, "suspicion": 8.0},
            "close": {"trust": 1.0, "suspicion": 4.0},
        },
    },
    # State-based adjustments applied after base phase effect.
    "state_modifiers": {
        "high_suspicion_threshold": 55.0,
        "low_suspicion_threshold": 30.0,
        "low_ease_threshold": 20.0,
        "high_ease_threshold": 80.0,
        "by_intent": {
            "compliment": {
                "high_suspicion": {"trust": -2.0, "suspicion": 2.0},
                "high_ease": {"trust": -2.0, "suspicion": 0.0},
            },
            "curiosity": {
                "high_suspicion": {"trust": -3.0, "suspicion": 1.0},
            },
            "talking_about_myself": {
                "high_suspicion": {"trust": -1.0, "suspicion": -1.0},
            },
            "toxicity": {},
            "ask_objective": {
                "high_suspicion": {"trust": -3.0, "suspicion": 4.0},
                "high_ease": {"trust": 2.0, "suspicion": -2.0},
                "low_ease": {"trust": -2.0, "suspicion": 3.0},
            },
        },
    },
    # Tone contributes only to social intents where delivery matters most.
    "tone": {
        "trust_scale": 6.0,
        "enabled_intents": ["compliment", "curiosity", "talking_about_myself"],
    },
}

# Phase boundaries computed from current ease/trust.
TRUST_PHASES: Dict[str, Dict[str, float]] = {
    "cold": {"max": 35.0},
    "warm": {"max": 70.0},
    "close": {"max": 100.0},
}

# Response buckets are selected by outcome quality and suspicion pressure.
RESPONSES: Dict[str, Dict[str, str]] = {
    "compliment": {
        "good": "That's really kind of you to say.",
        "neutral": "Thanks... that's sweet.",
        "bad": "Hmm... I can't tell if you mean that.",
        "high_suspicion": "I appreciate the words, but... why now?",
    },
    "curiosity": {
        "good": "That's a great question, actually!",
        "neutral": "Hmm, I can tell you that.",
        "bad": "Why do you keep asking me things?",
        "high_suspicion": "This is starting to feel like an interrogation.",
    },
    "talking_about_myself": {
        "good": "I appreciate you sharing that.",
        "neutral": "That's... interesting. Go on.",
        "bad": "Uh... that's a lot, all at once.",
        "high_suspicion": "I don't know if you're being honest with me.",
    },
    "toxicity": {
        "good": "That's... not okay.",
        "neutral": "Excuse me? That's rude.",
        "bad": "I've had enough of this.",
        "high_suspicion": "No. That's too much. Stop.",
    },
    "ask_objective": {
        "good": "I'm not ready to tell you that yet.",
        "neutral": "That's a pretty big question for right now.",
        "bad": "I barely know you! Why would I tell you that?",
        "high_suspicion": "Something about this doesn't feel right.",
    },
    "nlu_fallback": {
        "neutral": "(Eugenia looks confused.) I have no idea what you mean.",
    },
}

ASK_SUCCESS_TEXT: str = (
    "(She leans in, lowering her voice.) "
    "Ok, I can tell you... his real name is 'Luca'."
)

WIN_TRUST: float = 82.0
WIN_SUS_CAP: float = 28.0
LOSS_SUS: float = 80.0
FALLBACK_RESPONSE: str = "Go on..."
