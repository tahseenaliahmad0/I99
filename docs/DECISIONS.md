# DECISIONS

Decisions the builder made where the GDD is silent, ambiguous or contradicts
itself (GDD 1.4 rule 7, applying GDD 1.5). Newest last. Each entry says what
was decided and why, so a later session or the owner can overturn it knowingly.

Format: `D-NNN (milestone, date) Title` then Context / Decision / Why.

---

## D-001 (M0, 2026-11-17) Engine version

- **Decision.** The build targets **Godot 4.7.2.stable.official.ed1daf0bf**
  (`godot --version`). GDScript only, no addons, no C#, no GDExtension.
- **Why.** GDD 13.1 asks for 4.7.x stable and for the exact version to be
  recorded here.

## D-002 (M0, 2026-11-17) The game is called I-99

- **Context.** The owner's brief names the game "I-99 (previously named
  Single-Handed)". The GDD still says Single-Handed throughout.
- **Decision.** The project name is `I-99` (`application/config/name`) and the
  player-facing title is the line `title.game_name`. `docs/GDD.md` is left as
  the owner wrote it; wherever it says Single-Handed it means this game.
- **Why.** The owner's brief is newer than the document. Keeping the name in
  the line database means a later rename is a one-cell edit.

## D-003 (M0, 2026-11-17) "First session is M0 only" versus "do not stop early"

- **Context.** GDD 1.4 rule 2 says the first session is M0 only. The owner's
  brief says the task spans many context windows and must not stop early.
- **Decision.** M0 is finished and committed as its own unit, with nothing
  from M1 in it. Work then continues with M1 and onward. Every new context
  window is treated as a new session and starts with the routine of GDD 1.4
  rule 1 (also written at the top of `PROGRESS.md`).
- **Why.** The point of rule 2 is that the harness exists and is committed
  before any gameplay is written. That is kept. Stopping after M0 would break
  the owner's direct instruction.

## D-004 (M0, 2026-11-17) Test registry and runner semantics

- **Decision.**
  - `tests/tests.json` holds one entry per line: `id`, `milestone`, `status`
    (`failing` or `passing`), `source`, `passes_when`.
  - A test is a method on a `tests/test_*.gd` suite, named after its id:
    `T-HAND-01` is `test_hand_01()`, `T-ITEM-TEA-GLASS` is
    `test_item_tea_glass()`.
  - A test passes when every check passes, at least one check ran, and no
    engine or script error was logged while it ran (a `Logger` trap; GDScript
    has no exceptions, so a crashed test would otherwise look green).
  - Runner outcomes: `PASS`, `FAIL` (registered passing, now failing: exit 1),
    `NEW` (registered failing, now passing: exit 1 until promoted with
    `-- --promote`), `TODO` (implemented, still failing), `PEND` (not written).
  - `-- --promote` only ever turns `failing` into `passing`. The runner also
    compares the registry with `git show HEAD:tests/tests.json` and fails if
    an id vanished or a passing test went back to failing.
  - `tools/check.sh --final` additionally requires every test to be passing.
    That is the gate for GDD 18.2.
- **Why.** GDD 1.4 rules 2 and 4: ids are registered up front as failing and
  the set is append-only. Making the tool enforce it removes the temptation.

## D-005 (M0, 2026-11-17) Test ids for the wildcard families and for tests the GDD names but does not define

- **Context.** GDD 18 lists families (`T-ITEM-*` one per item, `T-SYN-*` one
  per synergy, `T-PASS-*` one per passenger, `T-TABLE-*` one per Table) and
  several ids with no row in 18.1 (for example T-HAND-03, T-WHEEL-02,
  T-GEST-01, T-CAR-05, T-CC-01, T-NERVES-04, T-FAULT-02, T-ITEM-BASE,
  T-GEN-03, T-LEG-01 to 09, T-RUN-01/02, T-STOP-01, T-SAVE-01, T-PHANTOM-01,
  T-BOSS-01 to 03, T-HECKLE-01, T-END-01, T-PROLOGUE-01, T-SETTINGS-01,
  T-SMOKE-BOOT, T-SMOKE-ALL, T-TOUCH-01).
- **Decision.** 114 ids are registered. Families are expanded from Part II:
  32 items (11 Habits, 7 Keepsakes, 10 Adaptations, 4 Deals; the arak flask is
  one item sold as a Deal), 9 synergies, 5 passengers, 7 Tables. T-LEG-01 to
  09 follow the order of the table in GDD 9.1. Every id without a row in 18.1
  has a `passes_when` written by the builder from the matching rules in
  Part II, marked `"source": "builder (DECISIONS D-005)"`. The registry text
  is the definition; a test may check more than its text, never less.
- **Why.** "Register every test id from section 18" needs concrete ids on day
  one, and an id with no definition cannot be failed or passed honestly.

## D-006 (M0, 2026-11-17) Static typing is enforced by the engine

- **Decision.** `project.godot` turns these GDScript warnings into errors:
  `untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`,
  `unsafe_call_argument`, `unassigned_variable`, `standalone_expression`.
  A script that breaks one does not compile, so the parse check fails.
- **Why.** GDD 1.3 demands static typing everywhere. With no editor in the
  loop, compile-time checking of every call is also the cheapest bug filter.
  Consequence: JSON values (Variant) are read through typed helpers
  (`GameData.as_float` and friends, `Tuning.f/i/b/s`).

## D-007 (M0, 2026-11-17) `Lines.get(id)` is spelled `Lines.get_text(id)`

- **Context.** GDD 17.3 says all text comes through `Lines.get(id)`.
- **Decision.** The lookup is `Lines.get_text(id)`, with `Lines.get_speaker(id)`
  beside it.
- **Why.** `get` is a native `Object` method; GDScript refuses to override it.

## D-008 (M0, 2026-11-17) Smoke tests run with `--fixed-fps 60`

- **Context.** GDD 13.10 gives `godot --headless --path . <scene> --quit-after 600`.
- **Decision.** The smoke tools add `--fixed-fps 60`.
- **Why.** Headless without it, 600 frames take over 4 s of wall time and
  cover an unpredictable amount of game time. With it they take about 0.3 s
  and always cover exactly 10 s of game time (1,200 simulation ticks).

## D-009 (M0, 2026-11-17) Events carry one Dictionary

- **Decision.** Every signal on the `Events` bus (GDD 13.6) has the signature
  `(data: Dictionary)`. The pure simulation queues events as dictionaries and
  the drive controller forwards them with `Events.emit_event(name, data)`.
- **Why.** The simulation cannot touch an autoload (GDD 1.3), so events must
  cross the boundary as data anyway. One shape keeps 31 signals uniform.

## D-010 (M0, 2026-11-17) Shape of the data files

- **Decision.**
  - Record files (`items`, `rituals`, `legs`, `beats`, `modifiers`, `stops`,
    `passengers`, `tables`, `heckles`, `faults`) are
    `{ "version": 1, "<name>": [ records with "id" ] }`.
  - `beats.json` also holds `"vehicles"` (the traffic table of GDD 5.5) and
    `anchors.json` also holds `"points"` (G, W, eye, shoulder) and `"slots"`
    (GDD 7.1). The GDD names no file for vehicles or slots and forbids
    inventing new ones lightly; these are the files that already use them.
  - `placeholders.json` and `sfx.json` are plain maps of id to entry, exactly
    as the GDD 14 example shows, so an artist edits one obvious thing.
  - `tuning.json` groups constants for the reader (`hand_wheel`, `car`,
    `collisions`, `nerves`, `car_cash_clock_law`, `structure`); code sees one
    flat namespace. Names and values are those of GDD 15 exactly, including
    units (for example `wheel_smoothing` is 60, in ms). `_units` documents
    them and feeds the F2 panel.
  - Bosses, when they arrive, are records in `legs.json` (a boss is driven in
    the same scene as a leg and its numbers need a home).
- **Why.** GDD 1.3 (every number in data), GDD 13.2 (the sixteen named files),
  GDD 1.5 rule 4.

## D-011 (M0, 2026-11-17) Content arrives with its milestone; T-DATA-01 grows with it

- **Context.** T-DATA-01 belongs to M0, but most content rows of Part II
  belong to later milestones.
- **Decision.** M0 ships the complete `tuning.json` (GDD 15), `anchors.json`
  (GDD 16.2), `faults.json` (GDD 6.3) and the eleven lines of GDD 3.6. The
  other files start empty and fill up in the milestone that implements them.
  T-DATA-01 proves the validator in two ways: the shipped data validates, and
  a fixture built from the GDD 14 examples validates while each deliberately
  broken variant of it is rejected with the right error code. Completeness
  checks ("all nine legs exist") are added to the validator as content lands;
  that only ever makes T-DATA-01 stricter.
- **Why.** Vertical slices (GDD 1.4 rule 3): data and the code that reads it
  are designed together, so the schema is not guessed months early.

## D-012 (M0, 2026-11-17) Files beyond the GDD 13.2 list

- **Decision.** The folder list in GDD 13.2 is read as the required minimum,
  not a closed set (13.5 itself names `drive_controller.gd`, which 13.2 does
  not list). Added so far: `src/core/game_data.gd` (loads `res://data`),
  `src/core/data_validator.gd`, `src/game/boot.gd`, `tests/support/*`
  (suite base class, error trap, smoke helper), `tools/*.gd` (parse check,
  validator CLI, smoke runner, file lister).
- **Why.** None is a new system, resource or screen (GDD 1.5 rule 4); each is
  plumbing the named deliverables need.

## D-013 (M0, 2026-11-17) Line CSV files are kept, not imported

- **Decision.** `data/lines_*.csv.import` set `importer="keep"`.
- **Why.** Godot otherwise treats any CSV as a translation table and writes
  junk `.translation` files, because our columns are `id, speaker, text,
  needs_writer` (GDD 14), not locales.

## D-014 (M0, 2026-11-17) `--user-dir=` for test isolation

- **Decision.** Besides the arguments of GDD 13.9, the game accepts
  `--user-dir=<path>`: settings and saves go there instead of `user://`.
  Smoke tests pass a folder under `user://test_runs/`, which the runner
  empties.
- **Why.** Tests must not read or clobber the player's save, and must not
  depend on what an earlier run left behind (for example `prologue_seen`).

## D-015 (M0, 2026-11-17) Screenshots without a GPU

- **Context.** GDD 1.4 rule 5: save a screenshot to `artifacts/` if a display
  is available. The build machine has no display and no Vulkan driver, but it
  has Xvfb and Mesa's software OpenGL.
- **Decision.** Screenshots are taken with
  `xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 ...`.
  The project itself stays on Forward+ (GDD 13.1). `tools/check.sh` never
  needs a display.
- **Why.** It is the only renderer that runs here, and GDD 13.1 already
  limits the game to features the simpler renderers support. Pictures taken
  this way show layout and colour, not final lighting.

## D-016 (M0, 2026-11-17) Export targets

- **Context.** GDD 18 (M12) lists export presets for Windows, Linux and
  macOS. The owner's brief says the game is for "Windows/IOS/Linux".
- **Decision.** M12 will ship presets for Windows, Linux, macOS and iOS.
  T-TOUCH-01 says so.
- **Why.** Touch is already in scope (GDD 17.4), so an iOS preset adds no
  system. Shipping both readings of the brief costs one preset.
