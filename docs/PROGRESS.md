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
| A night with the bot at the wheel | `godot --headless --path . --fixed-fps 60 res://scenes/drive.tscn --quit-after 6000 -- --table=drivers --seed=3 --bot=expert --hud` |
| The balance report (GDD 12.5) | `tools/run_balance.sh [seeds per skill per Table] [jobs]`, or a look: `godot --headless --path . --script res://tools/run_balance.gd -- --cells=drivers/expert --seeds=4 --verbose --out=/tmp/b.json` |
| Screenshot (no GPU here, see D-015) | `xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy ...` |

## Current state

- **Milestone:** **All twelve milestones are built** (2026-11-27; the owner: "continue"). M11: the scripted driver of T-WALL-01 (D-067), the DriverBot and the balance runner (D-068). M12: touch, the pause's hotspot, four export presets (D-069). What is left is what a builder alone cannot do, and what was left open on the way: see NEEDS OWNER and the open findings below. M9 to M12 have had no adversarial review (the owner's spend limit ended the workflows on 2026-11-20; "ultracode" is off).
- **Tests:** 114 of 114 passing (M0: 2, M1: 8, M2: 10, M3: 7, M4: 13, M5: 6, M6: 42, M7: 4, M8: 5, M9: 11, M10: 3, M11: 2, M12: 1). `tools/check.sh` has eight steps (import, parse with the core and event-name lints, data, audio, tests, subtitles, smoke, postfx) and prints `CHECK OK`; the tests step takes about twelve minutes here (T-WALL-01 two of them).
- **How the last session ended.** On 2026-11-20 the account's monthly spend limit stopped six workflows in mid-run. What their agents had finished was taken in by hand on 2026-11-27: the M8 rules fixes (`m8fix/rules`, complete), the M6 test gaps (`m6fix/tests`, complete), the post effects review fixes (uncommitted in the agent's worktree; committed, merged, pictures retaken and looked at), and of the M7 views fixes V-01 and V-05. **What never ran and is still owed, if the owner wants it:** a skeptic's check of the fixes themselves. The fixes of D-055, D-057, D-058 and D-059, and the post effects fixes, are held by their own tests and mutants and by nothing else: no second agent tried to break them. The workflows' local branches (`m6fix/*`, `m7fix/views`, `m8fix/rules`, `m10/*-in-fix`) hold nothing that is not merged; they are not pushed and need not be.
- **The reviews' reports** are in `docs/reviews/` (one JSON per lens, with the GDD sentence, evidence and proposed fix of each finding). The probes they name are gone with the scratch folder.
- **Open findings, by milestone** (ids as in the reports):
  - *M7, the views lens* (`m7_review_views.json`): V-04, the verdicts are said in a line, but being turned back is still an uncut jump of 346 m and half an hour (a short cut through the post effects on `pulled_over` with minutes would do); V-11 (b), standing in the bay shows nothing in the forward view (the key's marker is below the frame: move the `key` anchor of anchors.json into it); V-13 (the bar, the barriers, their caps and the bay's paint are built from the registry's size and colour) is answered by D-070: such entries are marked `drawn_by_code` and the validator refuses a scene on them; V-14, numbers in view and game code (`_mirror_proud * 1.5`, `LIFT_PAINT`, `LIFT_LINE`, the gust's `_tell * 0.5`, the stand-in bot's 17 constants); V-15, the numeric HUD prints a nameless Leg row in a set piece and raw ids (`alone`, `parked`, what is carried); V-16, `--boss=` drops arguments it cannot use without a word, and after a Wreck every further round of a set piece begins wrecked; V-17, the stand-in leaves the window and the glovebox open after the Checkpoint (60% Haze in every Storm of a whole stand-in Telling) and takes every Exit; V-18, no smoke run puts the mirror's lights, the Patrol's blue, the phone at his ear or a searched Checkpoint on screen (the agent's unfinished `tools/views_check.gd` was not kept).
  - *M7, the rules* (D-057): DAWN-01 is closed (D-067); DAWN-11, a car across a lane line where the barriers begin is put into the lane its middle is in, up to half a car's width in one tick (the shoulder's 3.2 m jump is fixed, V-05); STORM-5, Night storm changes nothing a driver with two headlights can measure (NEEDS OWNER). Of the tests lens, cases named and not written: a standing car 5 cm short of wholly off the lanes; the 30 s of the Call timed in the three cases where he does not pull over; the generator's plan driven through Dawn's barriers; a Telling whose Checkpoint has a modifier.
  - *M8* (D-059): the test gaps m8tv-08, m8tv-09 (c to g) and m8tv-10 (seventeen clauses of GDD 8 and D-051 with no check; the build is right in each today). RULES-13 is the owner's (below).
  - *M6* (D-055): the fix branches were never reviewed. Seen by their agents and left: an item's `params` and its `lapse` are not checked by the validator; a phone taken out of the cabin while it rings ends its call without `call_resolved`; the stand-in at the wheel hands a Patrol's officer nothing and waits there for ever; `DriveSim._use_control` announces a keypad ritual without asking whether it ran; a stop reorders the cabin's list.
  - *M11* (D-067): whoever follows in the car's tracks (the Patrol's car, the Tailgater closing up or hanging back) can be drawn inside a vehicle the car has just cut in front of; behind the car, seen in the mirror only.
  - *M10*: GDD 17.2 was gone through for the tells of M7 and M8 only (D-058); the earlier milestones' tells (a curve's sign has no sound, the yawns and the Phantom's hum no picture) belong to the rest of M10. The post effects fixes have had no review of their own.
  - *M1 and M2* (reviews of 2026-11-17): closed on 2026-11-27 (D-070): the validator holds rituals.json and anchors.json to the table of GDD 4.6; what the code draws itself takes no scene (this also answers V-13 of the M7 views); the pointer's ring is where the pointer points; the forearm's stretch is recorded; 213 mutants of the hand, wheel, gate, gestures, car, traffic and collisions are all killed (52 lived at first). M3, M4 and M5 have not been reviewed.
- **Next step:**
  1. `tools/check.sh` must print `CHECK OK`.
  2. Nothing is next in GDD 18's order. What can be taken up, each with a check that fails first: the open findings below; the bot's missing habits (D-068: it does not smoke, sip, answer the phone or a heckle, carry a passenger, take the Motorcade's side road), which stand between its numbers and GDD 12.5's; a balance run of 100 seeds (`tools/run_balance.sh`, some hours); the tells of GDD 17.2 for the milestones before M7 (D-058); V-04 of the M7 views; the menus by touch without the engine's emulated mouse.
  The bot at the wheel: `--bot=novice|competent|expert` on the drive scene, or F7. `BalanceRun.tell(table, skill, seed, buys)` is one Telling's record; `tools/run_balance.gd --cells=drivers/expert --seeds=4 --verbose` a quick look. Touch is `TouchInput` (src/game): `finger_down/moved/up`, then `apply(sim, input)` each tick. A scripted drive for a test is `IdealDriver` (tests/support). A headless tool that needs the autoloads is a loader and a body (`tools/onehand_walk.gd`, `tools/touch_walk.gd`, `tools/subtitles_check.gd`); events are given with `root.push_input(event, true)`.
  Mutation runs are `python3 tools/mutants.py <test ids> tools/mutants/<list>.py [log]` (one textual change at a time, the tests, the file restored; `MUT_ROOT=<copy>` runs them on a copy of the project, `MUT_ONLY=3,5` a few of them). Every entry of every list applies to the code as it is (checked 2026-11-27); a change to `src/core` can make an entry stale, which `tools/mutants.py` reports instead of running it.
  Tests for the cabin extend `CabinSuite` (tests/support): `_reach`, `_hold_at`, `_tap_at`, `_flick`, `_carry`, `_drag`, `_crank`, `_wipe`, `_grip`, `_steer`, `_reach_time`, `_scrape_rail`, `_pass_closely`, `_to_quiet_leg`, `_into_stall`, `_leave_stop`, `_begin_quiet_leg`, `_begin_quiet_boss`, `_begin_checkpoint`, `_stand_at_the_bar`, `_drive_on_to_act`, `_into_next_quiet_leg`, `_drive_on_to_boss`, `_drive_on_to_boss_stop`, `_answer_to_a_pull`, `_check_answer_lags`. How items say what they do is D-040 to D-044; stops and pull-overs D-049 and D-055; bosses D-046 to D-048 and D-057, their views D-050; passengers D-051 and D-059; sound, post effects and subtitles D-052 to D-054; the tells' sounds D-058. A `_reach` to the anchor the hand already rests on does not tick: tick once before a gesture that needs the pointer there. A flag set in `BossSim.step_after_car` must be reported after it in the tick (`_step_set_piece`), not in `_report_soldier`, which runs before the car moves.
- **How long checks take here:** `tools/check.sh` needs about six minutes on an idle machine and three times that beside other work. To go on working while it runs, check a copy: `git archive HEAD | tar x -C <scratch>/chk` and run `tools/check.sh` there (the same for mutation runs, with `MUT_ROOT`). Every test process writes under a folder of its own (`user://test_runs_<pid>`), so several copies can be tested at once. Never wait with `sleep` or a polling loop: start it in the background and read its log when told it is done.

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
- [x] Adversarial review of the M1 core and tests (workflow `m1-review`, on a snapshot of commit a7c3d8a): findings applied (D-030, and what was left on 2026-11-27: D-070); tests strengthened where a mutation survived (`tools/mutants/m1_hand.py`, 108 mutants, all killed)

### M2 Driving: T-CAR-01..05, T-COL-01..03, T-CC-01..02
- [x] `Rng` (road, shop, heckle, bot streams), `CarSim`, `TrafficSim`, `Collision`, thin `NervesSim` and `FaultSim`
- [x] `DriveSim` steps 5 to 7; cash; events `hit`, `lamp_lit`, `close_call`, `wreck`
- [x] Vehicle table (GDD 5.5) in `beats.json`; M2 tuning constants
- [x] The ten M2 tests written, passing and promoted
- [x] Road view: uniform strips plus recycled dashes and posts; `world_bend.gdshader`; pooled vehicle views; flat sky
- [x] Sandbox traffic so the scene can be driven; `artifacts/m2_road.png`
- [x] Review of the M2 core, tests and views (workflow `m2-review`, on a snapshot of commit e197006): findings applied (D-028, D-029, and what was left on 2026-11-27: D-070; `tools/mutants/m2_car.py`, 105 mutants, all killed)

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
- [x] Findings of the review `m6-items-review` (49, four lenses): rulings D-049, built as D-055 (three fix branches and the tests' gaps: 283 checks, 45 mutants); what was seen and left is under "Current state"
- [x] Views: a placeholder per item, the contraband tag, fittings of the Adaptations, moved anchors, the carried object, the ghost hand, the ringing phone, Sway's roll, Lag's trailing hand, HUD rows; `--give=` and `--hud` (D-045; `artifacts/m6_cabin_*.png`)

### M7 Bosses: T-BOSS-01..03, T-CALL-01
- [x] Boss framework (D-046): `BossSim` and its plans, boss numbers and `boss_modifiers` in legs.json, the modifier drawn by seed (`boss_modifier_chance`), `DriveSim.begin_boss`, the tea stall's sign
- [x] The Storm (T-BOSS-02): dust rhythm, gusts, wiper smear and window dust, standing on the shoulder, the weather cramp, Crosswind and Night storm, tail lights
- [x] Dawn, the Call and the Arrival (T-BOSS-03, T-CALL-01; D-047): generated rush traffic that builds, Glare and the visor, the last checkpoint's corridors (`CarSim` walls), the Call's four responses, the street, the bay and the key
- [x] The Checkpoint (T-BOSS-01; D-048): queues in every lane's corridor, the bar, Stow (stowing and taking out by hand), Papers (three documents, the window, the letter), the verdicts, the bribe, Long queue and Thorough; the owed checks of T-ITEM-BREATH-MINTS and T-ITEM-FORGED-PAPERS at the real Checkpoint and of T-PHANTOM-01 in the Storm
- [x] The scripted driver of T-RUN-01 drives every boss for real: the Checkpoint's queue, window and papers, the Storm, Dawn, the Arrival (it parks at 06:02 with seven stops: a third-gear night with every stop is two minutes late)
- [x] Views of the set pieces (D-050): barriers, bars, the soldier and his sign, the bay and the house, gust streaks, the glow and the sun, the cabin's switches (window, hazards, glovebox, letter), the mirror's lights, the phone; `--boss=<id>[,modifier]` and `--boss=arrival`; a stand-in bot that gets through every set piece; smoke runs; pictures `artifacts/m7_*.png`
- [x] Mutation runs: the Storm 38 of 38; the Checkpoint 46 of 54, the eight closed by new checks; Dawn 40 of the first 43, two closed, one equivalent
- [x] Adversarial review of M7 (workflow `m7-review`): four lenses applied (D-057)
- [x] The views lens of that review: V-01, V-02, V-05, V-06, V-07, V-08, V-09, V-10, V-11 (the paint), V-12, V-19 and the sounds of V-03 (D-058)
- [ ] Left open: V-04's cut, V-11's marker, V-14 to V-18 (V-13: D-070); DAWN-01, DAWN-11, STORM-5; four unwritten test cases (see "Current state")

### M8 Passengers: T-PASS-* (5)
- [x] `PassengerSim` and passengers.json (D-051): hitchers at the roadside, the passenger door, the seat and the back seat, rides counted at stalls, fares, guests at arrival, the save
- [x] The Hajjiya, the Conscript, the Drummer, the Student, the Apprentice: five tests; T-DATA-01 knows the new rules
- [x] Views: the figure in the seat, the arm, the drum, the hitcher and their name, HUD rows; `--ride=<id>`; pictures `artifacts/m8_*.png`
- [x] Mutation run of `tools/mutants/passengers.py`: 104 of 104 killed (three lived and were closed by new checks)
- [x] Adversarial review of M8 (workflow `m8-review`, both lenses verified): the rules RULES-01 to 12 fixed (D-059; the mutant list has 169 entries), the drum's place, the lean, the passengers' sounds (D-058)
- [ ] Left open: the test gaps m8tv-08, 09, 10 (see "Current state")

### M9 The frame: T-TABLE-* (7), T-HECKLE-01, T-END-01, T-PROLOGUE-01, T-FINALE-01
- [x] M9a The seven Tables (D-060): `TableRules`, `data/tables.json` (rules as validated keys), the rules in `DriveSim`, `RunState`, `RunGenerator` and `StopSim`; seven tests; T-DATA-01 breaks each rule key once; mutants in `tools/mutants/tables.py`
- [x] M9b Heckles (D-061): `HeckleDirector`, `data/heckles.json` (30 records: the six Tables' and two per passenger), a Twist's stretch laid out by the generator and kept off the road until it is said, the shower, the Fib's ghost hand; T-HECKLE-01 (469 checks); T-DATA-01 breaks each record rule once; mutants in `tools/mutants/heckles.py`; a HUD row and the ghost hand on the wheel
- [x] M9c Endings and persistence (D-062): `Save.ending_of`, `Save.apply_ending`, `Game.end_telling`; T-END-01 (161 checks); `tools/mutants/endings.py` 25 of 25 killed. The modes are earned; playing them is M9e
- [x] M9d Prologue and finale (D-063): `PrologueSim` and `DriveSim.begin_prologue` (75 s to the tick, seven steps by the clock, the left hand keeping the lane, no cost, the cut to tonight with `narrator.start`), `FinaleSim` (eight claps, the walk, "Baba." at 20 s, over only when her hand is let go in front of the groom), `Game.wants_prologue`; T-PROLOGUE-01 (101 checks), T-FINALE-01 (35 checks); T-DATA-01 breaks their numbers; mutants in `tools/mutants/bookends.py`
- [x] M9e The frame on screen (D-064): `scenes/title.tscn`, `scenes/wedding.tscn` (`WeddingView`: the room, the ending's card, the finale, the credits), `Game.go` and the DriveContext, the prologue's overlay (pulse, white-out, cards), solid left arm and props, the Wreck's black cut and the Table's objection, `Narration`, the Commute and Endless Night (`DriveSim.begin_commute`, `begin_endless`; T-END-01 checks them, 211 checks), 217 more lines (502), smoke runs for all of it, pictures `artifacts/m9_*.png`
- [ ] Left open: no adversarial review of M9 (see NEEDS OWNER); the flow between the scenes is run by hand and by the smoke step only

### M10 Presentation and options: T-ONEHAND-01, T-SETTINGS-01, T-SMOKE-ALL
- [x] T-SMOKE-ALL (57 checks): the four scenes, the wedding's states, and `drive.tscn` in each DriveContext kind, 600 frames each headless
- [x] The settings of GDD 17.1 (D-065): `SettingsSpec` from tuning `settings`, `DriveSim.apply_settings`, Brake assist, Steady start, Game speed, shake visuals, the Numeric HUD, the Mirrored cabin (`shaders/mirror.gdshader`), `SettingsView` from the title and from a paused drive; T-SETTINGS-01 (190 checks); mutants in `tools/mutants/settings.py`
- [x] T-ONEHAND-01 (167 checks; D-066): every ritual one of eight gestures at an anchor the pointer reaches, each gesture performed with the left button and nothing else, the brake the right, the pads only the Thumb keypad's, the pause the left button held on nothing (on the road, at a stall, at the officer's window, on the last street; the same night to the bit with it); and `tools/onehand_walk.gd`, a headless walk with mouse events only from the title through its options, a Table, a paused drive, an ending, the finale and the credits (27 steps); mutants in `tools/mutants/onehand.py`
- [x] Generated audio (GDD 16.5; D-052): `SfxSynth`, `Audio`, `data/sfx.json`, the mix; `tools/audio_check.gd` is a step of `tools/check.sh`
- [x] Post effects (GDD 16.4; D-053): `shaders/post_fx.gdshader`, `PostFxView`; `tools/post_fx_check.gd` is a step of `tools/check.sh`; pictures `artifacts/m10_postfx_*.png`
- [x] Subtitles (GDD 16.6; D-054): `SubtitlesView`, `SubtitleQueue`, speaker lines, the two Subtitles settings' keys; `tools/subtitles_check.gd` is a step of `tools/check.sh`; pictures `artifacts/m10_subtitles_*.png`
- [x] The three pieces meet M7 and M8: one place for Dawn's sun (`glare_position`), the ring's subtitle ends with the Call (`until`), the passengers' speakers have their lines, a late answer says nothing
- [x] Review fixes of the three pieces (merged from `m10/<piece>-in-fix`); a sound for every tell of M7 and M8, the dust's tell, a tell's subtitle at once (D-058)
- [x] Mouse-only menus (title, wedding room, pause and settings)
- [ ] Left open: no adversarial review of M10; GDD 17.2's tells for the milestones before M7

### M11 Balance: T-BOT-01, T-WALL-01
- [x] T-WALL-01 (158 checks, about two minutes; D-067): `tests/support/ideal_driver.gd` (third gear, the plan's line, eyes shut) over every leg type in each act and with each modifier (46 legs), Tailgater legs until he has gone by, each kind of Twist, Dawn three times and once slowly, the Commute, four failure cases
- [x] The Tailgater keeps off the road the leg needs (`EncounterSim`: swerves in behind when his lane is blocked, hangs back once left, passes only into a clear window off the plan's line, falls behind after his stab); T-LEG-06 has the cases among traffic (87 checks)
- [x] DAWN-01: Dawn's traffic keeps his pace from the checkpoint's sign until he is back at par (`BossSim.traffic_pace`)
- [x] Mutants: `tools/mutants/wall.py` (17, all killed)
- [x] The DriverBot (GDD 13.8, D-068): `src/game/driver_bot.gd` in place of `stand_in_bot.gd`; three skills from tuning `bot_*`; `--bot=<skill>` and F7 in the drive scene
- [x] The balance runner (`src/game/balance_run.gd`, `tools/run_balance.gd`, `tools/run_balance.sh [seeds] [jobs]`) and its report, `artifacts/balance.json`; T-BOT-01 (145 checks: the skills, reaction, lane keeping, the hand at the lever, the policy, following, one Telling twice, the report's arithmetic, two Tellings by the tool itself); mutants in `tools/mutants/bot.py` (20, all killed)
- [x] A tuning pass, of the bot only: gestures take what GDD 7.4 gives them, eyes that shut, sight that haze, rain and glare shorten, a sense of the Clock (D-068). The numbers of GDD 15 were not touched: see NEEDS OWNER
- [ ] Left open: the bot does not smoke, sip, answer the phone or a heckle, carry a passenger, or take the Motorcade's side road; a run of 100 seeds per skill per Table (some hours) has not been made

### M12 Touch and export: T-TOUCH-01
- [x] Touch (GDD 4.1, 17.4; D-069): `src/game/touch_input.gd` (the thumb is the hand, a TAP performs when the hand arrives, the other gestures need the thumb, the pedal zone, 9 mm targets), `src/view/touch_view.gd`, the drive scene hears `InputEventScreenTouch` and `InputEventScreenDrag`
- [x] The pause's hotspot of GDD 4.1 (top-left corner), for a finger and for the game's own pointer
- [x] `export_presets.cfg`: Windows Desktop, Linux, macOS, iOS (D-016); landscape only
- [x] T-TOUCH-01 (100 checks), with `tools/touch_walk.gd` (the headless drive scene given screen touches); mutants in `tools/mutants/touch.py` (19, all killed)
- [ ] Left open: no export was made (no export templates here); nobody has put a finger on it; the menus work by touch only through the engine's emulated mouse

## Known debts (builder)

- Simulation speed (measured at M5): 45 microseconds per tick on an empty road, 95 on an Open road leg, 130 on a Rush leg with 23 vehicles; a whole Telling of 1,100 s of driving takes about 15 s. Traffic's follow rule was the worst of it and is linear now. A Telling of 20 minutes is about 12 s of CPU; the full balance run of GDD 13.8 (100 seeds x 3 skills x 7 Tables) would take hours. The per-tick Dictionary lookups in `ItemSim.step`, `FaultSim.param` and `EffectSystem.step` are the first things to tighten in M11.

## NEEDS OWNER

Things a human must judge or supply. Nothing here blocks the build.

- **The balance numbers are the owner's to act on** (D-068, `artifacts/balance.json`;
  four seeds per skill per Table, 84 Tellings, 2026-11-27: hands-off time 3.41 s (target 3.4: within); hand off the wheel 10% of the competent bot's Act 2 legs (25% to 40%: outside); expert at the Drivers' Table, no purchases, 3 of 4 won (40% to 60%: outside, on four nights); competent, buying, 4 of 4 (15% to 30%: outside); novice at the Children's Table reaches the Checkpoint 4 of 4 (50% or more: within); Wrecks from one event 0 of 3 (0%: within). Of 84 nights 3 were wrecked (Dawn twice, Roadworks once) and 39 were late; nobody won at Noor's Table). GDD 12.5 says "A human tunes by feel. The bot gives the
  builder numbers before a human plays." The numbers are in; nobody has
  played. They say the road is easier on a bot than GDD 12.5 wants and the
  cabin asks less of its hand. Two things stand between them and a verdict.
  The bot does not do everything a player's hand has to (it does not
  smoke, sip, answer the phone or a heckle), so its hand is idle where his
  would not be. And the numbers that could be turned are those of GDD 15,
  which the tests hold to the letter and section 1.5 puts above everything
  else: changing one is changing the spec. So the "tuning pass" of M11 was
  made on the bot alone, until it plays as a person could; the game's
  numbers were left as written. If the owner wants them moved, say which
  way (harder road, hungrier cabin, shorter night) and the tests that pin
  them will have to be told so.
- **Touch has never met a finger, and nothing was exported** (D-069): no
  phone here and no export templates. The presets carry a placeholder
  bundle identifier (`com.example.i99`) and no Apple team id. The pause has
  three ways now: Esc, the hotspot of GDD 4.1 in the top-left corner, and
  the left button held on nothing (D-066, built before the hotspot's row
  of GDD 4.1 was noticed). Say if the third should go.
- **M9 has had no review.** M1 to M8 each had an adversarial review by
  other agents (GDD 1.4); M9 (Tables, heckles, endings, prologue, finale,
  the scenes) was built alone on 2026-11-27 after the spend limit had ended
  the workflows, and "ultracode" is off. Its rules are held by its eleven
  tests and by 214 mutants (`tools/mutants/tables.py`, `heckles.py`,
  `endings.py`, `bookends.py`), and its readings of the GDD are D-060 to
  D-064. A review like `m8-review` would cost about what that one did; say
  "use a workflow" to have one run.
- **How M9 read the GDD where it had to choose** (each in DECISIONS):
  heckles never *begin* during an encounter, and "an encounter" is the time
  it is at him, not the whole leg (D-061); late beats the Call, and a
  passenger carried to Basra late is a guest all the same (D-062); the
  prologue runs on into the first Telling instead of stopping at the
  wedding room, and letting go of Noor's hand on the way to the groom ends
  nothing (D-063); a wrecked Commute does not count for the best (D-064).
- **M10's settings and the pause have had no review either**, and two
  readings are the owner's to confirm (D-065, D-066): the pointer's way to
  the pause is the left button held for 1.2 s where the hand has nothing
  to hold (someone who misses the wheel's rim and holds the button in the
  air will meet the pause screen; the arc round the pointer is the
  warning); Game speed is the engine's time scale, so a slowed night is a
  slowed clock too.

- **Name.** The project is called I-99 as briefed; the GDD text still says
  Single-Handed (D-002). Confirm, or change the line `title.game_name`.
- **Export targets.** Brief says Windows/iOS/Linux, GDD says Windows, Linux,
  macOS. M12 will ship all four presets (D-016). iOS needs the owner's Apple
  team id and signing to actually build.
- **Lines.** Every English line is a placeholder marked `needs_writer`; the
  Arabic file has the same ids and no text (GDD 1.2).
- **Nobody has heard the game.** There are no speakers here: every level,
  duck depth and pitch in `data/sfx.json` comes from measurement (D-052).
  `godot --headless --path . --script res://tools/audio_check.gd -- --wav=<folder>`
  writes each sound for listening.
- **Sounds beyond the table of GDD 16.5** (D-052, D-058): `horn_behind`,
  `rattle`, and the tells that had only a picture: `gust`, `dust`,
  `soldier_whistle`, `soldier_knock`, `passenger_snore`,
  `passenger_murmur`, `passenger_clink`. Each is one record of
  `data/sfx.json`; rename, replace or strike them there. Still silent on
  purpose: the low sun, the bar, the bay and the key, a hitcher at the
  roadside.
- **The mix** has about 0.8 dB of room under the rule that a functional cue
  stands 6 dB over everything else at once (D-058 deepened the ducks by
  1 dB); a further sound heard at once will want deeper ducks again.
- **Asked again while she holds**, the Hajjiya's 6 s begin anew (D-059):
  with the hand kept on her shoulder and a tap every few seconds the wheel
  is held dead straight for as long as he likes. A pause after she lets
  go would be one number in passengers.json.
- **Night storm** changes nothing a driver with two working headlights can
  measure: the dust is always nearer than the cone (D-046, D-057).
- **The fixes of the reviews were not themselves reviewed** (see "Current
  state"): the skeptics' workflows ended with the spend limit of
  2026-11-20.
- **Subtitles lie over the wheel hub** and the key of the Arrival (bottom
  centre, GDD 16.6); `subtitle_bottom_margin` moves them (D-054).
- **Renderers.** Only the Compatibility renderer under Mesa was ever run:
  the post effects are unseen in Forward+ and Mobile and unmeasured on a
  GPU (D-053).

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
- 2026-11-20 M7: the Checkpoint (T-BOSS-01), built as D-048 has it: stop-and-go queues between barriers, the bar, Stow with stowing by hand, Papers, the verdicts and the bribe.
  The owed checks at the real set pieces are in; the whole-Telling test drives all three bosses for real. All four tests of M7 pass: 92 of 114.
- 2026-11-20 M7: the views of the set pieces, `--boss=`, the stand-in bot through every set piece (D-050). His eyes stay on the road during the Call; the ring is written out as well as heard.
  T-BOSS-01 and T-BOSS-03 gained the checks their mutation runs asked for. Rulings on the M6 review's open questions: D-049.
- 2026-11-20 M8: the five passengers (D-051). Hitchers stand at stops and get in by the passenger door; each has a Hand and Weights from data; a ride is counted at stalls and ends where the car stands.
- 2026-11-20 M8: the passenger mutation list is closed (104 of 104); M8 is pushed. M10: the three parked pieces (sound, post effects, subtitles) are merged over M7 and M8 (D-052 to D-054).
  At the merge: the passengers' four speakers got their lines; the ring's subtitle ends with the Call; the sky and the post effects share one sun (`glare_position`); the validator asks for a speaker's line.
- 2026-11-20 M6 review: `m6fix/seams` and `m6fix/rituals` are merged (the night waits at a stop and with the officer; requirements asked again at completion; the tape past the dial).
  The parse check now fails on a listener that names an event the simulation never announces (it found "wrecked" in the drive controller).
- 2026-11-20 M7 review: the Checkpoint's, the Storm's and Dawn's findings fixed on the main line, each with a failing check first (D-057); the tests lens's 34 checks taken in.
  Standing in the Storm cannot be dodged with the pedal; the 70 holds between Dawn's barriers; the end of the Call's talk has a tell; the key parks the car.
- 2026-11-20 M10: the subtitles' review fixes merged; a tell's subtitle takes the screen at once. M7 and M8: a sound for every tell (D-058): gust, the dust closing in over its last thin second, the soldier's whistle and knock.
  M6: the third fix branch and 283 new checks merged (D-055); a Wreck in the tick he pulls in at a stall is a Wreck. Each test process keeps to a user folder of its own. The spend limit then ended six workflows.
- 2026-11-27 What the stopped workflows had finished is in: the M8 rules fixes (D-059), the post effects review fixes, V-01 and V-05 of the M7 views lens. On the main line: the passengers' sounds, V-07, V-10, V-11, V-19.
  The review reports are kept in `docs/reviews/`; every mutant list applies again. Paused as asked: next is M9. 97 of 114.
- 2026-11-27 M9a: the seven Tables (D-060). Each Table's rule is a validated key of its record; the Children's rewind returns him to the leg's start as it was; the Uncles' Patrol is one place per act on both branches;
  Noor's road is nine named legs under one seed, with no fork to take, tea and repairs only, and the Student at Act 2's second stop. 104 of 114.
- 2026-11-27 M9b: the heckles (D-061). One per leg in Act 1 and two after, each said at its place when the leg's encounter is not at him; two seconds of subtitle, then the Twist's stretch comes onto the road (laid out by the generator with the leg),
  or the Dare, Doubt, Question or Order runs, or the Fib's ghost hand holds the lane. Guests bring two heckles each. 105 of 114.
- 2026-11-27 M9c: endings and what persists (D-062). Late beats the Call; a win opens the next Table and the first one the Commute; the Call marks the Table told true, earns Endless Night and at Noor's Table starts the finale;
  whoever is beside him when the key is turned is a wedding guest. The profile is written with no Telling to continue. 106 of 114.
- 2026-11-27 M9d: the two bookends as simulations (D-063). The prologue is a mode of the drive: 75 s to the tick, seven steps by the clock, a left hand that keeps the lane, nothing that costs, and a cut into tonight's Telling with the narrator's first line.
  The finale ends only when her hand is let go in front of the groom. Every Telling begins with `narrator.start`. 108 of 114: all of M9's tests pass; its scenes are M9e.
- 2026-11-27 M9e: the frame on screen (D-064). `title.tscn` and `wedding.tscn` (the room of Tables, the ending's card, the finale, the credits), `Game.go` with a DriveContext, the prologue's pulse, left arm, white-out and cards, the Wreck's black cut and the Table's objection,
  the narrator and the stalls between the heckles, the Commute and Endless Night, 217 more lines. The M9d commit by itself fails the subtitles step (two checks assumed a silent start to a night); this one fixes them. 108 of 114: M9 is built; the rest of M10 is next.
- 2026-11-27 M10: T-SMOKE-ALL passes (109 of 114). The mutants that had lived were killed by the new checks (heckles 11 of 11, tables, bookends); ten entries of older lists that M9's edits had made stale were rewritten: 683 mutants in fourteen lists, all applying.
- 2026-11-27 M10: the settings of GDD 17.1 (D-065): data, a screen, and each with its effect, changed mid-Telling. Brake assist slows the car when a crash is certain; Steady start (on by default) holds the wheel straight for 2 s after a stop;
  the Mirrored cabin reverses the picture and the pointer; Game speed is the engine's time scale. T-SETTINGS-01 passes: 110 of 114.
- 2026-11-27 M10: one hand, two buttons (D-066). The pointer's way to the pause is the left button held where the hand has nothing to hold: the game's gesture, not the simulation's, so it works at a stall, at the officer's window and on the last street,
  where a pause on the ignition key (built first) broke T-STOP-01, T-LEG-07 and T-BOSS-03. A headless walk clicks from the title through a night's pause to the credits with mouse events only. T-ONEHAND-01 passes: 111 of 114. M10 is built; M11 is next.
- 2026-11-27 M11: T-WALL-01 (D-067). The scripted driver (third gear, the plan's line, no brake, no eyes) cleared 210 legs of every kind untouched, except the Tailgater's: he was held in place through traffic, cut in where he could not get away and stayed in front on the line.
  He now swerves in behind when his lane is blocked, hangs back once the lane change is held, passes only into a clear window off the line and falls behind after his stab. Dawn's traffic keeps the driver's pace through the last checkpoint (DAWN-01). 112 of 114.
- 2026-11-27 M11: the DriverBot and the balance runner (D-068). Three skills play whole Tellings through the input: a reaction delay, a lane-keeping error, one hand that leaves the wheel only when the road allows. The competent and the expert bot read the way the traffic leaves open; the novice only reacts, and is late.
  It found two things in the game: on Dawn's waiting road the brake did not open a gap (fixed, D-067), and nothing else. Report of 84 Tellings in `artifacts/balance.json`: wins well above GDD 12.5's targets, the hand off the wheel 10% of the time where 25% to 40% is wanted. T-BOT-01 passes: 113 of 114.
- 2026-11-27 M12: touch and export (D-069). The thumb is the hand; a TAP performs when the hand arrives, the other gestures need the thumb; a pedal zone at the bottom left; targets 9 mm across; the pause's hotspot of GDD 4.1 in the top-left corner, for a finger and for the pointer; four export presets.
  A headless drive scene is played with screen touches. T-TOUCH-01 passes: 114 of 114. Every milestone of GDD 18 is built.
- 2026-11-27 M11, M12: mutation runs on the three new lists (wall 17, bot 20, touch 19): eleven mutants lived at first and each got a check that kills it (the Tailgater among traffic, the brake on Dawn's waiting road, the bot's following distance and standing traffic, a late night's outcome, the far crank by touch); two were equivalent and are noted in their lists.
  784 mutants in nineteen lists apply to the code as it is. `tools/check.sh` prints CHECK OK on b6d43e8.
- 2026-11-27 M1 and M2: what was left of the first two reviews (D-070; the owner: "Finish it"). The validator holds the controls to the table of GDD 4.6; a placeholder the code draws takes no scene; the pointer's ring is drawn where the pointer points.
  1,014 mutants in 22 lists apply to the code as it is. Two mutation lists for the first two milestones (the hand, wheel, gate and gestures: 108; the car, traffic, collisions and close calls: 105): 52 mutants lived, 45 got a check that kills them and 7 are equivalent and named. 381 checks added, none removed. The task list is empty.

