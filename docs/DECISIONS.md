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

## D-017 (M1, 2026-11-17) The pointer is a direction into the cabin

- **Context.** GDD 4.2 calls the pointer "a 2D position on screen" that snaps
  to anchors within 60 px. But half the anchors of GDD 16.2 are not on the
  screen when he looks straight ahead with a 75 degree view: the gear lever
  and the cups are below it, the driver's window is left of it, and the
  passenger's shoulder is exactly beside the eye (90 degrees off the forward
  axis), where no flat projection reaches. The glance (GDD 4.7) also turns
  the camera as the hand moves, which would slide every anchor out from under
  a screen-fixed pointer mid-reach.
- **Decision.** The pointer is kept in reference pixels (the pixels of a
  1080-high view) as an angular map of directions from the eye:
  `yaw = (x - cx) / k`, `pitch = -(y - cy) / k`, with `k = 540 / tan(fov / 2)`.
  At the centre of the view one pointer pixel is one screen pixel.
  The pointer may leave the screen rectangle; its range is
  `pointer_yaw_min/max`, `pointer_pitch_min/max`. `anchor_snap_radius` is
  measured in this space. The pointer does not move when the eyes glance: it
  stays on the same spot of the cabin, and the view draws it where that spot
  is on screen. With no anchor in range the hand goes to the point under the
  pointer on the plane `hand_plane_distance` in front of the eye, clamped to
  the box `hand_free_bounds_min/max` so a sideways pointer cannot send the
  hand out of the car.
- **Why.** It is the simplest model in which every anchor of GDD 16.2 can be
  pointed at with mouse motion alone, on any window shape (GDD 1.1), and in
  which a reach is stable while the eyes follow the hand. `CabinSpace` holds
  all of it.

## D-018 (M1, 2026-11-17) How the gear gate reads GDD 4.5

- **Decision.**
  - The lever rides rails: the neutral channel (y = 0) and one vertical
    channel per column. `gate_channel_half_width` is how close to a junction
    the lever must be to change rail.
  - Per tick the lever follows the stronger component of the pointer motion
    along its rail. If that way is shut it slides the other way, as a real
    lever slides along a gate wall.
  - "Pushes more than 1 unit into a wall" counts only motion that moves the
    lever not at all. The stop at the far end of a gear's own slot is not a
    wall: pushing the lever home, however hard, never grinds.
  - The engaged gear becomes neutral as soon as the held lever leaves
    `gate_engage_radius` of it; a gear engages only on release.
  - A release at 0.3 to 0.8 units along a vertical channel grinds and springs
    back to neutral; below 0.3 it springs back silently; from 0.8 it engages.
  - With the assist setting, FLICK up and FLICK down on the lever shift one
    gear at a time and never grind (`GearGate.shift_sequential`).
- **Why.** GDD 4.9 asks for the generous reading of the fiddly dials. A
  literal reading would grind on every enthusiastic shift and on every
  diagonal stroke, which punishes the player for the mouse, not for a
  mistake. Mis-aimed shifts (the wrong slot, a push at a wall, a release
  half-way) still grind, which is what 4.5 describes.

## D-019 (M1, 2026-11-17) `--aim=` and `--shot=` for pictures

- **Decision.** Two more arguments for the build's own use: `--aim=<anchor>`
  holds the pointer on an anchor without a mouse, and `--shot=<file.png>`
  saves one rendered frame (after `screenshot_frame` frames) and quits.
- **Why.** GDD 1.4 rule 5 asks for screenshots in `artifacts/`. There is no
  mouse on the build machine, and the screenshots must be repeatable.

## D-020 (M1, 2026-11-17) Details of the hand the GDD leaves open

- **Buffered press.** A press is remembered for the anchor the pointer was
  snapped to when it was made. It is applied when the hand arrives there
  within `input_buffer`; it is dropped if the pointer leaves that anchor. A
  click made and released during the reach still counts as a TAP on arrival.
- **Left side.** Any straight stretch with an end left of the hub (x < 0)
  runs at `hand_left_side_mult`; W itself (x = 0) counts as the right side.
  The hand changes sides only through W, in both directions, also when it is
  following a free pointer.
- **Wheel.** The wheel is a disc in the plane z = 0. "Pointer on the wheel"
  means the pointer's ray meets that plane inside the grip zone
  (`wheel_radius` plus or minus `grip_zone_half_width`). The rim is a place
  to point at like an anchor: where the pointer is nearer to the rim's
  centre line than to an anchor in range, the rim wins. (Amended after the
  M1 review: with "the anchor always wins", his own face and the stalks took
  57 of the rim's 360 degrees, and a press there after a right turn was a
  slap, not a grip.)
- **Toggle grip.** In toggle mode only a click on the rim asks for the
  wheel; the click that lets go does not take it again while it is held.
- **Glance.** The camera turns toward the hand along the shortest arc by
  `glance_gain` of the angle beyond `glance_start`; the result is then
  clamped to `glance_max_yaw` and to `glance_max_pitch` downward. The eyes
  never glance upward (GDD 4.7 only caps downward pitch).
- **Pinning.** While a gesture other than DRAG_TO is in progress the pointer
  is pinned, as it is while gripping (GDD 4.3), so a FLICK or a CRANK moves
  the object, not the hand.
- **Co-located anchors.** `radio` and `tape` share a position (GDD 16.2).
  The tape deck stays inactive until a Mixtape is fitted (M6).

## D-021 (M1, 2026-11-17) Details of the gestures the GDD leaves open

- **FLICK** must reach `flick_min_distance` while the button is down; a
  release before that cancels. A ritual may accept several directions (the
  indicator: up and down); the recogniser reports which was made.
- **CRANK** counts the cumulative change of heading of the pointer's motion,
  sampled every `crank_min_step` pixels, so the size and centre of the
  circle do not matter. Turning back unwinds. Either direction completes.
  Releasing early cancels.
- **BEAD** is a TAP that counts at most `bead_max_rate` times per second;
  faster taps are ignored.
- **HOLD** completes at its time while the button is still down.
- **GATE** is not a gesture of the recogniser; the lever has its own class.
- **DRAG** (the radio dial, the mixtape, the tissue: "DRAG" without "_TO" in
  GDD 4.6 and 7.4) is not in the list of GDD 4.4. It is added in M3 with the
  radio as a pinned drag that reports its travel.
- **Order within a tick.** GDD 13.3 puts the gesture recogniser before the
  hand. So a press applied by the hand in tick N starts a gesture that the
  recogniser first advances in tick N+1; a HOLD of t seconds completes
  exactly t after the press was applied.

## D-022 (M1, 2026-11-17) Controls are rituals; cabin dressing is data

- **Decision.** The controls of GDD 4.6 are rows in `rituals.json` with no
  owning item (anchor, gesture, flick directions, crank turns). Their effects
  (`on_complete`) arrive in M3. The static shapes that dress the cabin (dash,
  console, seat, roof, pillars, doors) are `"props"` in `anchors.json`, each
  naming a placeholder; an anchor may name its own placeholder, or `null` to
  draw nothing (his own face).
- **Why.** GDD 1.3 (content and numbers in data), GDD 1.1 (an artist changes
  a registry file, not code).

## D-023 (M2, 2026-11-17) Details of driving the GDD leaves open

- **Chain.** "Each close call within 4 s of the last adds 25% to the chain,
  up to x3" is read as additive: x1, x1.25, x1.5 ... x3, which takes eight
  links, matching the eight squeal sounds of GDD 16.5.
- **Pushed clear.** After a hit the car is moved along the shallower overlap
  until there is `hit_pushback` of air: sideways for a sideswipe, backward
  along the road when he runs into a vehicle's back. Running into a back also
  caps his speed at that vehicle's speed (otherwise he would hit it again the
  moment the immunity ends). An oncoming head-on stops the car.
- **Close call = a pass.** It counts only if the vehicle is behind him when
  the two stop overlapping along the road. Dropping back from beside a truck
  is not a close call. Closing speed is read at that moment.
- **Traffic never rams.** GDD 5.5 says vehicles hold a lane at a set speed.
  A vehicle that catches another in its lane, or the player from behind,
  follows at that speed within `traffic_follow_gap` instead of driving
  through. Ramming is reserved for the Tailgater and the Storm (GDD 9.3,
  10.3), in line with GDD 12.4 rule 5.
- **Undivided roads.** Left of the oncoming lane stands a rail
  `undivided_left_rail_margin` beyond its edge, so the oncoming lane has no
  escape shoulder.
- **Edges.** The car is "on the rumble strip" when any part of it overlaps
  the strip, and "on the shoulder" when its right edge is beyond the strip.
  The shoulder cap is reached at `engine_brake`.
- **Honks.** A taxi passed as a close call adds its `honk_nerves` (GDD 5.5).
- **Horn yields for pickups and tuk-tuks.** GDD 4.6 names "cars and taxis"
  as yielding and "trucks and buses" as ignoring the base horn. Pickups and
  tuk-tuks are set not to yield; the Loud horn moves everything.
- **Cash** is a float (a close call in second gear pays 1, chained 1.25).

## D-024 (M3, 2026-11-17) How items and rituals are data

- **Rituals** carry `on_complete` (and `on_step` for a DRAG) as a list of ops,
  `"op"` or `"op:arg:arg"`: `nerves:<n>`, `cash:<n>`,
  `add_effect:<id>[:<seconds>]`, `remove_effect:<id>`, `consume_supply`,
  `give` (apply the owning item's `gives`), `toggle:<switch>`, `sfx:<id>`,
  `line:<id>`, and the controls' own ops `horn`, `wipe`, `photo`, `indicate`,
  `window`, `ash`, `radio_step`. `requires` holds conditions: an effect id,
  `supply>0`, `hot`, `flag:<switch>`, each optionally negated with `!`.
  The validator knows the op and condition vocabulary and checks every id.
- A ritual with `"anchor": "@slot"` is performed wherever its item sits (the
  tea glass may stand in either cup holder). Each anchor offers the first
  ritual whose conditions hold, items before controls: the ashtray offers
  "light" when nothing is lit and "ash" when something is.
- **Effects** are registered in `items.json` (`"effects"`). An effect may
  `imply` others: `lit` implies `awake` and `tremor_mute`; `news` implies
  `awake`. That is how "while lit" and "while tuned" sources of GDD 6.1 work.
- **The starting cabin** of GDD 7.3 is `"starting_cabin"` in `items.json`.
- The numbers of the controls of GDD 4.6 live in the `cabin` group of
  `tuning.json`; the numbers of an item live in its record (`gives`, `takes`,
  `lapse`, `params`).
- **Why.** GDD 13.3: items add, remove or query statuses and emit resource
  changes, and never change other systems directly. GDD 14 gives the item
  and ritual shapes; this fills in the vocabulary they imply.

## D-025 (M3, 2026-11-17) Details of Nerves and the base cabin the GDD leaves open

- **Blink and Nod rhythm.** The clock starts when he becomes Heavy: the
  first blink comes one `blink_period` later and lasts `blink_length`; the
  yawn comes `blink_tell` before each. At `nod_depth` or more below the floor
  the Nod's rhythm replaces the Blink's. A spell above the floor, or Awake,
  resets the rhythm. Lids open again at the rate they close.
- **Nod depth with a low floor.** "15 or more below the floor" with the
  Act 2 floor of 15 means Nerves 0. That is as written.
- **Snap.** At 100 Nerves reset to `snap_reset` at once and for
  `snap_duration` the pointer snaps to nothing and presses do nothing; the
  wheel can still be gripped and steered (GDD 6.1). A gesture in progress is
  cancelled.
- **Tremor** is added to the gripped wheel's angle (the wheel itself
  shakes); when he takes the wheel it does not jump, the shake starts from
  the angle it has.
- **Traffic near him** is counted by distance between centres.
- **Radio dial.** DRAG on the radio steps through `radio_stations` in order,
  one station per `radio_step_px` of sideways drag; from static, right finds
  the station after the last one heard and left the one before. A station
  becomes static `radio_drift_time` after it was tuned.
- **Horn.** Yielding vehicles whose rear is within `horn_range` ahead in his
  lane move to the right lane if it is free within `traffic_follow_gap`,
  else the left, taking `horn_yield_time`. The calm (`horn_nerves`) comes at
  most once per `horn_cooldown`; the yield works every time.
- **Wipers.** Rain blur is `time since the last sweep / wiper_clear_time`,
  capped at 1: clear just after a sweep, fully blurred at 6 s (GDD 4.6 and
  9.1 read together).
- **Cigarette ash.** It must be flicked once before `ash_by_s` (15 s) into
  the burn, or it falls then (+5 Nerves). The craving timer starts when a
  cigarette burns out, and only after the first one of the Telling.
- **Tea.** It is hot for `hot_for_s` after it is poured; the starting glass
  is poured at 22:00. It spills from a crash upward (`spills_on_hit`).
- **Visor.** The visor comes down every time; the photo's calm is once per leg.
