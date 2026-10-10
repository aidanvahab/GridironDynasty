# Gridiron Dynasty 1.0.0 — Test Report

Environment: Linux container (Ubuntu 24.04, 4 vCPU, no GPU), Godot 4.7.2-stable,
Xvfb virtual display with software rendering (Mesa llvmpipe — Vulkan Forward+
for the editor runs, OpenGL Compatibility fallback for the exported Linux
build), Wine 11 for the Windows build. No sound device and no physical
controller were available.

## 1. Automated unit / integration tests — `tools/test.sh`

**65 tests, 19,797 assertions, 0 failures.** Any script error raised during a
test also fails it.

| Suite | Tests | Covers |
|---|---|---|
| `test_rules.gd` | 31 | first downs (9.9 yd ≠ first down), downs/turnover on downs, incompletions (spot, clock), runoff/tempo, timeouts, TD → try → kickoff, two-point, interceptions incl. touchback and pick-six, safety + free kick, FG made/missed (spot of kick vs 20), punts/touchbacks, quarter changes (direction flip, drive continues), no snap after expiry, halftime kickoff, two-minute warning, game over (no further plays), OT receiver TD, OT FG then answer, sudden death, regular-season tie, playoff multi-OT, kneel, run-out-clock, team stats |
| `test_field_coords.gd` | 6 | world/field round trips in both directions, goal lines, forward/right conventions, spot labels, bounds |
| `test_simulation.gd` | 7 | league generation validity (rosters, minimums, cap, unique numbers, no shared players), determinism, position strength profiles, 120 simulated games (scores sane, scoring log == final score), drive possession, CPU kneel, 4th-down decisions |
| `test_gameplay.gd` | 6 | live plays via bot input: pass play result, run play handoff credit, 60 plays across 20 plays × 7 defenses × both directions (no stalls, gains in range), kneel/spike, -X direction, field-goal physics (good/wide/short, both directions and hashes) |
| `test_franchise.gd` | 15 | schedule validity (10/14/15 games: once per week, no repeats, balanced home games), tiebreakers, idempotent results, full season → playoffs → champion → awards, offseason → draft (5 rounds) → next season, cap/roster limits, contract expiry + re-sign, lowball rejection, progression (young up, old down, ≤ potential), trades (validation/execution), scouting reports, save/load round trip, repair of corrupted ownership, atomic save + corrupted-main → backup recovery, 3-season stability (invariants, bounded player pool) |

`tools/lint.sh`: every GDScript file compiles (0 failures).

## 2. End-to-end scenarios against the real application — `tools/e2e.gd`

| Test | Scenario | Result |
|---|---|---|
| **A** New career | `career`: wizard (coach, franchise, rebrand to "Westhaven Comets", recommended setup, start) → hub; every hub tab opened | **PASS**, 0 errors, 16 screenshots |
| **B** Complete drive | covered by `match`/`stability` (completions, first downs credited; scoring log reconciles) and `input` (real-input pass thrown to the targeted receiver) | **PASS** |
| **C** Incomplete pass | unit tests (spot/down/clock) + rendered `match`/`input` runs ("Broken up by #54", 1st→2nd & 10, 3 s charged) | **PASS** |
| **D** Rushing TD | unit tests (TD → try → kickoff → possession) + full matches with rushing scores and tries | **PASS** |
| **E** Defensive possession | simulated opponent drives in every full match: score, clock, field markers and possession updated through the rules engine | **PASS** |
| **F** Turnover | unit tests (INT, pick-six, fumble, downs) + live INTs/fumbles in the balance harness and full matches | **PASS** |
| **G** End of match | `match` (headless, 4× time): intro → kickoffs → drives → tries → halftime → postgame → hub; final 40–21, scoring log == final score, schedule updated, week advanced, player stats credited | **PASS** |
| **H** Season advancement | `season`: whole season → playoffs → champion → review → re-sign → draft → free agency → camp → next season | **PASS** |
| **I** Persistence | `persist_a` (create, sim 3 weeks, save) then a **separate process** `persist_b` (continue from menu): team, record, week, roster, ratings, stats, schedule results, player pool all restored | **PASS** |
| **J** Settings | `settings_a` then a separate process `settings_b`: music volume, quality, camera shake, UI scale, difficulty persisted and re-applied to audio buses | **PASS** |
| **K** Input | `input` under a real display: Space snap, key 1 targets receiver 1, mouse hold charges (0.74), release throws to that receiver, handoff gives control of the runner (W+Shift, Space juke), gamepad A snap, hold B targets receiver 2 and charges, release throws to receiver 2, Esc pauses/resumes, borderless fullscreen applied, window resized to 1280×720, quit to hub | **PASS** (synthetic gamepad events; no physical controller) |
| **L** Extended stability | `stability`: 3 consecutive live matches (9–19, 7–29, 26–0) → scores consistent, node count 153/156/156, 0 orphan nodes, no duplicate ownership; plus the 3-season franchise test | **PASS** |
| **M** Release builds | see section 3 | Linux **PASS**, Windows **PASS (Wine)**, macOS built, **not run** |

A rendered (non-accelerated) full match was also captured for visual review
(kickoff, presnap, live play, result, opponent drive, halftime); with a CPU
rasterizer at ~3–8 fps a full game exceeds 30 minutes, so complete-game
verification uses the headless 4× runs above.

## 3. Release builds

| Platform | Artifact | Built | Launched | Notes |
|---|---|---|---|---|
| Linux x86_64 | `dist/GridironDynasty-1.0.0-linux-x86_64.tar.gz` | yes | yes | From the packaged archive: main menu, existing save shown as "Continue Career", new career → hub, autoplayed quick match in progress (Q2, 7–3). Fell back to OpenGL automatically (no Vulkan driver). |
| Windows x86_64 | `dist/GridironDynasty-1.0.0-windows-x86_64.zip` | yes | yes (Wine 11) | Main menu rendered with Vulkan (lavapipe) under Wine; quick match run from the packaged zip (see below). Not run on real Windows. Unsigned. |
| macOS Universal (x86_64 + arm64) | `dist/GridironDynasty-1.0.0-macos-universal.zip` | yes | **no** (no macOS available) | `.app` bundle verified structurally: universal Mach-O, Info.plist (`com.gridirondynasty.game`, 1.0.0), embedded `.pck`, icon. Ad-hoc signed only; **not notarized**. |

SHA-256 sums: `dist/SHA256SUMS.txt`.

## 4. Gameplay balance (bot-driven live snaps, `tools/balance.gd`, 150 snaps)

| Difficulty | Comp % | Yds/att | INT | Sacks | Yds/carry |
|---|---|---|---|---|---|
| Rookie | 71% | 7.4 | 1 | 6 | 8.9 |
| Pro | 67% | 9.0 | 5 | 7 | 6.7 |
| All-Pro | 61% | 4.6 | 5 | 18 | 5.2 |
| Legend | 60% | 7.8 | 6 | 16 | 4.9 |

Simulated games (drive simulator, 60 games): 22.7 points, 12.5 drives,
355 yards and 1.3 turnovers per team — in line with professional football.

## 5. Not verified / known limitations

* **Performance on real GPUs is untested.** All rendering ran on a CPU
  rasterizer (3–10 fps). The 60 fps target, Metal on macOS and D3D/Vulkan on
  real Windows hardware need verification on real machines. Quality "Low"
  reduces crowd density, shadows and post-processing.
* **Audio was never heard.** Assets are generated, imported and played
  through the buses without errors; spectrograms were checked, but mix and
  loudness need a listening pass.
* **Physical controllers** were not available; controller support was
  verified with synthetic joypad events through Godot's input system.
* **macOS build not launched**; unsigned/un-notarized builds trigger
  Gatekeeper (see README for the right-click → Open workaround and the
  signing/notarization steps).
* Rule simplifications are listed in `docs/RULES.md` (no penalties, no play
  clock enforcement, simplified kick returns, no onside kicks).
* Defense is simulated drive-by-drive by design; there is no user-controlled
  defense.
* No weather effects other than wind on kicks.
* CPU teams do not trade with each other (they make offers to the user and
  manage rosters through re-signing, the draft and free agency).
* Live-play balance was tuned with a scripted bot, not with human playtests.
