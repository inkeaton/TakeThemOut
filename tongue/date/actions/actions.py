from typing import Any, Text, Dict, List
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SlotSet
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer


class ActionEvaluateDate(Action):
    def name(self) -> Text:
        return "action_evaluate_date"

    def __init__(self):
        self.analyzer = SentimentIntensityAnalyzer()

        # --- SCORING DATA ---
        # Fallback base deltas per intent: (d_trust, d_suspicion)
        # Rarely reached — dynamic rules cover most game states.
        self.INTENT_SCORES = {
            "compliment":           (  5,   0),
            "curiosity":            (  3,  -2),
            "talking_about_myself": (  0,   3),
            "toxicity":             (-25,  20),
        }

        # --- DYNAMIC RULES ---
        # Each entry: list of (rule_name, condition_fn, d_trust, d_sus, modifier_msg).
        # First matching condition wins; if none match, INTENT_SCORES + tone blend.
        # Rules are ordered by specificity — most restrictive conditions first.
        self.DYNAMIC_RULES = {
            # ── COMPLIMENT ──────────────────────────────────────────
            # C1 – Sarcastic: negative tone flips the compliment
            # C2 – Under pressure: sus is high, she reads it as manipulation
            # C3 – Cold open: too early, feels forced
            # C4 – Diminishing returns: already high trust, flattery is old
            # C5 – Sweet spot: mid-trust, compliments land best
            # C6 – Early game: building rapport, moderate gain
            "compliment": [
                ("C1_sarcastic",
                 lambda t, s, tone: tone < -0.1,
                 -10, 10, "(She frowns at your tone.)"),
                ("C2_under_pressure",
                 lambda t, s, tone: s >= 50,
                 -5, 10, "(She narrows her eyes — are you buttering her up?)"),
                ("C3_cold_open",
                 lambda t, s, tone: t < 20,
                 5, 3, "(She smiles politely, but you're still a stranger.)"),
                ("C4_diminishing_returns",
                 lambda t, s, tone: t >= 65,
                 3, 2, "(She blushes, but flattery is getting old.)"),
                ("C5_sweet_spot",
                 lambda t, s, tone: 35 <= t < 65,
                 10, -2, "(Her eyes light up — she loves it.)"),
                ("C6_early_game",
                 lambda t, s, tone: 20 <= t < 35,
                 8, 0, "(She seems genuinely flattered.)"),
            ],
            # ── CURIOSITY ───────────────────────────────────────────
            # Q1 – Interrogation: high suspicion makes questions feel like grilling
            # Q2 – Warm opener: early + positive tone, best way to start
            # Q3 – Safe opener: early game, neutral/negative tone
            # Q4 – Reciprocity: high trust, she wants to know you too
            # Q5 – Engaged: mid-trust + warm tone, great for building rapport
            # Q6 – Standard: mid-trust, baseline curiosity
            "curiosity": [
                ("Q1_interrogation",
                 lambda t, s, tone: s >= 50,
                 2, 8, "(She tenses — this feels like an interrogation.)"),
                ("Q2_warm_opener",
                 lambda t, s, tone: t < 20 and tone > 0.2,
                 8, -3, "(She opens up — you seem genuinely interested.)"),
                ("Q3_safe_opener",
                 lambda t, s, tone: t < 20,
                 5, -2, "(She answers cautiously.)"),
                ("Q4_reciprocity",
                 lambda t, s, tone: t >= 65,
                 3, 3, "(She answers, but asks — why do you want to know?)"),
                ("Q5_engaged",
                 lambda t, s, tone: 35 <= t < 65 and tone > 0.2,
                 8, -5, "(She's enjoying the conversation.)"),
                ("Q6_standard",
                 lambda t, s, tone: 35 <= t < 65,
                 5, -4, "(She answers thoughtfully.)"),
            ],
            # ── TALKING ABOUT MYSELF ────────────────────────────────
            # T1 – Desperate: high sus + low trust, oversharing reeks of manipulation
            # T2 – Conflicted: high sus + decent trust, she's torn
            # T3 – Too soon: very low trust, she doesn't care about your life yet
            # T4 – Cautious warmth: low-mid trust + positive tone, she's warming up
            # T5 – Premature: low-mid trust, neutral/negative, mild backfire
            # T6 – Perfect timing: mid-trust + warm tone, vulnerability hits right
            # T7 – Solid: mid-trust, decent gain
            # T8 – Deep connection: high trust + warm tone, maximum intimacy
            # T9 – Late game: high trust, she likes hearing about you
            "talking_about_myself": [
                ("T1_desperate",
                 lambda t, s, tone: s >= 50 and t < 40,
                 -5, 12, "(She looks uncomfortable — why are you telling her this?)"),
                ("T2_conflicted",
                 lambda t, s, tone: s >= 50 and t >= 40,
                 5, 5, "(She listens, but something feels off.)"),
                ("T3_too_soon",
                 lambda t, s, tone: t < 25,
                 -5, 8, "(She nods awkwardly — she barely knows you.)"),
                ("T4_cautious_warmth",
                 lambda t, s, tone: 25 <= t < 40 and tone > 0.1,
                 5, 2, "(She seems interested, but guarded.)"),
                ("T5_premature",
                 lambda t, s, tone: 25 <= t < 40,
                 -2, 5, "(She shifts in her seat — too much, too soon.)"),
                ("T6_perfect_timing",
                 lambda t, s, tone: 40 <= t < 65 and tone > 0.1,
                 12, -5, "(She leans in — she feels a real connection.)"),
                ("T7_solid",
                 lambda t, s, tone: 40 <= t < 65,
                 8, -2, "(She listens intently.)"),
                ("T8_deep_connection",
                 lambda t, s, tone: t >= 65 and tone > 0.1,
                 15, -8, "(She looks moved — you really trust her.)"),
                ("T9_late_game",
                 lambda t, s, tone: t >= 65,
                 10, -3, "(She appreciates your openness.)"),
            ],
            # ── TOXICITY ────────────────────────────────────────────
            # X1 – Betrayal: high trust makes insults hit much harder
            # X2 – Last straw: high suspicion + insult = she's done
            # X3 – Misclassified: positive tone suggests accidental classification
            # X4 – Rude stranger: early game insult, moderate punishment
            # X5 – Standard: baseline toxicity penalty
            "toxicity": [
                ("X1_betrayal",
                 lambda t, s, tone: t >= 60,
                 -40, 30, "(She looks genuinely hurt — she trusted you.)"),
                ("X2_last_straw",
                 lambda t, s, tone: s >= 60,
                 -20, 25, "(That was the last straw.)"),
                ("X3_misclassified",
                 lambda t, s, tone: tone > 0.1,
                 -15, 10, "(She frowns, unsure what to make of that.)"),
                ("X4_rude_stranger",
                 lambda t, s, tone: t < 20,
                 -15, 15, "(She recoils — who says that to a stranger?)"),
                ("X5_standard",
                 lambda t, s, tone: True,
                 -25, 20, "(She glares at you.)"),
            ],
            # ── ASK OBJECTIVE ───────────────────────────────────────
            # A1 – Success: trust high + suspicion low = she tells the secret
            # A2 – Blown by suspicion: trust is there but she doesn't trust you
            # A3 – Almost there: close, but not enough trust yet
            # A4 – Premature: mid-game ask, notable penalty
            # A5 – Way too early: low trust, harsh penalty
            "ask_objective": [
                ("A1_success",
                 lambda t, s, tone: t >= 80 and s < 30,
                 0, 0, ""),
                ("A2_blown_by_suspicion",
                 lambda t, s, tone: t >= 80 and s >= 30,
                 -5, 15, "(She hesitates — something about you feels off.)"),
                ("A3_almost_there",
                 lambda t, s, tone: t >= 60 and s < 30,
                 -8, 12, "(She considers it, but she's not ready.)"),
                ("A4_premature",
                 lambda t, s, tone: 40 <= t < 60,
                 -10, 15, "(She pulls back — too forward.)"),
                ("A5_way_too_early",
                 lambda t, s, tone: True,
                 -10, 20, "(She stares at you — who asks that to a stranger?)"),
            ],
        }

        # Sentiment blending weight for fallback path
        self.TONE_WEIGHT = 0.35

        # --- RESPONSE DATA ---
        # Maps intent → {modifier_msg: response_text}
        # Falls back to True/False (positive/negative d_trust) for unmatched modifiers.
        self.RESPONSES = {
            "compliment": {
                "(She frowns at your tone.)":
                    "...Was that supposed to be a compliment?",
                "(She narrows her eyes — are you buttering her up?)":
                    "I appreciate the words, but... why now?",
                "(She smiles politely, but you're still a stranger.)":
                    "Oh. Thank you.",
                "(She blushes, but flattery is getting old.)":
                    "You're sweet, but you don't have to keep saying things like that.",
                "(Her eyes light up — she loves it.)":
                    "That's really kind of you to say.",
                "(She seems genuinely flattered.)":
                    "That's sweet of you to say.",
                True:  "That's sweet of you to say.",
                False: "Hmm... thanks, I guess.",
            },
            "curiosity": {
                "(She tenses — this feels like an interrogation.)":
                    "Why do you keep asking me things?",
                "(She opens up — you seem genuinely interested.)":
                    "Oh! Well, since you asked... let me tell you.",
                "(She answers cautiously.)":
                    "I suppose I can tell you that.",
                "(She answers, but asks — why do you want to know?)":
                    "Sure, but... can I ask why you're so curious?",
                "(She's enjoying the conversation.)":
                    "That's a great question, actually!",
                "(She answers thoughtfully.)":
                    "Hmm, let me think... yes, I'd say so.",
                True:  "That's a good question... I'd love to tell you.",
                False: "I'd rather not get into that.",
            },
            "talking_about_myself": {
                "(She looks uncomfortable — why are you telling her this?)":
                    "O-okay... I didn't need to know that.",
                "(She listens, but something feels off.)":
                    "That's... interesting. Go on.",
                "(She nods awkwardly — she barely knows you.)":
                    "Uh... okay? That's a lot to share right away.",
                "(She seems interested, but guarded.)":
                    "Really? Tell me more.",
                "(She shifts in her seat — too much, too soon.)":
                    "I see... maybe we should talk about something else?",
                "(She leans in — she feels a real connection.)":
                    "I feel the same way, actually.",
                "(She listens intently.)":
                    "That's really interesting. I appreciate you sharing.",
                "(She looks moved — you really trust her.)":
                    "That means a lot that you'd tell me that.",
                "(She appreciates your openness.)":
                    "Thank you for being so open with me.",
                True:  "I appreciate you sharing that.",
                False: "Uh... okay? TMI.",
            },
            "toxicity": {
                "(She looks genuinely hurt — she trusted you.)":
                    "I... I thought we were getting along. Why would you say that?",
                "(That was the last straw.)":
                    "I've had enough of this. Don't talk to me like that.",
                "(She frowns, unsure what to make of that.)":
                    "I'm not sure how to take that...",
                "(She recoils — who says that to a stranger?)":
                    "Wow. Okay. That's how you want to start?",
                "(She glares at you.)":
                    "Excuse me? That's incredibly rude.",
                True:  "That's... not okay.",
                False: "Excuse me? That's rude.",
            },
            "ask_objective": {
                "(She hesitates — something about you feels off.)":
                    "I... no. Something about this doesn't feel right.",
                "(She considers it, but she's not ready.)":
                    "I'm not sure I'm ready to tell you that yet.",
                "(She pulls back — too forward.)":
                    "Whoa — that's a pretty big question for right now.",
                "(She stares at you — who asks that to a stranger?)":
                    "I barely know you! Why would I tell you that?",
                True:  "I barely know you! I'm not telling you that.",
                False: "I barely know you! I'm not telling you that.",
            },
        }

        # ask_objective success response (special — not in RESPONSES table)
        self.ASK_SUCCESS_TEXT = (
            "(She leans in, lowering her voice.) "
            "Ok, I can tell you... his real name is 'Luca'."
        )

        # Game-ending thresholds
        self.WIN_TRUST     = 80
        self.WIN_SUS_CAP   = 30
        self.LOSS_SUS      = 80

        # Fallback response for unknown intents
        self.FALLBACK_RESPONSE = "Go on..."

    # --- MAIN LOGIC ---
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:

        # 1. Parse input
        user_text         = tracker.latest_message.get("text", "")
        intent_data       = tracker.latest_message.get("intent", {})
        last_intent       = intent_data.get("name", "unknown")
        intent_confidence = intent_data.get("confidence", 0.0)

        # 2. Sentiment analysis
        sentiment  = self.analyzer.polarity_scores(user_text)
        tone_score = sentiment["compound"]

        # 3. Current state
        trust     = tracker.get_slot("ease_score") or 20.0
        suspicion = tracker.get_slot("suspicion_score") or 0.0
        start_trust = trust
        start_sus   = suspicion

        # 4. Score the turn (dynamic rules → static fallback → tone blend)
        d_trust, d_sus, modifier_msg, rule_name = self._compute_deltas(
            last_intent, trust, suspicion, tone_score
        )

        # 5. Apply deltas
        trust     = self._clamp(trust + d_trust, 0, 100)
        suspicion = self._clamp(suspicion + d_sus, 0, 100)

        # 6. Determine response and game events
        response_text, game_event = self._resolve_outcome(
            last_intent, trust, suspicion, d_trust, modifier_msg
        )

        # 7. Clamp to extremes on game-ending events
        if game_event == "date_success":
            trust = 100
        elif game_event == "date_failed":
            suspicion = 100

        # 8. Log results (includes rule name)
        self._log(user_text, last_intent, intent_confidence, tone_score,
                  start_trust, trust, d_trust, start_sus, suspicion, d_sus,
                  modifier_msg, rule_name, game_event)

        # 9. Build and send response
        custom_data = {
            "ease_score":       trust,
            "suspicion_score":  suspicion,
            "delta_suspicion":  d_sus,
            "detected_intent":  last_intent,
        }
        if game_event:
            custom_data["game_event"] = game_event
            if game_event == "date_success":
                custom_data["secret_info"] = "Luca"

        dispatcher.utter_message(text=response_text, json_message=custom_data)

        return [SlotSet("ease_score", trust), SlotSet("suspicion_score", suspicion)]

    # --- SCORING ---
    def _compute_deltas(self, intent: str, trust: float, sus: float, tone: float):
        """Compute (d_trust, d_sus, modifier_msg, rule_name) for an intent.
        Returns a 4-tuple. rule_name is the ID of the matched dynamic rule,
        or 'fallback' if static scores were used."""
        modifier_msg = ""

        # Check dynamic rules (state-dependent, first match wins)
        if intent in self.DYNAMIC_RULES:
            for rule_id, condition_fn, dt, ds, msg in self.DYNAMIC_RULES[intent]:
                if condition_fn(trust, sus, tone):
                    return (dt, ds, msg, rule_id)

        # Fall back to static intent scores + tone blending
        base_trust, base_sus = self.INTENT_SCORES.get(intent, (0, 0))

        # Blend sentiment: positive tone amplifies trust gain, negative dampens
        tone_bonus = tone * self.TONE_WEIGHT * 10  # scale to ±3.5 range
        d_trust = base_trust + tone_bonus
        d_sus   = base_sus

        return (d_trust, d_sus, modifier_msg, "fallback")

    # --- OUTCOME RESOLUTION ---
    def _resolve_outcome(self, intent: str, trust: float, sus: float,
                         d_trust: float, modifier_msg: str):
        """Determine response text and optional game event."""

        # 1. ask_objective — win check via A1 rule (already applied d_trust/d_sus)
        if intent == "ask_objective":
            if trust >= self.WIN_TRUST and sus < self.WIN_SUS_CAP:
                return (self.ASK_SUCCESS_TEXT, "date_success")
            # For failed asks, the dynamic rule already set modifier_msg + penalties

        # 2. Loss condition — suspicion overflow
        if sus >= self.LOSS_SUS:
            return ("You're making me really uncomfortable. I'm leaving.",
                    "date_failed")

        # 3. Look up response by modifier (dynamic rule message)
        intent_responses = self.RESPONSES.get(intent)
        if intent_responses and modifier_msg in intent_responses:
            text = intent_responses[modifier_msg]
        elif intent_responses:
            # Fall back to success/failure key
            success = d_trust > 0
            text = intent_responses.get(success, self.FALLBACK_RESPONSE)
        else:
            text = self.FALLBACK_RESPONSE

        # Prepend modifier for flavour (only if response wasn't already matched)
        if modifier_msg and modifier_msg not in (self.RESPONSES.get(intent) or {}):
            text = modifier_msg + " " + text

        # NLU fallback override
        if intent == "nlu_fallback":
            text = "(Eugenia looks confused.) I have no idea what you mean."

        return (text, None)

    # --- UTILS ---
    @staticmethod
    def _clamp(value: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, value))

    @staticmethod
    def _log(user_text, intent, confidence, tone,
             start_trust, trust, d_trust, start_sus, sus, d_sus,
             modifier, rule_name, game_event):
        print("\n" + "=" * 50)
        print("  DATING ANALYSIS")
        print("=" * 50)
        print(f"Input:     '{user_text}'")
        print(f"Intent:     {intent} (Confidence: {confidence:.2f})")
        print(f"Tone:       {tone:.2f}")
        print(f"Rule:       {rule_name}")
        print(f"Trust:      {start_trust:.1f} -> {trust:.1f} (Delta: {d_trust:+.1f})")
        print(f"Suspicion:  {start_sus:.1f} -> {sus:.1f} (Delta: {d_sus:+.1f})")
        if modifier:
            print(f"Modifier:   {modifier}")
        if game_event:
            print(f"Outcome:    EVENT -> {game_event}")
        print("=" * 50 + "\n")