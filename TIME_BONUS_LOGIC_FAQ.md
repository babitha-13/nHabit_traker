# Time Bonus Logic FAQ (Developer)

This document explains the current scoring behavior in code for time bonus (Effort Mode), including task vs habit differences and edge cases.

## Source of Truth (Code)

- `lib/features/Progress/Point_system_helper/points_service.dart`
- `lib/features/Progress/Point_system_helper/binary_time_bonus_helper.dart`
- `lib/features/Shared/Points_and_Scores/daily_points_calculator.dart`
- `lib/services/Activtity/task_instance_service/task_instance_time_logging_service.dart`
- `lib/services/app_state.dart` (`timeBonusEnabled`)

## Quick Terms

- `priority` = point weight (usually 1, 2, 3...)
- `timeBonusEnabled`:
  - `false` = Goal mode
  - `true` = Effort mode
- Bonus block size = `30 minutes`
- Diminishing ratio = `0.7`

## Core Bonus Formula

For extra time:

`bonus = priority * sum(0.7^i) for i = 1..N`

Where:

- `N = floor(excessMinutes / 30)`
- only full 30-minute excess blocks count

Examples of bonus multiplier (priority = 1):

- 0 full blocks: `+0.0`
- 1 full block (30-59 extra min): `+0.7`
- 2 full blocks (60-89 extra min): `+1.19`
- 3 full blocks (90-119 extra min): `+1.533`

## 1) Binary Tracking

### Binary Earned Points

- Base earned:
  - usually `priority` when completed
  - if binary counter is used: `(count / target) * priority`
- In Effort mode (`timeBonusEnabled = true`), if time exists:
  - baseline = `templateTimeEstimateMinutes` if set and `> 0`, else `30`
  - extra bonus uses the diminishing formula above

### Binary Target Points (Important Task vs Habit Difference)

- Binary task targets are adjusted by the same bonus amount:
  - `taskTarget += priority + binaryTimeBonusAdjustment`
  - effect: a task can stay around `100%` even when extra time increases earned
- Binary habit targets are not adjusted for this bonus path:
  - effect: extra time becomes over-completion (`>100%`)

### Binary Special Case: Forced-Binary One-Off Manual Time Logs

For one-off manual logs forced to binary, time is stored for calendar display but excluded from points:

- `templateTarget` is forced to `1`
- `disableTimeScoringForPoints = true`
- result: completion-based points only (no time bonus)

This is set in:

- `lib/services/Activtity/task_instance_service/task_instance_time_logging_service.dart`

### Binary Examples (priority = 1)

1. Estimate `30m`, logged `30m`, completed
- Bonus OFF: earned `1.0`
- Bonus ON:
  - Task: earned `1.0`, target `1.0` -> `100%`
  - Habit: earned `1.0`, target `1.0` -> `100%`

2. Estimate `30m`, logged `60m`, completed
- Excess = `30m` -> bonus `+0.7`
- Bonus OFF: earned `1.0`
- Bonus ON:
  - Task: earned `1.7`, target `1.7` -> `100%`
  - Habit: earned `1.7`, target `1.0` -> `170%`

3. Estimate `120m`, logged `140m`, completed
- Excess = `20m` -> no full 30m block -> bonus `+0.0`
- Bonus OFF: earned `1.0`
- Bonus ON: earned still `1.0` (bonus does not kick in yet)

## 2) Quantitative Tracking

### Quantitative Earned Points

- Main formula: `(currentValue / target) * priority`
- Over-completion is allowed (`>1.0` ratio)
- For windowed habits, code may use differential contribution (`todayContribution`) instead of total

### Quantitative and Time Bonus

- No separate time bonus path is applied
- Bonus ON vs OFF: same quantitative formula

### Quantitative Examples (priority = 1)

1. Target `8`, current `4`
- Bonus OFF: `0.5`
- Bonus ON: `0.5`

2. Target `8`, current `8`
- Bonus OFF: `1.0`
- Bonus ON: `1.0`

3. Target `8`, current `10`
- Bonus OFF: `1.25`
- Bonus ON: `1.25`

## 3) Time Tracking

### Time Earned Points (Bonus OFF / Goal Mode)

- Linear and proportional:
  - `earned = (logged / target) * priority`
- Over-completion is linear (`2x time -> 2x points`)
- For windowed habits, OFF path can use differential contribution for today

### Time Earned Points (Bonus ON / Effort Mode)

Piecewise:

- if `logged < target`: `earned = (logged / target) * priority`
- if `logged >= target`: `earned = priority + diminishingBonus(logged - target)`

Only full extra 30-minute blocks after target count.

### Time Examples (priority = 1)

1. Target `20m`, logged `10m`
- Bonus OFF: `0.5`
- Bonus ON: `0.5`

2. Target `20m`, logged `50m`
- Excess = `30m` -> `+0.7`
- Bonus OFF: `2.5`
- Bonus ON: `1.7`

3. Target `120m`, logged `140m`
- Excess = `20m` -> no full block
- Bonus OFF: `1.1667`
- Bonus ON: `1.0`

## 2h vs 20m Targets: Why Bonus Sometimes "Does Not Help"

Bonus requires full excess blocks of 30 minutes.

- Target `20m`, logged `40m`: excess `20m` -> no bonus
- Target `120m`, logged `140m`: excess `20m` -> no bonus

If excess is the same, bonus is the same regardless of target:

- Target `20m`, logged `50m`: excess `30m` -> `+0.7 * priority`
- Target `120m`, logged `150m`: excess `30m` -> `+0.7 * priority`

So longer targets are not penalized in formula directly, but in practice they are harder to exceed by full 30-minute blocks.

## Known Behavioral Mismatches / Caveats

1. Time habit target scaling vs earned scaling:
- Habit target uses a duration multiplier in `calculateDailyTarget` (`round(targetMinutes / 30)`), so long time habits can have larger targets.
- Earned in Effort mode for time tracking uses `priority + diminishingBonus(excess)`, not the same multiplier.
- Result: for some long time habits, completion at exactly target time may show below 100%, and very high percentages may be mathematically hard or impossible.

2. Task vs habit asymmetry for binary time bonus:
- Tasks adjust target for binary bonus.
- Habits do not.
- This is intentional in current behavior to treat habit extra time as over-completion.

3. Full-block requirement:
- Bonus is block-based (`floor(excess/30)`), so `29` excess minutes adds `0`.

## Pseudocode Summary

```text
if trackingType == quantitative:
  earned = proportional quantity progress
  // no time bonus path

if trackingType == time:
  if bonus OFF:
    earned = linear proportional vs target
  else:
    if logged < target: earned = proportional
    else: earned = priority + diminishingBonus(logged - target)

if trackingType == binary:
  earned = base completion/counter logic
  if bonus ON and not disableTimeScoringForPoints:
    earned += diminishingBonus(logged - baselineEstimate)

  // target side
  if category == task:
    target = priority + binaryBonusAdjustment
  else if category == habit:
    target = habit daily target logic (no binary bonus target adjustment)
```
