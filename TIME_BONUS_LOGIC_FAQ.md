# Time Bonus Logic FAQ (Planned Unified Design)

This document captures the planned scoring policy to finalize before full code rollout.

## Product Intent

- The app should allow over-completion (unlike many apps), especially for timer/time tracking.
- Over-completion must always be diminishing to avoid one-activity domination.
- Binary tracking remains completion-centric (done vs not done), with no binary over-completion percentage.
- Quantity tracking is unaffected by this time-bonus design.

## Global Principle

All over-completion uses diminishing returns.

- Diminishing ratio per additional block: `0.7`
- Full blocks only for bonus steps (partial block does not trigger the next bonus step)
- Rounded values may be shown in UI, but computation uses full precision

## Bonus ON (Effort Mode): 30-Minute Block System

When `timeBonusEnabled = true`, both binary and time tracking use 30-minute block logic.

### Shared Definitions

- `targetMinutes`: planned/estimated duration
- `loggedMinutes`: actual logged duration
- `baseSpanMinutes = min(targetMinutes, 30)`
- `bonus(excessMinutes) = sum(0.7^i) for i = 1..floor(excessMinutes / 30)`

### Score Curve Used in ON Mode

For any duration `m` with target context `targetMinutes`:

- if `m <= baseSpanMinutes`: `score = (m / baseSpanMinutes) * priority`
- if `m > baseSpanMinutes`: `score = priority + priority * bonus(m - baseSpanMinutes)`

This curve makes all provided examples consistent.

## Binary (Bonus ON)

Binary is completion-first, no over-completion percentage.

### Broad Rules

- Target is represented in 30-minute block logic.
- If binary item is completed and `loggedMinutes <= targetMinutes`:
  - full completion is awarded at target score
- If binary item is completed and `loggedMinutes > targetMinutes`:
  - earned is revised upward using logged time
  - target is revised upward in lockstep (same value) to prevent >100% binary completion
- Interpretation: extra time on binary indicates initial estimate was low; reward extra effort, but keep completion capped.

### Binary Examples (priority = 1)

- Target `20m`, completed in `10m`:
  - target `1.0`, earned `1.0`
- Target `20m`, completed in `30m`:
  - target `1.0`, earned `1.0` (next 30-min bonus step not crossed)
- Target `60m`, completed in `30m`:
  - target `1.7`, earned `1.7`
- Target `60m`, completed in `120m`:
  - target `2.55` (rounded), earned `2.55` (rounded)

## Time / Timer-Type (Bonus ON)

Time completion depends on logged duration through the same ON-mode curve.

### Broad Rules

- Target uses 30-minute block logic.
- Earned follows logged-time progression on the same curve.
- Over-completion is allowed and diminishing.

### Time Examples (priority = 1)

- Target `60m` (target score `1.7`), logged `30m` -> earned `1.0`
- Target `30m` (target score `1.0`), logged `15m` -> earned `0.5`
- Target `20m` (target score `1.0`), logged `10m` -> earned `0.5`
- Target `20m` (target score `1.0`), logged `15m` -> earned `0.75`
- Target `60m` (target score `1.7`), logged `120m` -> earned `2.55` (rounded)

## Bonus OFF (Goal Mode)

Planned rule remains:

- Over-completion is still diminishing.
- Diminishing block size = the activity's own target duration.

Examples (priority = 1):

- `20m` target: `20m -> 1.0`, `40m -> 1.7`, `60m -> 2.19`
- `60m` target: `60m -> 1.0`, `120m -> 1.7`

## One-Off Forced Binary Manual Time Logs (Planned)

To avoid special-case behavior, one-off manual binary logs follow the same binary rules by mode:

- Bonus OFF:
  - completion-based scoring (`earned = priority` when completed)
  - practical target stays completion-style (`target = priority`)
- Bonus ON:
  - use the same 30-minute block scoring logic as other binary items
  - for completed items, keep binary capped by setting `earned` and `target` in lockstep from logged time
  - for incomplete items, `earned = 0`

## Clarification on Consistency

Your examples are consistent with one explicit clarification:

- For Bonus ON, use `baseSpanMinutes = min(targetMinutes, 30)` before applying 30-minute bonus blocks.

Without that clarification, cases like `20m target, 10m logged = 0.5` and `60m target, 30m logged = 1.0` conflict under a single naive formula.

## Implementation Note

This FAQ is the agreed plan/spec. Code alignment can proceed against this document.

## V1 Risk Posture

For v1:

- no explicit cap on manual one-off log duration
- rely on diminishing returns to limit benefit from very long single logs

Known risk to monitor:

- users creating many tiny manual logs (for example a few seconds each) to repeatedly collect base completion points

If gaming is observed in production, we can add guardrails in the next iteration.
