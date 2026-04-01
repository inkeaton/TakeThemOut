# 08 — GDScript Comment Style Guide

This guide defines a unified comment style for all in-scope GDScript files.

## Scope

- Included: `bodies/**`, `stages/**`, `libraries/**`
- Excluded (Option A): `addons/**` (third-party/plugin-owned style preserved)
- Rule: comment/documentation cleanup only; no behavior changes

## Goals

1. Keep the same (or better) information density.
2. Make comment structure predictable across files.
3. Clarify intent, assumptions, and side effects.
4. Reduce noise from redundant comments.

---

## 1) Mandatory top-of-file header

Every `.gd` file must start with a compact `##` header block:

```gdscript
## <ScriptName>: <one-line role summary>
## Role: <autoload|scene-controller|npc-body|state|utility>
## Responsibilities:
## - <primary responsibility>
## - <primary responsibility>
## Dependencies:
## - <autoloads / node contracts / message protocols>
```

Notes:
- Keep to 5–8 lines where possible.
- Use present tense.
- Be concrete (avoid generic phrases like “handles logic”).

---

## 2) Section headers

Use standardized section separators for medium/large files:

```gdscript
# --- Configuration ---
# --- Signals ---
# --- State ---
# --- Nodes ---
# --- Lifecycle ---
# --- Core Logic ---
# --- Helpers ---
```

Rules:
- Use `Title Case`.
- Keep one concept per section.
- Avoid mixing lifecycle, protocol, and utility helpers in the same section when possible.

---

## 3) Function documentation (`##`)

Document public callbacks, protocol handlers, and non-trivial helpers with `##`:

```gdscript
## Sends navigation status updates to the mind bridge.
## Side effects: Emits JSON messages through `VesnaManager`.
func send_navigation_update(status: String, waypoint_name: String):
```

Rules:
- First line: what the function does.
- Optional second line: side effects / assumptions / contracts.
- Keep short and technical.

---

## 4) Inline comments

Allowed uses:
- Explain intent/rationale that is not obvious from code.
- Clarify protocol schema, state-machine transitions, or edge-case behavior.

Avoid:
- Restating literal code (“increment i by 1”).
- Outdated `FIX` notes once stable.
- Long narrative blocks in hot paths.

---

## 5) Language and tone

- Use neutral technical English.
- Prefer present tense and active voice.
- Keep naming consistent with project vocabulary:
  - `mind`, `body`, `state`, `transition`, `patrol`, `captain`, `sentry`, `alert`, `messenger`.

---

## 6) Information preservation rule

When normalizing comments:
- Do not delete meaningful operational context.
- Preserve protocol details (payload keys, event names, state assumptions).
- If shortening wording, keep equivalent semantics.