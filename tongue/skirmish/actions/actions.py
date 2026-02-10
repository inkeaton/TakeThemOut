from typing import Any, Text, Dict, List
import re
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

# =============================================================================
# KEYWORD PATTERNS (UNCHANGED)
# =============================================================================
KEYWORD_PATTERNS = {
    "bribe": re.compile(
        r'\b(money|pay|paid|dollars|cash|funds|tip|bonus|compensation|compensate|'
        r'expense|envelope|pocket|deal|offer|worth|price|buy|afford|rich)\b',
        re.IGNORECASE
    ),
    "flattery": re.compile(
        r'\b(beautiful|handsome|stunning|gorgeous|magnificent|admire|impressive|'
        r'dashing|radiant|captivating|exquisite|lovely|attractive|elegant|charming|'
        r'eyes|smile|strong|muscular|physique|uniform|looks|looking|pretty)\b',
        re.IGNORECASE
    ),
    "aggression": re.compile(
        r'\b(kill|hurt|destroy|regret|suffer|threat|warn|attack|enemy|'
        r'stupid|idiot|fool|incompetent|useless|pathetic|weak|coward|die|dead)\b',
        re.IGNORECASE
    ),
    "pity": re.compile(
        r'\b(children|family|sick|dying|hospital|orphan|widow|poor|desperate|'
        r'helpless|mercy|please|beg|begging|forgive|sorry|mother|father|child)\b',
        re.IGNORECASE
    ),
    "logic": re.compile(
        r'\b(authorized|clearance|permission|verify|supervisor|check|protocol|'
        r'regulation|paperwork|credentials|official|orders|mission|assignment)\b',
        re.IGNORECASE
    )
}

def apply_keyword_fallback(text: str, current_intent: str, confidence: float) -> tuple:
    """
    Apply keyword-based fallback.
    """
    CONFIDENCE_THRESHOLD = 0.6
    
    # --- 1. STRICT OVERRIDES ---
    flattery_matches = KEYWORD_PATTERNS["flattery"].findall(text)
    if current_intent == "aggression" and len(flattery_matches) > 0:
        return "flattery", True

    bribe_matches = KEYWORD_PATTERNS["bribe"].findall(text)
    if current_intent == "aggression" and len(bribe_matches) > 0:
        return "bribe", True

    # --- 2. STANDARD LOW CONFIDENCE CHECK ---
    if confidence >= CONFIDENCE_THRESHOLD:
        return current_intent, False
    
    scores = {}
    for intent, pattern in KEYWORD_PATTERNS.items():
        matches = pattern.findall(text)
        scores[intent] = len(matches)
    
    if max(scores.values()) > 0:
        best_intent = max(scores, key=scores.get)
        if scores[best_intent] > scores.get(current_intent, 0):
            return best_intent, True
    
    return current_intent, False

class ActionEvaluateExcuse(Action):
    def name(self) -> Text:
        return "action_evaluate_excuse"

    def __init__(self):
        self.analyzer = SentimentIntensityAnalyzer()
        
        # --- PERSONALITY PROFILES (SCORE WEIGHTS) ---
        self.PERSONALITY_PROFILES = {
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

        # --- RESPONSE DICTIONARY (TEXT) ---
        # Structure: [Guard][Intent][Success (True/False)]
        # Success = Score > 0.0
        self.RESPONSES = {
            "rosanna": {
                "flattery": {
                    True:  "(Rosanna preens, checking her reflection.) Oh, stop it. Actually, don't. You can go in.",
                    False: "(Rosanna rolls her eyes.) You're trying too hard, darling. It's pathetic."
                },
                "bribe": {
                    True:  "(Rosanna snatches the offering.) Well, I suppose I can look the other way just this once.",
                    False: "(Rosanna looks offended.) Is that all? My dignity costs more than that."
                },
                "aggression": {
                    True:  "(Rosanna looks surprised.) Okay, okay! No need to shout. Just go.", # Rare case
                    False: "(Rosanna glares icy daggers.) Excuse me? Do you know who I am? Security!"
                },
                "pity": {
                    True:  "(Rosanna sighs dramatically.) Fine, you're ruining my makeup with this sad story.",
                    False: "(Rosanna yawns.) tragedy is so last season. Not my problem."
                },
                "logic": {
                    True:  "(Rosanna checks her nails.) If the paperwork says so, fine. Just hurry up.",
                    False: "(Rosanna waves you off.) Bore someone else with the details."
                }
            },
            "susanna": {
                "flattery": {
                    True:  "(Susanna blushes deeply.) O-oh... you really think so? Um, okay, you can pass.",
                    False: "(Susanna hides her face.) Please don't look at me like that... it's uncomfortable."
                },
                "bribe": {
                    True:  "(Susanna looks around nervously.) I... I shouldn't... but I really need this. Go, quickly!",
                    False: "(Susanna shakes her head frantically.) No! That's against the rules! I can't!"
                },
                "aggression": {
                    True:  "(Susanna trembles.) P-please don't hurt me! Just take whatever you want!", # Fear response
                    False: "(Susanna squeaks.) Eek! G-guard! Help! This person is scary!"
                },
                "pity": {
                    True:  "(Susanna's eyes water.) Oh no, that's awful. Of course you can come in. Here, take a tissue.",
                    False: "(Susanna looks confused.) I... I don't know if I can help you with that."
                },
                "logic": {
                    True:  "(Susanna nods aggressively.) Yes! The rules say this is allowed. Please proceed.",
                    False: "(Susanna frowns at the paper.) I don't think this form is signed correctly... I'm sorry."
                }
            },
            "polyanna": {
                "flattery": {
                    True:  "(Polyanna sighs.) I guess even a broken clock is right twice a day. Go in.",
                    False: "(Polyanna sneers.) Your fake compliments are empty. Like my soul."
                },
                "bribe": {
                    True:  "(Polyanna takes it without looking.) Material possessions are fleeting. But fine.",
                    False: "(Polyanna drops the money.) I can't be bought. I'm already owned by the darkness."
                },
                "aggression": {
                    True:  "(Polyanna nods slowly.) Finally, someone who understands pain. Proceed.",
                    False: "(Polyanna stares into the void.) Your anger is shallow. Come back when you've really suffered."
                },
                "pity": {
                    True:  "(Polyanna looks at you.) Life is suffering. We are all alone. Go ahead.",
                    False: "(Polyanna shrugs.) Cry me a river. We're all dying anyway."
                },
                "logic": {
                    True:  "(Polyanna shrugs.) Rules are just a construct to control the chaos. Whatever.",
                    False: "(Polyanna ignores you.) Order is an illusion."
                }
            },
            "marianna": {
                "flattery": {
                    True:  "(Marianna beams.) Aww! You are too sweet! Get in here, you charmer!",
                    False: "(Marianna tilts her head.) Eh, a bit much, don't you think?"
                },
                "bribe": {
                    True:  "(Marianna winks.) Ooh, lunch is on you today! Thanks, buddy!",
                    False: "(Marianna laughs.) Nice try, but I'm not that cheap!"
                },
                "aggression": {
                    True:  "(Marianna salutes.) Whoa, tough guy! Alright, alright, you're the boss!",
                    False: "(Marianna stops smiling.) Hey, chill out! No bad vibes allowed here."
                },
                "pity": {
                    True:  "(Marianna pats your back.) Oh, buddy! cheer up! Go inside and have a cookie!",
                    False: "(Marianna frowns.) Don't be such a downer. You're killing the mood."
                },
                "logic": {
                    True:  "(Marianna salutes playfully.) Aye aye captain! Everything looks... boringly correct!",
                    False: "(Marianna groans.) Paperwork? Seriously? Booooooring."
                }
            }
        }

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:

        # 1. GET CONTEXT
        guard_name = tracker.get_slot("guard_name")
        if not guard_name: guard_name = "rosanna"
            
        user_text = tracker.latest_message.get('text', "")
        
        intent_data = tracker.latest_message.get('intent', {})
        last_intent = intent_data.get('name') if intent_data else "unknown"
        intent_confidence = intent_data.get('confidence', 0.0)
        
        # Keyword Fallback (Using the function defined globally)
        last_intent, was_corrected = apply_keyword_fallback(user_text, last_intent, intent_confidence)

        # 2. CALCULATE SCORE
        sentiment = self.analyzer.polarity_scores(user_text)
        raw_tone = sentiment['compound']

        profile = self.PERSONALITY_PROFILES.get(guard_name.lower(), self.PERSONALITY_PROFILES["rosanna"])
        
        # Calculate Base Score
        intent_score = profile["intent_weights"].get(last_intent, 0.0)
        sentiment_impact = raw_tone * profile["sentiment_direction"]
        
        # Weighted Final Score (-1.0 to 1.0)
        final_score = (intent_score * 0.7) + (sentiment_impact * 0.3)
        final_score = max(-1.0, min(1.0, final_score))
        
        # 3. GENERATE RESPONSE
        success = final_score > 0.0 # Threshold for "Success" response
        
        # Safe fetch for response text
        guard_responses = self.RESPONSES.get(guard_name.lower(), self.RESPONSES["rosanna"])
        intent_responses = guard_responses.get(last_intent, guard_responses.get("logic")) # Default to logic if intent unknown
        response_text = intent_responses.get(success, "...")

        if last_intent == "nlu_fallback":
             response_text = f"({guard_name.capitalize()} looks confused.) I have no idea what you are saying."
    
        # --- DEBUG LOGGING ---
        print("\n" + "="*50)
        print(f"  DEBUG: SKIRMISH ANALYSIS")
        print(f"--------------------------------------------------")
        print(f"Guard:       {guard_name}")
        print(f"Input:       '{user_text}'")
        if was_corrected:
            print(f"Intent:      {last_intent} (CORRECTED from '{original_intent}')")
        else:
            print(f"Intent:      {last_intent} (Confidence: {intent_confidence:.2f})")
        print(f"Tone (Raw):  {raw_tone:.2f}")
        print(f"Score Calc:  [Intent: {intent_score}] * 0.7 + [Tone: {sentiment_impact:.2f}] * 0.3")
        print(f"Final Score: {final_score:.2f}")
        print(f"Outcome:     {'SUCCESS' if success else 'FAILURE'}")
        print("="*50 + "\n")

        # 4. SEND RESPONSE
        dispatcher.utter_message(
            text=response_text,
            json_message={
                "sympathy_score": round(final_score, 2), 
                "detected_intent": last_intent,
                "guard_name": guard_name
            }
        )
        return []