from typing import Any, Text, Dict, List
import re
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SlotSet
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

# =============================================================================
# KEYWORD PATTERNS (DATE CONTEXT)
# =============================================================================
KEYWORD_PATTERNS = {
    "compliment": re.compile(
        r'\b(beautiful|handsome|stunning|gorgeous|magnificent|admire|impressive|'
        r'dashing|radiant|captivating|exquisite|lovely|attractive|elegant|charming|'
        r'eyes|smile|style|smart|funny|sexy|cute|love|like|enjoy|wonderful)\b',
        re.IGNORECASE
    ),
    "curiosity": re.compile(
        r'\b(what|who|where|when|how|why|tell me|ask|passionate|dream|vacation|'
        r'family|job|work|favorite|childhood|secret)\b',
        re.IGNORECASE
    ),
    "talking_about_myself": re.compile(
        r'\b(i am|i feel|i work|i love|i have|my family|my job|my dog|nervous|'
        r'lonely|honest|trust|connection|scared|worried|myself|personally)\b',
        re.IGNORECASE
    ),
    "toxicity": re.compile(
        r'\b(boring|ugly|stupid|hate|dumb|waste|annoying|dull|weird|terrible|'
        r'shut up|leave|go away|bad|awful|disgusting|loser)\b',
        re.IGNORECASE
    ),
}

def apply_keyword_fallback(text: str, current_intent: str, confidence: float) -> tuple:
    """
    Forces intents based on specific vocabulary if confidence is low,
    or if specific symbols (like '?') dictate the intent.
    """
    CONFIDENCE_THRESHOLD = 0.6
    
    # --- 1. STRICT OVERRIDES ---
    # If the user asks a question, it is almost certainly curiosity
    if "?" in text and current_intent != "curiosity":
         # Only override if it's not a clear compliment like "Don't you look pretty?"
         if not KEYWORD_PATTERNS["compliment"].search(text):
             return "curiosity", True

    # Toxicity override (Safety net)
    toxic_matches = KEYWORD_PATTERNS["toxicity"].findall(text)
    if current_intent != "toxicity" and len(toxic_matches) > 0:
        return "toxicity", True

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


class ActionEvaluateDate(Action):
    def name(self) -> Text:
        return "action_evaluate_date"

    def __init__(self):
        self.analyzer = SentimentIntensityAnalyzer()

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:

        # 1. INPUT ANALYSIS
        user_text = tracker.latest_message.get('text', "")
        intent_data = tracker.latest_message.get('intent', {})
        original_intent = intent_data.get('name', "unknown")
        intent_confidence = intent_data.get('confidence', 0.0)
        
        # Keyword Fallback
        last_intent, was_corrected = apply_keyword_fallback(user_text, original_intent, intent_confidence)

        # Sentiment Analysis
        sentiment = self.analyzer.polarity_scores(user_text) 
        tone_score = sentiment['compound']
        
        # 2. GET CURRENT SCORE STATE
        # Godot expects "ease_score" (Trust) and "suspicion_score" 
        trust = tracker.get_slot("ease_score") or 20.0
        suspicion = tracker.get_slot("suspicion_score") or 0.0
        
        start_trust = trust
        start_suspicion = suspicion

        # 3. CALCULATE DELTAS
        d_trust = 0
        d_sus = 0
        modifier_msg = ""
        game_event = None # Used to signal Win/Loss to Godot

        # --- INTENT LOGIC ---
        if last_intent == "compliment":
            d_trust = 10
            d_sus = -2
            if tone_score < -0.1: # Sarcastic compliment
                d_trust = -10
                d_sus = 10
                modifier_msg = "(She frowns at your tone)"

        elif last_intent == "curiosity":
            # Asking about her is the safest move.
            d_trust = 5
            d_sus = -5 

        elif last_intent == "talking_about_myself": 
            # DYNAMIC: High risk if trust is low
            if trust >= 40:
                d_trust = 15  
                d_sus = -5
                modifier_msg = "(She appreciates your honesty)"
            else:
                d_trust = -5
                d_sus = 10    
                modifier_msg = "(She looks uncomfortable with the oversharing)"

        elif last_intent == "toxicity":
            d_trust = -30
            d_sus = 20

        # 4. BOUNDARY CHECKS
        trust = max(0, min(100, trust + d_trust))
        suspicion = max(0, min(100, suspicion + d_sus))

        # 5. WIN/LOSS CONDITIONS
        
        # WIN CONDITION: "ask_objective"
        if last_intent == "ask_objective":
            if trust >= 80 and suspicion < 30:
                response_text = "(She leans in, lowering her voice.) Ok, I can tell you... his real name is 'Luca'."
                game_event = "date_success" # [cite: 1] Triggers _handle_game_event
                trust = 100
            else:
                if suspicion >= 30:
                    response_text = "Why are you asking me that? You're acting weird."
                else:
                    response_text = "I barely know you! I'm not telling you that."
                
                # Penalty for asking too early
                d_trust = -10
                d_sus = 15
                trust -= 10
                suspicion += 15

        # LOSS CONDITION: Suspicion too high
        elif suspicion >= 80:
            response_text = "You're making me really uncomfortable. I'm leaving."
            game_event = "date_failed" # [cite: 1] Triggers _handle_game_event
            suspicion = 100
        
        # STANDARD RESPONSES (Flavor Text)
        else:
            if modifier_msg:
                response_text = modifier_msg + " "
            else:
                response_text = ""
                
            if last_intent == "compliment":
                response_text += "That's sweet of you to say."
            elif last_intent == "curiosity":
                response_text += "That's a good question... I'd love to tell you."
            elif last_intent == "talking_about_myself":
                if d_trust > 0: response_text += "I feel the same way."
                else: response_text += "Uh... okay? TMI."
            elif last_intent == "toxicity":
                response_text += "Excuse me? That's rude."
            else:
                response_text += "Go on..."

        # 6. DEBUG LOGGING (Keep this, it's good)
        print("\n" + "="*50)
        print(f"  DEBUG: DATING ANALYSIS")
        print(f"--------------------------------------------------")
        print(f"Input:       '{user_text}'")
        if was_corrected:
            print(f"Intent:      {last_intent} (CORRECTED from '{original_intent}')")
        else:
            print(f"Intent:      {last_intent} (Confidence: {intent_confidence:.2f})")
        print(f"Trust:       {start_trust:.1f} -> {trust:.1f} (Delta: {d_trust})")
        print(f"Suspicion:   {start_suspicion:.1f} -> {suspicion:.1f} (Delta: {d_sus})")
        if game_event:
            print(f"Outcome:     EVENT TRIGGERED -> {game_event}")
        elif modifier_msg:
             print(f"Modifier:    {modifier_msg}")
        print("="*50 + "\n")

        # 7. SEND RESPONSE (FIXED JSON CONSTRUCTION)
        
        # Base dictionary
        custom_data = {
            "ease_score": trust,
            "suspicion_score": suspicion,
            "delta_suspicion": d_sus,
            "detected_intent": last_intent
        }
        
        # FIX: Only add game_event if it actually exists (is not None).
        # This prevents Godot from receiving "game_event": null and crashing.
        if game_event:
            custom_data["game_event"] = game_event

        dispatcher.utter_message(
            text=response_text,
            json_message=custom_data
        )

        return [SlotSet("ease_score", trust), SlotSet("suspicion_score", suspicion)]