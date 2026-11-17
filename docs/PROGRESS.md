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

- **Milestone:** M7 (bosses): the framework, the Storm, Dawn with the Call and the Arrival are in (three of its four tests pass); the Checkpoint is designed (D-048) and is next, then the views of the bosses. M6's review findings (listed below) remain to be applied.
- **Tests:** 91 of 114 passing (M0: 2, M1: 8, M2: 10, M3: 7, M4: 13, M5: 6, M6: 42, M7: 3).
- **Reviews:** `m1-review` and `m2-review` reported on every lens (run ids wf_53ae3899-d40 and wf_d8c835c4-884; findings saved as JSON under the scratchpad `fixes/` folder, which does not survive the container: the lists below are what is left). Applied: M1 hand, wheel and gate; M2 car (D-028), traffic and collisions (D-029); M1 gesture pipeline code (D-030); M1 rules and the M2 view findings on indicators, vehicle ids, dashes, bend (D-035). **Still open:** (a) M2 views: pointer ring drawn at the hand's clamped target; the hand does not follow the gear knob; forearm stretches beyond 0.30 m for five far anchors (decision not recorded); `scene` in placeholders ignored for road strips, arm and pointer. (b) M1 test honesty (18): no test moves the pointer with relative motion; T-WHEEL-01 never releases a turned wheel; grip and ride on an off-centre wheel; gate engage radius and grind band probed from one side; FLICK time and direction limits; CRANK angle-not-distance; gate channel width; camera pitch and glance following the hand; pointer pixels to screen; steering sensitivity wiring; loose brackets on timing limits; literals standing in for tuning values. (c) M1 gesture: rituals.json is not checked against the table of GDD 4.6. (d) M2 test honesty leftovers (see D-028 and D-029 for what was done). M3, M4 and M5 have not been reviewed. Workflows work again (the usage limit of 2026-11-17 has lifted): use them for reviews and for independent parts.
- **Next step (the session paused here on 2026-11-17, with everything committed and pushed):**
  1. **M7c, the Checkpoint (T-BOSS-01).** Its design is settled and written down with its data records in DECISIONS D-048: build it as written there. Order: the checkpoint's numbers and rituals into the data and the validator (schema `checkpoint`, ops `hand`/`stow`/`unstow`, conditions `glovebox_room`/`stowed`, switch `letter_aside`, `"shared"` rituals, `"to": "@home"`); `ItemSim` (stowing, `take_all_contraband`, `handed`); `BossSim` (queue vehicles, bar, Stow, Papers) and `DriveSim` (Suspicion without decay, +25 on a barrier, the verdicts); T-BOSS-01; the owed checks of T-ITEM-BREATH-MINTS and T-ITEM-FORGED-PAPERS; the scripted driver of T-RUN-01 through the queue and the papers.
  2. **M7d.** Views of the bosses (dust and tail lights, gust streaks, the glow and the sun, barriers and the sign, the soldier, the phone at his ear, the bay and the key), `--boss=<id>[,modifier]`, screenshots; the stand-in bot of `drive_controller.gd` still drives a boss at par along the plan's line (it is searched at Dawn's barriers). Then an adversarial review of M7 as a workflow, and its findings.
  3. **Tests to strengthen.** Mutation runs are `python3 tools/mutants.py <test ids> tools/mutants/<list>.py [log]` (one textual change at a time, the tests, the file restored; `MUT_ROOT=<copy>` runs them on a copy of the project). All 38 mutants of the Storm (`storm.py`) are killed by T-BOSS-02. Of the 67 of Dawn, the Call and the Arrival (`dawn.py`) the first 43 were run against T-BOSS-03 and T-CALL-01: 40 killed, 3 alive: traffic kept at a flat quarter all through the false dawn instead of rising (check that the second half of it carries clearly more than the first); vehicles beside him in the reserved stretch of the last checkpoint (`LegGenerator._in_reserved` removed: check that no planned vehicle is met between the taper's start and the corridor's end); and the once-only flag of the speed check at the barriers, which is equivalent (the car crosses them once). Run numbers 44 to 67 (the rest of the Call, the Arrival) and close what lives.
  4. **M6 review findings** below, then M8 (passengers; the Call's "passenger beside him" is the cabin switch `passenger` until then), M9, M10, M11, M12 as GDD 18 has them.
  Tests for the cabin extend `CabinSuite` (tests/support): `_reach`, `_hold_at`, `_tap_at`, `_flick`, `_carry`, `_drag`, `_crank`, `_wipe`, `_grip`, `_steer`, `_reach_time`, `_scrape_rail`, `_pass_closely`, `_to_quiet_leg`, `_into_stall`, `_leave_stop`, `_begin_quiet_leg`, `_begin_quiet_boss`, `_drive_on_to_act`, `_into_next_quiet_leg`. How items say what they do is D-040 to D-044; bosses are D-046 to D-048. **Owed checks, to be appended when their systems exist:** T-ITEM-SEEDS with a real unanswered Doubt (M9; it now checks `DriveSim.fray`); T-ITEM-BREATH-MINTS and T-ITEM-FORGED-PAPERS at the real Checkpoint (M7c; they now check `courage_noticed()` and `use_forged_papers()`); T-PHANTOM-01 in the Storm is covered by T-BOSS-02 (append the same check to T-PHANTOM-01). Settings to wire in M10: `steer_sensitivity`, `grip_toggle`, `sequential_shift`, `phantom_enabled`.
- **How long checks take here:** `tools/check.sh` needs about six minutes. To go on working while it runs, check a copy: `git archive HEAD | tar x -C <scratch>/chk` and run `tools/check.sh` there (the same for mutation runs, with `MUT_ROOT`). Never wait with `sleep` or a polling loop: start it in the background and read its log when told it is done.
- **Workflows at the pause** (their worktrees, local branches and journals live only in the container): `m10-presentation` (run wf_9e18e3ba-75d: generated audio, the post-effect shader, subtitles, each built on a local branch `m10/<piece>` off commit 88a7899 under the rule "nothing under src/core", then reviewed and fixed) had its first two builders at work and nothing committed; `m6-items-review` (run wf_2f6ba2b0-546, on commit cf5650b) had two of four lenses reported (below) and none verified. If the container is still there, the finished parts are in `.claude/worktrees/` and the journals under the session's `subagents/workflows/`; if not, launch them again (the M10 brief: build the piece, a tool that proves it, pictures read back, `tools/check.sh` green, commit on the branch, do not push).
- **Findings of `m6-items-review` so far** (lenses "keepsakes and state" and "habits"; each came with a probe, none has been through its verify agent; fix the bugs, add the tests, decide the two owner's calls):
  - Bugs: (1) a mixtape bought or picked at a stop cannot be put in the deck: the radio's dial takes the hand at the shared place, so the tape stays on the tray and a boss stop's free pick is lost (let the covered anchor give way while a tape is carried; test with a bought tape); (2) a Snap at a stop never ends (`snap_left` is not counted down there): he cannot reach the tray; (3) pulled over, the Clock stands but calls keep coming: unlimited cash while the officer waits (stop step 9 while `_standing()`, or let the Clock run); (4) after a Wreck the save file still holds the wrecked Telling's last stop: continuing undoes the Wreck (clear `checkpoint` in `_retell()`, write an empty save on `wreck`); (5) a sip in progress when a crash spills the tea still pays as a hot sip, and a TAP that ends just after the phone rang out counts as a second use of the phone (+30 twice): check a ritual's `requires` again when its gesture completes; (6) under Focus a gust lasts 120 real ticks but pushes by road time: it carries the car 15% less far (count the gust in road time); (7) the cigarette's calm runs one tick long (-10.0033): end a drip when less than half a tick is left; timed statuses read in step 9 act one tick short.
  - Rules at the seams: (8) the photo's once-per-leg and the charm's first scrape are renewed at a boss stop and again on the 170 m approach (the photo calms up to four times around a boss): keep `leg_state` through a boss stop and do not begin a new leg for the items on the approach; (9) a stop cancels the cigarette's craving (carry it through the stop); (10) the wait for the next call starts again at every stop (keep the seconds left in `item_state`); (11) a charm or tape acquired mid-leg or mid-act treats the next scrape or fault as the first (mark the first whether or not the keepsake is aboard); (12) what a stop ends is not announced (`fault_repaired` for the tape's mend, `call_resolved` for a call that was ringing, `effect_expired` for statuses).
  - Owner's calls (NEEDS OWNER): (13) at a stop every Habit is free and no timer runs: beads give unlimited calm for nothing and a cigarette, Courage, tea and seeds can be loaded at the stall to start whole on the road (either offer only the tray and the wheel at a stop, or let what he uses there run down there); the same while pulled over.
  - Tests that let mutants live: T-ITEM-DUCT-TAPE passes when the tape renews every leg and when a boss stop forgets the mend; nothing checks that the call count, the answered row or the photo pass through a stop; no test checks that Courage dulls Nerves gained by the second; the edge of Focus is pinned only for the car, one truck, the hand and two clocks (encounter, collision, hazards, spawns, the leg's road, items and Nerves steps can swap `DT` and `_road_dt` unnoticed).

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
- [x] Stops and the shop: `stops.json`, the 32 item records, `StopSim`, the tray's anchors, TAP to buy, DRAG_TO to place, repairs, restocks, tea, find, shady guy, boss stop, rarity (T-STOP-01; DECISIONS D-037)
- [x] Wreck and restart (T-RUN-02)
- [x] `Save`, save points at stops (T-SAVE-01); `InputLog` and `DriveSim.state_hash()` (T-REPLAY-01); DECISIONS D-038
- [x] Views: fork sign and gore, Exit sign and slip lane, `StopView` (vendor, tray, offers with prices), dashboard clock, sky by the Clock; `--table=`, `--continue`; the game writes the save at stops; the smoke test runs a Telling through its first stop (DECISIONS D-039; `artifacts/m5_*.png`)
- [ ] Debug keys F3 to F8 of GDD 13.9 (left for M10)

### M6 All items: T-ITEM-* (32), T-SYN-* (9), T-PHANTOM-01
- [x] `CabinSuite` (tests/support): the shared rig of the cabin suites; `DriveSim.give_item`
- [x] Cigarettes and tea through the hand, restock and refill at stops (T-ITEM-CIGARETTES, T-ITEM-TEA-GLASS)
- [x] How items say what they do (D-040): entries of gives and takes, statuses with numbers and immunities, synergy amounts, carried-object rituals
- [x] Worry beads, sunflower seeds, tissue box, mixtape (T-ITEM-BEADS, -SEEDS, -TISSUE-BOX, -MIXTAPE)
- [x] Energy drink (Focus), painkillers at `face` (T-ITEM-ENERGY-DRINK, T-ITEM-PAINKILLERS; D-041)
- [x] Arak flask (Courage, Sway, Lag), breath mints (T-ITEM-ARAK-FLASK, T-ITEM-BREATH-MINTS); the tray has ten places
- [x] Phone (calls; T-ITEM-PHONE). All eleven Habits pass.
- [x] Keepsakes: charm, air freshener, thermos, duct tape, lucky note, sunglasses, taxi sign (7 tests; D-042); standing changes (`passive` entries)
- [x] Synergies: tea + cigarettes, cigarettes + freshener, beads + music, flask + photo, flask + painkillers, phone + taxi sign, seeds + tea (7 of 9)
- [x] Adaptations: crossover stalk, window switch, spinner knob, wheel ring, thumb keypad, fifth gear, loud horn, bull bar, fog lamps, wide mirror (10 tests; D-043) and their two synergies (ring + spinner, stalk + keypad): all nine synergies pass
- [x] Deals: forged papers, tinted glass, turbo, the good stuff (4 tests) and the Phantom: flinch and weather cramp (T-PHANTOM-01); D-044. All 42 tests of M6 pass.
- [ ] Findings of the review `m6-items-review` (two of four lenses reported: listed under "Current state"; the other two and the verification were still running at the pause)
- [x] Views: a placeholder per item, the contraband tag, fittings of the Adaptations, moved anchors, the carried object, the ghost hand, the ringing phone, Sway's roll, Lag's trailing hand, HUD rows; `--give=` and `--hud` (D-045; `artifacts/m6_cabin_*.png`)

### M7 Bosses: T-BOSS-01..03, T-CALL-01
- [x] Boss framework (D-046): `BossSim` and its plans, boss numbers and `boss_modifiers` in legs.json, the modifier drawn by seed (`boss_modifier_chance`), `DriveSim.begin_boss`, the tea stall's sign
- [x] The Storm (T-BOSS-02): dust rhythm, gusts, wiper smear and window dust, standing on the shoulder, the weather cramp, Crosswind and Night storm, tail lights
- [x] Dawn, the Call and the Arrival (T-BOSS-03, T-CALL-01; D-047): generated rush traffic that builds, Glare and the visor, the last checkpoint's corridors (`CarSim` walls), the Call's four responses, the street, the bay and the key
- [ ] The Checkpoint (T-BOSS-01); the owed checks of T-ITEM-BREATH-MINTS and T-ITEM-FORGED-PAPERS at the real Checkpoint, T-PHANTOM-01 in the Storm
- [ ] The scripted driver of T-RUN-01 drives each boss for real (done: the Storm, Dawn, the Arrival; the Checkpoint remains)
- [ ] Views of the bosses; `--boss=`; screenshots
- [ ] Adversarial review of M7 (workflow)

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
- 2026-11-17 M5: stops and the shop: 32 item records, the tray at the passenger window, `StopSim` (T-STOP-01, D-037).
  Seven planted faults in the stop rules were each caught by the test. 43 of 114.
- 2026-11-17 M5: Wreck and restart (T-RUN-02), save points and the save file (T-SAVE-01), input log and state hash (T-REPLAY-01); D-038.
  This engine's JSON reader loses the last bit of some floats: saves carry exact bits beside the readable numbers. 46 of 114.
- 2026-11-17 M5: what a Telling looks like (fork sign, gore, Exit, the vendor's tray, dashboard clock, sky by the Clock); `--table=`, `--continue`; the game saves at stops (D-039).
  A clean leg now also gives the -10 Nerves of GDD 6.1 (it was missing). Smoke runs a Telling through its first stop. M5 done: 46 of 114.
- 2026-11-17 M6: a shared rig for the cabin tests (`CabinSuite`); cigarettes and tea driven through the hand, with restock and refill at stops. 48 of 114.
  Items now say what they do in five entry shapes; statuses carry immunities; a DRAG_TO can go out and back in or across (D-040). Beads, seeds, tissue box and mixtape pass: 52 of 114.
- 2026-11-17 M6: energy drink (Focus slows the road, not the hand) and painkillers (taken at his face; a TAP there is still a slap); per-leg state now passes through a stop.
  Arak flask (Courage, Sway, Lag), breath mints; contraband is refilled by the shady guy only; the tray has ten places (D-041). 56 of 114.
- 2026-11-17 M6: the phone (calls every 25 to 40 s, three TAPs, eyes down, every fourth is Um Noor); all eleven Habits pass. 57 of 114.
  The seven Keepsakes and seven of the nine synergies (D-042). A save at a stop in Act 2 or 3 no longer looks like a new act. 71 of 114.
- 2026-11-17 M6: the ten Adaptations and the last two synergies (D-043): the hook is hung in its ring and holds the wheel when he lets go; the high-beam rule of GDD 4.6 was missing and is in. 83 of 114.
  An adversarial review of the M6 items work runs as a workflow (`m6-items-review`), each lens in its own worktree.
- 2026-11-17 M6: the four Deals and the Phantom (flinch and weather cramp), D-044. All 42 tests of M6 pass: 88 of 114.
  Left for M6: the views of the items and the findings of the review that is still running.
- 2026-11-17 M6: the views of the items (D-045): placeholders, contraband tags, fittings, the carried object, the ghost hand; `--give=` and `--hud`; three screenshots.
- 2026-11-17 M7: bosses are roads with a plan (`BossSim`, D-046); boss modifiers are drawn by the Telling seed; after tea the next fork's sign shows the boss's.
  The Storm (T-BOSS-02): 8 s thin and 12 s thick dust by the clock, gusts at 2 m/s, wipers that smear, a truck out of the dust behind a car that stands unsafely. 89 of 114.
- 2026-11-17 M7: Dawn (T-BOSS-03), the Call (T-CALL-01) and the Arrival, D-047. The leg generator lays out Dawn's road; the car knows barriers; the hand can hold a phone to his ear.
  The whole-Telling test drives the Storm, Dawn and the Arrival for real and parks at 05:43. All 38 mutants of the Storm are killed. 91 of 114.
