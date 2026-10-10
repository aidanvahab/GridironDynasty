# Gridiron Dynasty — Rule Set

All rules live in one place: `scripts/football/rules_engine.gd` (tested by
`tests/test_rules.gd`). Live play and the opponent simulator both send
`PlayResult`s through it, so they can never disagree about downs, scoring,
clock or possession.

## Field and coordinates
* 100-yard field, 10-yard end zones, 53⅓ yards wide; 1 world unit = 1 yard.
* Goal lines at world x = ±50, end lines at ±60, sidelines at z = ±26.67.
* Gameplay positions use the **offense frame**: `ball_on` = yards from the
  offense's own goal line (0–100), `lateral` = yards to the QB's right.
  `FieldCoords` converts between frames using the offense's direction (`dir`),
  which flips every quarter as teams switch ends.
* Snaps are spotted between the hash marks (3.08 yards from the center).

## Downs and scoring
* Four downs to gain 10 yards; a first down requires reaching the line to gain
  exactly (9.9 yards is not enough). Goal-to-go inside the 10.
* Touchdown 6 (ball carried or caught with possession in the end zone), extra
  point kick from the 15 (1) or two-point try from the 2 (2), field goal 3,
  safety 2 (followed by a free kick from the 20).
* Turnover on downs: the defense takes over at the dead-ball spot.
* Missed field goal: defense takes over at the spot of the kick or its own 20,
  whichever is better for it.
* Interceptions/fumbles: possession changes at the end of the return; a
  turnover downed in the defense's own end zone is a touchback (20).
* Touchbacks: kickoff → 30, punt → 20, turnover → 20.

## Clock
* Live-play time always runs off.
* Between plays the clock runs only after an in-bounds run or completion.
  Runoff depends on tempo (Hurry 15 s, Normal 36 s, Chew 41 s), scaled by the
  chosen game length. The offense can always get a snap off before the period
  ends (runoff is capped to leave one second).
* The clock stops after incompletions, out of bounds, scores, turnovers,
  changes of possession, timeouts, the two-minute warning (Q2 and Q4) and the
  end of a period.
* Three timeouts per half, two in overtime.
* Victory formation: a kneel lets 41 s (scaled) run; "Run out the clock" ends
  the period when the lead is safe.

## Periods and overtime
* Four quarters; teams switch ends each quarter. The team that received the
  opening kickoff kicks off to start the second half.
* A play that starts before the clock expires is completed; the try after a
  touchdown is still played at 0:00. No snap is ever allowed after the game
  ends.
* Overtime (one period, max 10 minutes): coin toss; a touchdown on the first
  possession wins; if the first possession ends in a field goal or no score the
  other team gets a possession; after that it is sudden death. Regular-season
  games can end tied after one OT period; playoff games continue until there
  is a winner.

## Documented simplifications
* No penalties (holding, false starts, pass interference, delay of game).
* No play clock / delay-of-game enforcement.
* Out-of-bounds always stops the clock (no "clock restarts on the ready for
  play" rule outside the last two minutes).
* Intentional grounding is not called; the throw-away (E) is always legal.
* Fumble recoveries are downed at the spot (no advancing a recovered fumble),
  except interception returns, which are run back live.
* Kickoffs and punts are presented visually but resolved by the kicking model
  (distance from the kicker's leg, returner speed vs. coverage).
* Onside kicks and fake punts/field goals are not available.
* The user controls the offense in real time; defensive possessions are
  simulated play-by-play with the same rules engine.
