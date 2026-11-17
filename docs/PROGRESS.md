# PROGRESS

State of the build. Read this first, every session (GDD 1.4).

## Start of every session

1. `pwd`
2. Read this file, `docs/DECISIONS.md`, `tests/tests.json`, `git log --oneline -20`.
3. If `docs_api/` is missing: `godot --headless --doctool docs_api && touch docs_api/.gdignore`
   (the engine API as XML; search it before using a class you are unsure of).
4. `tools/check.sh` must print `CHECK OK` before any new work.
5. Take the first unchecked step of the current milestone below.

Working loop (GDD 1.4 rule 3): implement one behaviour, write or enable its
test, `tools/check.sh`, commit, add two lines to the log at the bottom.

Useful commands:

| Purpose | Command |
|---|---|
| Everything | `tools/check.sh` |
| Tests only (after adding a `class_name`, run `godot --headless --path . --import` first) | `godot --headless --path . --script res://tests/run_tests.gd` |
| Some tests, verbose | `... run_tests.gd -- --only=T-HAND,T-GATE --verbose` |
| Mark newly passing tests | `... run_tests.gd -- --promote` |
| One scene, 10 s of game time | `godot --headless --path . --fixed-fps 60 res://scenes/boot.tscn --quit-after 600` |
| Screenshot (no GPU here, see D-015) | `xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy ...` |

## Current state

- **Milestone:** M5 (a whole Telling). M4 is complete but for its review.
- **Tests:** 42 of 114 passing (M0: 2, M1: 8, M2: 10, M3: 7, M4: 13, M5: 2).
- **Reviews:** `m1-review` and `m2-review` reported on every lens (run ids wf_53ae3899-d40 and wf_d8c835c4-884; findings saved as JSON under the scratchpad `fixes/` folder, which does not survive the container: the lists below are what is left). Applied: M1 hand, wheel and gate; M2 car (D-028), traffic and collisions (D-029); M1 gesture pipeline code (D-030); M1 rules and the M2 view findings on indicators, vehicle ids, dashes, bend (D-035). **Still open:** (a) M2 views: glovebox and horn markers buried in props; pointer ring drawn at the hand's clamped target; the hand does not follow the gear knob; left sleeve placed behind the eye; forearm stretches beyond 0.30 m for five far anchors (decision not recorded); Cabin node names of GDD 13.5; `scene` in placeholders ignored for road strips, arm and pointer. (b) M1 test honesty (18): no test moves the pointer with relative motion; T-WHEEL-01 never releases a turned wheel; grip and ride on an off-centre wheel; gate engage radius and grind band probed from one side; FLICK time and direction limits; CRANK angle-not-distance; gate channel width; camera pitch and glance following the hand; pointer pixels to screen; steering sensitivity wiring; loose brackets on timing limits; literals standing in for tuning values. (c) M1 gesture: rituals.json is not checked against the table of GDD 4.6. (d) M2 test honesty leftovers (see D-028 and D-029 for what was done). M3 and M4 have not been reviewed. Background agents hit the usage limit on 2026-11-17 (resets 2026-11-20 01:00 UTC): until then work without workflows.
- **Next step:** M5 (a whole Telling): Clock, run state and the Fork/Leg/Exit/Stop/Boss flow, stops and the shop, save and load, Wreck and restart, the input log and state hash. The open review items above are to be worked off alongside (the test-honesty ones are good work for parallel agents once they are available again).

## Milestones

Do not start a milestone until every test of the previous one passes (GDD 18).

### M0 Harness: T-DATA-01, T-SMOKE-BOOT
- [x] Project settings of GDD 13.1 (window, stretch, 120 ticks, input actions, autoloads)
- [x] Folder layout of GDD 13.2
- [x] Data loader (`GameData`, `Tuning`) and data validator
- [x] `tuning.json` (all of GDD 15), `anchors.json` (GDD 16.2), `faults.json` (GDD 6.3), lines of GDD 3.6
- [x] Test runner, registry with all 114 ids as failing, append-only guard
- [x] `tools/check.sh`: import, parse check and core purity lint, data, tests, smoke
- [x] `docs/PROGRESS.md`, `docs/DECISIONS.md`
- [x] T-DATA-01: shipped data validates; GDD 14 examples validate; 65 broken variants are each rejected with the right code
- [x] T-SMOKE-BOOT: boot.tscn runs 600 frames headless with five autoloads, all data loaded, no error output

### M1 The Hand and the wheel: T-HAND-01..03, T-WHEEL-01..02, T-GATE-01..02, T-GEST-01
- [x] `DriveInput`, `CabinSpace` (pointer map, free target, rim zone, glance), M1 tuning constants
- [x] `HandSim`: snap, travel through W, left-side speed, input buffer, fly-and-grip, riding the wheel
- [x] `WheelSim`, `Gesture` (TAP, HOLD, FLICK, DRAG_TO, CRANK, BEAD), `GearGate`
- [x] `DriveSim` stepping them in the order of GDD 13.3; control rituals of GDD 4.6 in `rituals.json`
- [x] The eight M1 tests written and passing (not yet promoted)
- [x] Cabin sandbox: `scenes/drive.tscn`, `drive_controller.gd`, `CabinView`, `HandView` (analytic arm), `PointerView`, `DebugHud` (F1); screenshots in `artifacts/m1_*.png`
- [x] Tests promoted (the registry must match what passes; review findings are applied on top)
- [ ] Adversarial review of the M1 core and tests (workflow `m1-review`, running on a snapshot of commit a7c3d8a): apply confirmed findings, strengthen tests where a mutation survived

### M2 Driving: T-CAR-01..05, T-COL-01..03, T-CC-01..02
- [x] `Rng` (road, shop, heckle, bot streams), `CarSim`, `TrafficSim`, `Collision`, thin `NervesSim` and `FaultSim`
- [x] `DriveSim` steps 5 to 7; cash; events `hit`, `lamp_lit`, `close_call`, `wreck`
- [x] Vehicle table (GDD 5.5) in `beats.json`; M2 tuning constants
- [x] The ten M2 tests written, passing and promoted
- [x] Road view: uniform strips plus recycled dashes and posts; `world_bend.gdshader`; pooled vehicle views; flat sky
- [x] Sandbox traffic so the scene can be driven; `artifacts/m2_road.png`
- [ ] Review of the M2 core, tests and views (workflow `m2-review`, running on a snapshot of commit e197006): apply confirmed findings

### M3 Nerves and the base cabin: T-NERVES-01..04, T-FAULT-01..02, T-ITEM-BASE
- [x] `EffectSystem` (timed statuses, stacks, holds, implications from the effect registry in `items.json`)
- [x] `NervesSim` in full: thresholds, Tremor, Tunnel, Pound, Snap, Heavy floor, Lids, Blink, Nod, ambient rates
- [x] `FaultSim` in full: seeded fault deck, lamps, capacity bonus, per-fault params, repair
- [x] `ItemSim`: slots, ritual choice per anchor, ritual ops, starting cabin; horn, wipers, radio (DRAG dial), cigarettes, tea, visor photo, slap, window, indicator, hazards, high beam
- [x] `DriveSim` wires step 9 (effects, items, Nerves, faults); Tremor on the gripped wheel; fault effects (pull, rattle, clutch, wiper, cone, cracks, mirror)
- [x] Data: `items.json` (effects, starting cabin, cigarettes, tea), ritual ops, slots, all sfx ids of GDD 16.5
- [x] The seven M3 tests written, passing and promoted
- [x] Cabin view: dashboard lamps, items in their slots, cash stack, lowered visor; only anchors in use are drawn; HUD rows for Nerves, lamps, cash, speed, radio, effects (`artifacts/m3_cabin.png`). Lids, tunnel, haze and blink are numbers in the HUD until the post effect of M10.
- [ ] Review of the M3 core and tests

### M4 Legs and encounters: T-GEN-01..03, T-SUS-01, T-LEG-01..09
- [x] Leg, modifier and beat data; validator schemas (`data/legs.json`, `modifiers.json`, `beats.json`)
- [x] `LegGenerator`: par-frame plan, held-up traffic, never-a-wall line, zones, density (DECISIONS D-026)
- [x] `RunGenerator`: forks by act (leg pool, modifier chance)
- [x] `LegSim`: spawns by trigger, planned lane changes, curves, gusts, hazards, flock, melons, leg end
- [x] `tests/support/leg_checker.gd`: independent rule checker and driven check; T-GEN-01..03 pass
- [x] T-LEG-01..05: Open road, Rush, Rain, Night, Roadworks driven through `DriveSim` (dust haze and visibility in the snapshot)
- [x] `SuspicionSim` and the pull-over (T-SUS-01); `EncounterSim` with the Patrol (T-LEG-07); DECISIONS D-031
- [x] Tailgater (T-LEG-06): in his tracks on the bumper, rams on the brake, pass and brake-check, lost in fourth
- [x] Two-lane (T-LEG-08)
- [x] Motorcade (T-LEG-09): convoy, wall, spotlight, slip lane and Two-lane side road (DECISIONS D-033)
- [x] Wedding honk (a wedding car passed closely is -5 Nerves; checked in T-CC-01); one list of bus signals (D-034)
- [x] Views: hazards, signs, police beacon, night and dust haze, rain sky, slip lane, the motorcade's sign; `--leg=` and `--bot=` (DECISIONS D-035; `artifacts/m4_*.png`). Rain streaks, glare and the mirror wait for the post effects of M10; the HUD shows them as numbers.
- [ ] Review of M3 and M4

### M5 A whole Telling: T-RUN-01..02, T-CLOCK-01, T-STOP-01, T-SAVE-01, T-REPLAY-01
- [x] `ClockSim` (T-CLOCK-01): runs while he drives, stands while he is pulled over; fines and bribes charge it
- [x] `RunState` and the flow of a Telling in `DriveSim`: approach, Fork by the side of the gore, Leg, Exit slip lane and stall, boss stand-ins, boss stop, Arrival (T-RUN-01; DECISIONS D-036)
- [ ] Stops and the shop: `stops.json`, the 32 item records, offers, TAP to buy, DRAG_TO to place, repairs, restocks, tea, find, shady guy, boss stop (T-STOP-01)
- [ ] Wreck and restart (T-RUN-02)
- [ ] `Save` (T-SAVE-01); input log and state hash (T-REPLAY-01)
- [ ] Views: fork sign, exit, stop view, dashboard clock, sky by the Clock; the drive scene runs a Telling

### M6 All items: T-ITEM-* (32), T-SYN-* (9), T-PHANTOM-01
- [ ] not started

### M7 Bosses: T-BOSS-01..03, T-CALL-01
- [ ] not started

### M8 Passengers: T-PASS-* (5)
- [ ] not started

### M9 The frame: T-TABLE-* (7), T-HECKLE-01, T-END-01, T-PROLOGUE-01, T-FINALE-01
- [ ] not started

### M10 Presentation and options: T-ONEHAND-01, T-SETTINGS-01, T-SMOKE-ALL
- [ ] not started

### M11 Balance: T-BOT-01, T-WALL-01
- [ ] not started

### M12 Touch and export: T-TOUCH-01
- [ ] not started

## Known debts (builder)

- Simulation speed (measured at M5): 45 microseconds per tick on an empty road, 95 on an Open road leg, 130 on a Rush leg with 23 vehicles; a whole Telling of 1,100 s of driving takes about 15 s. Traffic's follow rule was the worst of it and is linear now. A Telling of 20 minutes is about 12 s of CPU; the full balance run of GDD 13.8 (100 seeds x 3 skills x 7 Tables) would take hours. The per-tick Dictionary lookups in `ItemSim.step`, `FaultSim.param` and `EffectSystem.step` are the first things to tighten in M11.

## NEEDS OWNER

Things a human must judge or supply. Nothing here blocks the build.

- **Name.** The project is called I-99 as briefed; the GDD text still says
  Single-Handed (D-002). Confirm, or change the line `title.game_name`.
- **Export targets.** Brief says Windows/iOS/Linux, GDD says Windows, Linux,
  macOS. M12 will ship all four presets (D-016). iOS needs the owner's Apple
  team id and signing to actually build.
- **Lines.** Every English line is a placeholder marked `needs_writer`; the
  Arabic file has the same ids and no text (GDD 1.2).

## Log

Two lines per slice, newest last.

- 2026-11-17 M0: project, folders, autoload skeletons, `GameData`/`Tuning`/`DataValidator`, tuning + anchors + faults + first lines.
  Test runner with error trap and append-only guard; 114 ids registered as failing; `tools/check.sh` green.
- 2026-11-17 M0: T-DATA-01 (validator proven on shipped data, GDD 14 examples and broken variants) and T-SMOKE-BOOT pass and are promoted.
  Tools started with `--script` use `user://test_runs/tool` and ignore game arguments. M0 complete: 2 of 114.
- 2026-11-17 M1: core simulation of the hand, wheel, gestures and gear gate with `DriveSim`; eight tests written and passing.
  Cabin sandbox scene renders under Xvfb (artifacts/m1_*.png). Review workflow running on a snapshot before promotion.
- 2026-11-17 M2: car, traffic, collisions and close calls simulated; ten tests pass. M1 and M2 tests promoted: 20 of 114.
  M1 review still running in the background on a snapshot; its findings will be applied as their own commit.
- 2026-11-17 M2: road, vehicle and sky views with the world-bend shader; sandbox traffic; `m2-review` launched.
  M3: EffectSystem, full NervesSim and FaultSim, ItemSim with the base cabin; seven tests pass; 27 of 114.
- 2026-11-17 M4: leg generator (D-026), forks, `LegSim`, the leg checker; T-GEN-01..03 and T-LEG-01..05 pass.
  M1 and M2 review findings applied for the hand, wheel, gate, car, traffic, collisions and gestures (D-028 to D-030).
- 2026-11-17 M4: Suspicion and the pull-over (D-031), Patrol, Tailgater (D-032), Two-lane, Motorcade with its side road (D-033).
  All thirteen M4 tests pass and are promoted: 40 of 114. Background agents are over the usage limit until 2026-11-20.
- 2026-11-17 M4: wedding honk; one list of bus signals (D-034); views for hazards, signs, beacon, haze, slip lane; `--leg=` and `--bot=` (D-035).
  M1 rule findings applied (purity lint, countdowns, runner, settings, anchor indices, validator). Smoke now also runs three legs.
- 2026-11-17 M5: the Clock (T-CLOCK-01); `RunState` and the road of a Telling: approach, fork, Exit and stall, stops entered and left, boss stand-ins, Arrival (T-RUN-01, D-036).
  A scripted par Telling with seven stops parks at 05:34. Traffic's follow rule is linear with an identical trace. 42 of 114.
