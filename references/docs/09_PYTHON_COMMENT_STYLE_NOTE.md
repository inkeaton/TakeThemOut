# 09 — Python Comment Style Note (Rasa Actions)

Use this brief style for chatbot Python scripts in `tongue/**/actions/`.

## Goal
- Keep comments short, professional, and useful for balancing/debugging.
- Explain processing, scoring, and contracts — not obvious syntax.

## Rules
- Use **one short module header** (role + turn-processing flow).
- Add **function-level comments/docstrings** only for non-trivial logic.
- Prefer **why/how** comments over step-by-step narration.
- Keep comments stable under tuning changes (avoid hardcoded story text in comments).

## Always Comment
- Score pipelines and transforms (intent weight, tone effect, clamps, thresholds).
- State-dependent modifiers (phase bands, suspicion/ease pressure).
- Outcome gates (`success`, `fail`, special event conditions).
- Output payload contracts consumed by Godot (`text`, `custom`, required keys).

## Gameplay Notes
When editing data tables (`data_skirmish.py`, `data_date.py`), include short notes on gameplay intent:
- what each intent is expected to do,
- how phase/state changes that behavior,
- what makes an action risky/safe,
- what thresholds represent in player-facing terms.

## Avoid
- Repeating obvious code (“get value from dict”).
- Long narrative comments in hot paths.
- Comments that duplicate constant names without extra meaning.
