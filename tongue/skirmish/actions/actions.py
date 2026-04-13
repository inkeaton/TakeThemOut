from typing import Any, Text, Dict, List
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
from .data_skirmish import (
    DEFAULT_GUARD_NAME,
    INTENT_WEIGHT_FACTOR,
    SENTIMENT_WEIGHT_FACTOR,
    SCORE_MIN,
    SCORE_MAX,
    SUCCESS_THRESHOLD,
    FALLBACK_INTENT,
    UNKNOWN_RESPONSE,
    PERSONALITY_PROFILES,
    RESPONSES,
)


# Skirmish evaluator action.
# Processing flow per turn:
# 1) detect intent and tone,
# 2) score using guard personality weights,
# 3) map score to success/failure response,
# 4) return strict payload for Godot contract.
class ActionEvaluateExcuse(Action):
    # Returns the action name registered in the Rasa domain.
    def name(self) -> Text:
        return "action_evaluate_excuse"

    # Loads runtime helpers and static config, then validates config shape.
    def __init__(self):
        self.analyzer = SentimentIntensityAnalyzer()
        self.PERSONALITY_PROFILES = PERSONALITY_PROFILES
        self.RESPONSES = RESPONSES
        self._validate_config()

    # Validates static skirmish config to fail fast on malformed data.
    def _validate_config(self) -> None:
        # Fail fast on malformed static data so runtime scoring stays deterministic.
        if DEFAULT_GUARD_NAME not in self.PERSONALITY_PROFILES:
            raise RuntimeError("Skirmish config error: DEFAULT_GUARD_NAME not found in PERSONALITY_PROFILES.")
        if DEFAULT_GUARD_NAME not in self.RESPONSES:
            raise RuntimeError("Skirmish config error: DEFAULT_GUARD_NAME not found in RESPONSES.")
        for guard_name, profile in self.PERSONALITY_PROFILES.items():
            if "intent_weights" not in profile or not isinstance(profile["intent_weights"], dict):
                raise RuntimeError(f"Skirmish config error: '{guard_name}' missing intent_weights.")
            if "sentiment_direction" not in profile or not isinstance(profile["sentiment_direction"], (int, float)):
                raise RuntimeError(f"Skirmish config error: '{guard_name}' missing sentiment_direction.")
        for guard_name, responses in self.RESPONSES.items():
            if FALLBACK_INTENT not in responses:
                raise RuntimeError(f"Skirmish config error: '{guard_name}' missing fallback intent '{FALLBACK_INTENT}'.")

    # Executes one guard skirmish turn and emits a strict Godot payload.
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:

        # Guard identity drives both intent weights and response voice.
        guard_name = tracker.get_slot("guard_name")
        if not guard_name:
            guard_name = DEFAULT_GUARD_NAME
        
        # Parse NLU output for semantic intent and confidence.
        user_text = tracker.latest_message.get('text', "")
        intent_data = tracker.latest_message.get('intent', {})
        last_intent = intent_data.get('name') if intent_data else "unknown"
        intent_confidence = intent_data.get('confidence', 0.0)

        # Sentiment contributes to persuasion strength via profile direction.
        sentiment = self.analyzer.polarity_scores(user_text)
        raw_tone = sentiment['compound']

        # Unknown guards intentionally fall back to default profile.
        profile = self.PERSONALITY_PROFILES.get(guard_name.lower(), self.PERSONALITY_PROFILES["rosanna"])
        
        # Intent score captures tactic fit; sentiment impact captures delivery tone.
        intent_score = profile["intent_weights"].get(last_intent, 0.0)
        sentiment_impact = raw_tone * profile["sentiment_direction"]
        
        # Weighted blend stays normalized to a fixed gameplay range.
        final_score = (intent_score * INTENT_WEIGHT_FACTOR) + (sentiment_impact * SENTIMENT_WEIGHT_FACTOR)
        final_score = max(SCORE_MIN, min(SCORE_MAX, final_score))
        
        # Single threshold defines pass/fail outcome for dialogue branch selection.
        success = final_score > SUCCESS_THRESHOLD
        
        # Fallback chain: guard -> fallback intent -> unknown response.
        guard_responses = self.RESPONSES.get(guard_name.lower(), self.RESPONSES[DEFAULT_GUARD_NAME])
        intent_responses = guard_responses.get(last_intent, guard_responses.get(FALLBACK_INTENT))
        response_text = intent_responses.get(success, UNKNOWN_RESPONSE)

        # NLU fallback always returns explicit confusion feedback.
        if last_intent == "nlu_fallback":
            response_text = f"({guard_name.capitalize()} looks confused.) I have no idea what you are saying."

        self._log(
            guard_name,
            user_text,
            last_intent,
            intent_confidence,
            raw_tone,
            intent_score,
            sentiment_impact,
            final_score,
            success,
        )

        # Output payload is consumed by Godot as a strict contract.
        custom_data = {
            "sympathy_score": round(final_score, 2),
            "detected_intent": last_intent,
            "guard_name": guard_name
        }
        self._validate_output_contract(response_text, custom_data)

        dispatcher.utter_message(
            text=response_text,
            json_message=custom_data
        )
        return []

    # Prints a compact debug trace for one skirmish evaluation.
    @staticmethod
    def _log(guard_name: str, user_text: str, last_intent: str, intent_confidence: float,
             raw_tone: float, intent_score: float, sentiment_impact: float,
             final_score: float, success: bool) -> None:
        print("\n" + "=" * 50)
        print("SKIRMISH ANALYSIS")
        print("=" * 50)
        print(f"Guard:       {guard_name}")
        print(f"Input:      '{user_text}'")
        print(f"Intent:      {last_intent} (Confidence: {intent_confidence:.2f})")
        print(f"Tone:        {raw_tone:.2f}")
        print(
            f"Score Calc:  [Intent: {intent_score}] * {INTENT_WEIGHT_FACTOR} "
            f"+ [Tone: {sentiment_impact:.2f}] * {SENTIMENT_WEIGHT_FACTOR}"
        )
        print(f"Final Score: {final_score:.2f}")
        print(f"Outcome:     {'SUCCESS' if success else 'FAILURE'}")
        print("=" * 50 + "\n")

    # Validates response text and custom payload before dispatch to Godot.
    @staticmethod
    def _validate_output_contract(response_text: Text, custom_data: Dict[Text, Any]) -> None:
        # Contract mirrors Godot-side validators; raise immediately on drift.
        if not isinstance(response_text, str) or response_text == "":
            raise ValueError("Skirmish output contract violation: 'text' must be a non-empty string.")

        if not isinstance(custom_data, dict):
            raise ValueError("Skirmish output contract violation: 'custom' must be a dictionary.")

        sympathy_score = custom_data.get("sympathy_score")
        if not isinstance(sympathy_score, (int, float)):
            raise ValueError("Skirmish output contract violation: 'sympathy_score' must be numeric.")

        detected_intent = custom_data.get("detected_intent")
        if not isinstance(detected_intent, str) or detected_intent == "":
            raise ValueError("Skirmish output contract violation: 'detected_intent' must be a non-empty string.")

        guard_name = custom_data.get("guard_name")
        if not isinstance(guard_name, str) or guard_name == "":
            raise ValueError("Skirmish output contract violation: 'guard_name' must be a non-empty string.")