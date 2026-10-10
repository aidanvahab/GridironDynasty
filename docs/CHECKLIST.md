# Gridiron Dynasty — Development Checklist

Legend: [x] done and verified · [~] implemented, partially verified · [ ] not done

## Phase 1 — Foundation
- [x] Godot 4.7.2 project, autoloads (Settings, Audio, SaveManager, App)
- [x] Canonical field coordinate system (`FieldCoords`) + tests
- [x] Centralized rules engine (downs, scoring, clock, OT) + 37 tests
- [x] Headless test runner with script-error detection, lint tool

## Phase 2 — Playable football
- [x] Procedural stylized player rig with procedural animation set
- [x] Field shader (lines, hashes, numbers, end zones), goalposts, pylons
- [x] Football: ballistic flight, spiral visuals, exclusive possession, fumbles
- [x] QB controls: move, receiver targeting, charge/release throws, lead passes
- [x] Receivers: routes with timing/variation, ball tracking, contested catches
- [x] Blocking (pass pro, zone/inside run, screen), pass rush with sheds
- [x] Coverage: man (rating-based reaction lag), zone (2/3/prevent), blitzes
- [x] Tackling with ratings, angles, jukes, broken tackles, fumbles
- [x] Broadcast camera (presnap, pocket, pass, carrier, kick, wide, replay)

## Phase 3 — Match loop
- [x] Play-call screen with diagrams, suggestions, flip, tempo, specials
- [x] Pre-snap: formation, audible, flip, timeout, route overlay
- [x] Opponent drives simulated play-by-play through the rules engine
- [x] Field goals / extra points (aim + power + wind mini-game)
- [x] Kickoffs and punts with visible ball flight and returns
- [x] Scorebug, feedback banners, halftime, two-minute warning, OT, postgame
- [x] Replays of touchdowns/turnovers from recorded frames
- [x] Pause menu, settings in-match, simulate rest of game

## Phase 4 — Franchise
- [x] 16 original teams, conferences/divisions, generated players with archetypes
- [x] Round-robin schedule (validated), standings with tiebreakers
- [x] Season advancement, 8-team playoffs, championship, awards, records
- [x] Progression (weekly training + offseason growth/decline), retirement
- [x] Contracts, salary cap, negotiation, expirations, re-signing
- [x] Draft with scouting uncertainty and scouting points; draft history
- [x] Free agency (user + CPU), trades (valuation, validation, CPU offers)
- [x] Staff hiring, facilities upgrades, finances, morale events, chemistry
- [x] Saves: 3 slots, schema version, atomic writes, backup recovery, repair

## Phase 5–6 — Presentation & content
- [x] Three stadium styles (classic, modern, historic), day/evening/night
- [x] Instanced animated crowd reacting to the game
- [x] Original synthesized audio: SFX, crowd layers, menu/halftime/victory music
- [x] Main menu over live 3D stadium, new-career wizard, hub, records
- [x] Championship celebration screen
- [x] Onboarding sequence + in-match coaching tips (replayable from Settings)
- [x] Difficulty levels change reaction, coverage, tackling, sim balance

## Phase 7–8 — QA & release
- [x] Unit/integration tests (rules, sim, gameplay, franchise, persistence)
- [x] E2E driver for the real app (`tools/e2e.gd`) with screenshots
- [x] Export presets (Windows, macOS, Linux)
- [x] E2E scenarios A–M (see docs/TEST_REPORT.md for results)
- [x] Windows, macOS (universal) and Linux release builds packaged in `dist/`
- [x] Font coverage: UI uses only glyphs present in Barlow (no OS fallback needed)
- [x] CI workflow (`.github/workflows/build.yml`): lint, tests, exports, artifacts
- [ ] Run on real Windows / macOS hardware with a GPU (not available here)
- [ ] macOS Developer ID signing + notarization (needs Apple account)
- [ ] Listening pass on audio mix; physical controller playtest
