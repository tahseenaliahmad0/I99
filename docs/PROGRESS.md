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

- **Milestone:** M1 (The Hand and the wheel), in review.
- **Tests:** 2 of 114 registered passing; the eight M1 tests pass and wait for the review before promotion.
- **Next step:** apply the findings of the `m1-review` workflow, promote, commit, push. Then M2.

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
- [ ] Adversarial review of the M1 core and tests (workflow `m1-review`), fixes applied
- [ ] Tests promoted; M1 committed and pushed

### M2 Driving: T-CAR-01..05, T-COL-01..03, T-CC-01..02
- [ ] not started

### M3 Nerves and the base cabin: T-NERVES-01..04, T-FAULT-01..02, T-ITEM-BASE
- [ ] not started

### M4 Legs and encounters: T-GEN-01..03, T-SUS-01, T-LEG-01..09
- [ ] not started

### M5 A whole Telling: T-RUN-01..02, T-CLOCK-01, T-STOP-01, T-SAVE-01, T-REPLAY-01
- [ ] not started

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
