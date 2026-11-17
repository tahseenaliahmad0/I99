Godot 4.7.2 is installed as `godot`. There's no display, so always run it headless:
- Import project: `godot --headless --path . --import`
- Run a script/tests: `godot --headless --path . --script res://path/to/script.gd`

# Working on I-99

The specification is `docs/GDD.md`. State lives in `docs/PROGRESS.md`,
`docs/DECISIONS.md`, `tests/tests.json` and git. Read GDD 1.3 to 1.6 before
touching code; the rules below are the ones that bite most often.

## Commands

- Everything: `tools/check.sh` (import, parse check + core lint, data validator, tests, smoke).
- Tests: `godot --headless --path . --script res://tests/run_tests.gd -- --only=T-HAND --verbose`
  (after adding a `class_name`, run the import first).
- A throwaway probe: write `probe.gd` (`extends SceneTree`, work in `_initialize()`,
  end with `quit()`) anywhere outside the project and run
  `godot --headless --path <project> --script /abs/path/probe.gd`.
- The engine API as XML is in `docs_api/` (git-ignored). Search it before using
  a class or method you are unsure of. Prefer APIs that have existed since 4.3.

## Code rules

- GDScript with static typing everywhere. Untyped declarations and unsafe
  (Variant) method, property and argument use are compile errors here. Read
  JSON values through `GameData.as_float/as_int/as_string/as_bool/as_dict/as_array`.
- All gameplay lives in pure classes under `src/core` (no Node, no autoload, no
  wall clock, no global random functions, no `Array.shuffle`/`pick_random`),
  stepped at a fixed 120 Hz by `DriveSim.step(input)`. Views read
  `DriveSim.snapshot()` and never change state.
- Every number and every content record lives in `data/*.json`. No tuning
  literals in code: read them with `tuning.f("name")` once, in `configure()`.
  Names in `tuning.json` are those of GDD 15, exactly, with their units.
- Every player-facing string goes through `Lines.get_text(id)`.
- Use the vocabulary of GDD 1.6 in identifiers (Telling, Table, Leg, Beat,
  Anchor, Reach, Ritual, Gesture, Nerves, Awake, Lamp, Fault, Suspicion, ...).
- When the spec is silent or contradicts itself, apply GDD 1.5 and record the
  decision in `docs/DECISIONS.md`.

## Test rules

- Tests are append-only (GDD 1.4 rule 4). Never delete, skip or loosen one.
- A test is a method on a `tests/test_*.gd` suite that `extends TestSuite`,
  named after its id: `T-HAND-01` is `test_hand_01()`.
- A test must establish the `passes_when` text of its entry in `tests/tests.json`,
  with failure cases, and read its numbers from tuning or data, not from
  literals of its own.
- A test passes only if every check passes, at least one check ran, and no
  engine or script error was logged while it ran.
