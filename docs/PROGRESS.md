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

- **Milestone:** paused, as the owner asked on 2026-11-20 ("finish M6, M7, M8 and M10, then pause"; read in D-056 as the work in flight on those four). M6 (items), M7 (bosses) and M8 (passengers) are built and reviewed, and what their reviews found is applied but for the open findings below. Of M10 the three presentation pieces are in and reviewed: sound, post effects, subtitles. **The next milestone is M9** (the frame); the rest of M10 (the eleven settings of GDD 17.1, mouse-only menus, T-ONEHAND-01, T-SETTINGS-01, T-SMOKE-ALL) needs M9's scenes and comes after it.
- **Tests:** 97 of 114 passing (M0: 2, M1: 8, M2: 10, M3: 7, M4: 13, M5: 6, M6: 42, M7: 4, M8: 5). `tools/check.sh` has eight steps (import, parse with the core and event-name lints, data, audio, tests, subtitles, smoke, postfx) and prints `CHECK OK`.
- **How the last session ended.** On 2026-11-20 the account's monthly spend limit stopped six workflows in mid-run. What their agents had finished was taken in by hand on 2026-11-27: the M8 rules fixes (`m8fix/rules`, complete), the M6 test gaps (`m6fix/tests`, complete), the post effects review fixes (uncommitted in the agent's worktree; committed, merged, pictures retaken and looked at), and of the M7 views fixes V-01 and V-05. **What never ran and is still owed, if the owner wants it:** a skeptic's check of the fixes themselves. The fixes of D-055, D-057, D-058 and D-059, and the post effects fixes, are held by their own tests and mutants and by nothing else: no second agent tried to break them. The workflows' local branches (`m6fix/*`, `m7fix/views`, `m8fix/rules`, `m10/*-in-fix`) hold nothing that is not merged; they are not pushed and need not be.
- **The reviews' reports** are in `docs/reviews/` (one JSON per lens, with the GDD sentence, evidence and proposed fix of each finding). The probes they name are gone with the scratch folder.
- **Open findings, by milestone** (ids as in the reports):
  - *M7, the views lens* (`m7_review_views.json`): V-04, the verdicts are said in a line, but being turned back is still an uncut jump of 346 m and half an hour (a short cut through the post effects on `pulled_over` with minutes would do); V-11 (b), standing in the bay shows nothing in the forward view (the key's marker is below the frame: move the `key` anchor of anchors.json into it); V-13, the bar, the barriers, their caps and the bay's paint are built from the registry's size and colour and cannot be replaced by an artist's scene; V-14, numbers in view and game code (`_mirror_proud * 1.5`, `LIFT_PAINT`, `LIFT_LINE`, the gust's `_tell * 0.5`, the stand-in bot's 17 constants); V-15, the numeric HUD prints a nameless Leg row in a set piece and raw ids (`alone`, `parked`, what is carried); V-16, `--boss=` drops arguments it cannot use without a word, and after a Wreck every further round of a set piece begins wrecked; V-17, the stand-in leaves the window and the glovebox open after the Checkpoint (60% Haze in every Storm of a whole stand-in Telling) and takes every Exit; V-18, no smoke run puts the mirror's lights, the Patrol's blue, the phone at his ear or a searched Checkpoint on screen (the agent's unfinished `tools/views_check.gd` was not kept).
  - *M7, the rules* (D-057): DAWN-01, after Dawn's last checkpoint traffic is laid out for a driver at par (walls of vehicles during the Call for a slower one: with T-WALL-01 in M11); DAWN-11, a car across a lane line where the barriers begin is put into the lane its middle is in, up to half a car's width in one tick (the shoulder's 3.2 m jump is fixed, V-05); STORM-5, Night storm changes nothing a driver with two headlights can measure (NEEDS OWNER). Of the tests lens, cases named and not written: a standing car 5 cm short of wholly off the lanes; the 30 s of the Call timed in the three cases where he does not pull over; the generator's plan driven through Dawn's barriers; a Telling whose Checkpoint has a modifier.
  - *M8* (D-059): the test gaps m8tv-08, m8tv-09 (c to g) and m8tv-10 (seventeen clauses of GDD 8 and D-051 with no check; the build is right in each today). RULES-13 is the owner's (below).
  - *M6* (D-055): the fix branches were never reviewed. Seen by their agents and left: an item's `params` and its `lapse` are not checked by the validator; a phone taken out of the cabin while it rings ends its call without `call_resolved`; the stand-in at the wheel hands a Patrol's officer nothing and waits there for ever; `DriveSim._use_control` announces a keypad ritual without asking whether it ran; a stop reorders the cabin's list.
  - *M10*: GDD 17.2 was gone through for the tells of M7 and M8 only (D-058); the earlier milestones' tells (a curve's sign has no sound, the yawns and the Phantom's hum no picture) belong to the rest of M10. The post effects fixes have had no review of their own.
  - *M1 and M2* (reviews of 2026-11-17, never finished): (a) M2 views: pointer ring drawn at the hand's clamped target; the hand does not follow the gear knob; forearm stretches beyond 0.30 m for five far anchors (decision not recorded); `scene` in placeholders ignored for road strips, arm and pointer. (b) M1 test honesty (18): no test moves the pointer with relative motion; T-WHEEL-01 never releases a turned wheel; grip and ride on an off-centre wheel; gate engage radius and grind band probed from one side; FLICK time and direction limits; CRANK angle-not-distance; gate channel width; camera pitch and glance following the hand; pointer pixels to screen; steering sensitivity wiring; loose brackets on timing limits; literals standing in for tuning values. (c) M1 gesture: rituals.json is not checked against the table of GDD 4.6. (d) M2 test honesty leftovers (see D-028 and D-029 for what was done). M3, M4 and M5 have not been reviewed.
- **Next step:**
  1. `tools/check.sh` must print `CHECK OK` (about six minutes on an idle machine).
  2. **M9, the frame** (GDD 11, 3, 10.1, 10.6): wedding room, seven Tables, heckles, lines, endings, persistence, prologue, finale, modes; tests T-TABLE-* (7), T-HECKLE-01, T-END-01, T-PROLOGUE-01, T-FINALE-01. Heckle lines are tells: ask for them with `"tell": true` (D-058). A Wreck that only rewinds (the Children's Table) must leave the save file alone (D-055).
  3. Then the rest of M10, M11 (the DriverBot replaces `src/game/stand_in_bot.gd`; T-WALL-01 with DAWN-01), M12.
  The open findings above can be taken at any time; each needs a check that fails first.
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
- [ ] Left open: V-04's cut, V-11's marker, V-13 to V-18; DAWN-01, DAWN-11, STORM-5; four unwritten test cases (see "Current state")

### M8 Passengers: T-PASS-* (5)
- [x] `PassengerSim` and passengers.json (D-051): hitchers at the roadside, the passenger door, the seat and the back seat, rides counted at stalls, fares, guests at arrival, the save
- [x] The Hajjiya, the Conscript, the Drummer, the Student, the Apprentice: five tests; T-DATA-01 knows the new rules
- [x] Views: the figure in the seat, the arm, the drum, the hitcher and their name, HUD rows; `--ride=<id>`; pictures `artifacts/m8_*.png`
- [x] Mutation run of `tools/mutants/passengers.py`: 104 of 104 killed (three lived and were closed by new checks)
- [x] Adversarial review of M8 (workflow `m8-review`, both lenses verified): the rules RULES-01 to 12 fixed (D-059; the mutant list has 169 entries), the drum's place, the lean, the passengers' sounds (D-058)
- [ ] Left open: the test gaps m8tv-08, 09, 10 (see "Current state")

### M9 The frame: T-TABLE-* (7), T-HECKLE-01, T-END-01, T-PROLOGUE-01, T-FINALE-01
- [ ] not started

### M10 Presentation and options: T-ONEHAND-01, T-SETTINGS-01, T-SMOKE-ALL
- [x] Generated audio (GDD 16.5; D-052): `SfxSynth`, `Audio`, `data/sfx.json`, the mix; `tools/audio_check.gd` is a step of `tools/check.sh`
- [x] Post effects (GDD 16.4; D-053): `shaders/post_fx.gdshader`, `PostFxView`; `tools/post_fx_check.gd` is a step of `tools/check.sh`; pictures `artifacts/m10_postfx_*.png`
- [x] Subtitles (GDD 16.6; D-054): `SubtitlesView`, `SubtitleQueue`, speaker lines, the two Subtitles settings' keys; `tools/subtitles_check.gd` is a step of `tools/check.sh`; pictures `artifacts/m10_subtitles_*.png`
- [x] The three pieces meet M7 and M8: one place for Dawn's sun (`glare_position`), the ring's subtitle ends with the Call (`until`), the passengers' speakers have their lines, a late answer says nothing
- [x] Review fixes of the three pieces (merged from `m10/<piece>-in-fix`); a sound for every tell of M7 and M8, the dust's tell, a tell's subtitle at once (D-058)
- [ ] Settings of GDD 17.1 (eleven, each with its effect, saved and loaded, changed mid-Telling): waits for M9 (D-056). Only `subtitle_size` and `subtitle_background` exist.
- [ ] Mouse-only menus (title, wedding room, pause and settings): waits for M9
- [ ] T-ONEHAND-01, T-SETTINGS-01, T-SMOKE-ALL: wait for M9's scenes

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
