from typing import Any, Text, Dict, List
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SlotSet
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
from .data_date import (
    DEFAULT_DATE_PROFILE,
    TRUST_PHASES,
    RESPONSES,
    ASK_SUCCESS_TEXT,
    WIN_TRUST,
    WIN_SUS_CAP,
    LOSS_SUS,
    FALLBACK_RESPONSE,
)


# Date evaluator action.
# Processing flow per turn:
# 1) detect intent and sentiment,
# 2) compute ease/suspicion deltas from phase (+ optional tone effect),
# 3) resolve win/fail gating,
# 4) emit strict payload consumed by Godot HUD/event logic.
class ActionEvaluateDate(Action):
    # Returns the action name used by Rasa in domain/rules.
    def name(self) -> Text:
        return "action_evaluate_date"

    # Loads static config/constants and validates them once at startup.
    def __init__(self):
        self.analyzer = SentimentIntensityAnalyzer()
        self.PROFILE = DEFAULT_DATE_PROFILE
        self.TRUST_PHASES = TRUST_PHASES
        self.RESPONSES = RESPONSES
        self.ASK_SUCCESS_TEXT = ASK_SUCCESS_TEXT
        self.WIN_TRUST = WIN_TRUST
        self.WIN_SUS_CAP = WIN_SUS_CAP
        self.LOSS_SUS = LOSS_SUS
        self.FALLBACK_RESPONSE = FALLBACK_RESPONSE
        self._validate_config()

    # Ensures required config sections and phase tables exist before runtime.
    def _validate_config(self) -> None:
        # Validate static data once at startup to avoid runtime config drift.
        if "intent_phase_effects" not in self.PROFILE:
            raise RuntimeError("Date config error: missing 'intent_phase_effects' in profile.")
        for intent in ["compliment", "curiosity", "talking_about_myself", "toxicity", "ask_objective"]:
            if intent not in self.PROFILE["intent_phase_effects"]:
                raise RuntimeError(f"Date config error: missing intent profile for '{intent}'.")
            for phase in ["cold", "warm", "close"]:
                if phase not in self.PROFILE["intent_phase_effects"][intent]:
                    raise RuntimeError(f"Date config error: intent '{intent}' missing phase '{phase}'.")
        if "tone" not in self.PROFILE or "trust_scale" not in self.PROFILE["tone"]:
            raise RuntimeError("Date config error: missing tone config.")
        for phase in ["cold", "warm", "close"]:
            if phase not in self.TRUST_PHASES:
                raise RuntimeError(f"Date config error: missing trust phase '{phase}'.")

    # Runs one Date turn: score update, outcome resolution, payload emission.
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:

        # Input from the latest user turn and NLU classification.
        user_text = tracker.latest_message.get("text", "")
        intent_data = tracker.latest_message.get("intent", {})
        last_intent = intent_data.get("name", "unknown")
        intent_confidence = intent_data.get("confidence", 0.0)

        # Tone score modulates trust for selected social intents.
        sentiment = self.analyzer.polarity_scores(user_text)
        tone_score = sentiment["compound"]

        # Persistent state carried in slots across turns.
        trust_slot = tracker.get_slot("ease_score")
        suspicion_slot = tracker.get_slot("suspicion_score")
        # this avoids the 0.0 = None bug
        trust = 20.0 if trust_slot is None else float(trust_slot)
        suspicion = 0.0 if suspicion_slot is None else float(suspicion_slot)
        start_trust = trust
        start_sus = suspicion

        d_trust, d_sus, phase_name = self._compute_deltas(
            last_intent, trust, tone_score
        )

        # Clamp scores to gameplay-safe bounds before resolving outcomes.
        trust = self._clamp(trust + d_trust, 0, 100)
        suspicion = self._clamp(suspicion + d_sus, 0, 100)

        response_text, game_event = self._resolve_outcome(
            last_intent,
            trust,
            suspicion,
            d_trust,
            phase_name,
        )

        if game_event == "date_success":
            trust = 100
        elif game_event == "date_failed":
            suspicion = 100

        self._log(
            user_text,
            last_intent,
            intent_confidence,
            tone_score,
            start_trust,
            trust,
            d_trust,
            start_sus,
            suspicion,
            d_sus,
            phase_name,
            game_event,
        )

        # Godot Payload
        custom_data = {
            "ease_score": trust,
            "suspicion_score": suspicion,
            "delta_suspicion": d_sus,
            "detected_intent": last_intent,
        }
        if game_event:
            custom_data["game_event"] = game_event
            if game_event == "date_success":
                custom_data["secret_info"] = "Luca"

        self._validate_output_contract(response_text, custom_data)

        dispatcher.utter_message(text=response_text, json_message=custom_data)
        return [SlotSet("ease_score", trust), SlotSet("suspicion_score", suspicion)]

    # Maps current trust/ease to the active relationship phase.
    def _phase_for_trust(self, trust: float) -> str:
        # Relationship phase is derived from current ease/trust.
        if trust < self.TRUST_PHASES["cold"]["max"]:
            return "cold"
        if trust < self.TRUST_PHASES["warm"]["max"]:
            return "warm"
        return "close"

    # Computes trust/suspicion deltas from phase profile plus tone effect.
    def _compute_deltas(self, intent: str, trust: float, tone: float):
        # Base effect: intent table indexed by current phase.
        phase_name = self._phase_for_trust(trust)
        phase_effect = self.PROFILE["intent_phase_effects"].get(intent, {}).get(
            phase_name,
            {"trust": 0.0, "suspicion": 0.0},
        )

        d_trust = float(phase_effect["trust"])
        d_sus = float(phase_effect["suspicion"])

        # Tone only affects configured social intents.
        tone_cfg = self.PROFILE["tone"]
        if intent in tone_cfg.get("enabled_intents", []):
            d_trust += tone * float(tone_cfg["trust_scale"])

        return d_trust, d_sus, phase_name

    # Resolves response text and optional end-state event for this turn.
    def _resolve_outcome(self, intent: str, trust: float, sus: float,
                         d_trust: float, phase_name: str):
        # Objective ask can directly trigger mission success if trust/suspicion gate passes.
        if intent == "ask_objective":
            if trust >= self.WIN_TRUST and sus < self.WIN_SUS_CAP:
                return self.ASK_SUCCESS_TEXT, "date_success"

        # Global fail condition: suspicion overflow.
        if sus >= self.LOSS_SUS:
            return "You're making me really uncomfortable. I'm leaving.", "date_failed"

        intent_responses = self.RESPONSES.get(intent, {})

        # Response tone bucket follows turn quality only.
        if d_trust >= 10.0:
            tone_key = "good"
        elif d_trust <= -10.0:
            tone_key = "bad"
        else:
            tone_key = "neutral"

        text = intent_responses.get(tone_key, self.FALLBACK_RESPONSE)
        if phase_name == "cold" and tone_key == "good" and intent == "talking_about_myself":
            text = "You're opening up quickly... but I appreciate it."

        if intent == "nlu_fallback":
            text = "(Eugenia looks confused.) I have no idea what you mean."

        return text, None

    # Clamps a numeric value to an inclusive range.
    @staticmethod
    def _clamp(value: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, value))

    # Prints a compact debug trace for one Date turn.
    @staticmethod
    def _log(user_text, intent, confidence, tone,
             start_trust, trust, d_trust, start_sus, sus, d_sus,
             phase_name, game_event):
        print("\n" + "=" * 50)
        print("  DATING ANALYSIS")
        print("=" * 50)
        print(f"Input:     '{user_text}'")
        print(f"Intent:     {intent} (Confidence: {confidence:.2f})")
        print(f"Tone:       {tone:.2f}")
        print(f"Trust:      {start_trust:.1f} -> {trust:.1f} (Delta: {d_trust:+.1f})")
        print(f"Suspicion:  {start_sus:.1f} -> {sus:.1f} (Delta: {d_sus:+.1f})")
        if phase_name:
            print(f"Phase:      {phase_name}")
        if game_event:
            print(f"Outcome:    EVENT -> {game_event}")
        print("=" * 50 + "\n")

    # Validates action output contract before sending payload to Godot.
    @staticmethod
    def _validate_output_contract(response_text: Text, custom_data: Dict[Text, Any]) -> None:
        # Keep producer-side checks aligned with Godot consumer-side validators.
        if not isinstance(response_text, str) or response_text == "":
            raise ValueError("Date output contract violation: 'text' must be a non-empty string.")

        if not isinstance(custom_data, dict):
            raise ValueError("Date output contract violation: 'custom' must be a dictionary.")

        for key in ["ease_score", "suspicion_score", "delta_suspicion"]:
            if not isinstance(custom_data.get(key), (int, float)):
                raise ValueError(f"Date output contract violation: '{key}' must be numeric.")

        detected_intent = custom_data.get("detected_intent")
        if not isinstance(detected_intent, str) or detected_intent == "":
            raise ValueError("Date output contract violation: 'detected_intent' must be a non-empty string.")

        game_event = custom_data.get("game_event")
        if game_event is not None:
            if not isinstance(game_event, str):
                raise ValueError("Date output contract violation: 'game_event' must be a string when present.")
            if game_event not in ["date_success", "date_failed"]:
                raise ValueError("Date output contract violation: 'game_event' must be 'date_success' or 'date_failed'.")

        if game_event == "date_success":
            secret_info = custom_data.get("secret_info")
            if not isinstance(secret_info, str) or secret_info == "":
                raise ValueError("Date output contract violation: 'secret_info' must be a non-empty string for 'date_success'.")