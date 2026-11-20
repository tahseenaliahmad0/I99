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

## D-018 (M1, 2026-11-17; rewritten after the M1 review) How the gear gate reads GDD 4.5

- **Decision.**
  - The lever is a point that moves only inside the channels of GDD 4.5: the
    neutral channel along y = 0 and one vertical channel per column, each
    `gate_channel_half_width` to either side of its centre line. Each tick
    the pointer motion is applied sideways and lengthways separately (the
    stronger part first) and stopped at the channel walls. So a stroke slides
    along a wall and turns the corner it leans into; nothing re-centres the
    lever.
  - "Pushes more than 1 unit into a wall": a tick counts as a push when the
    walls take more than three quarters of the motion asked for; what they
    took is added up as a vector, and a lever that then slides is forgiven by
    as much as it travels. More than `gate_wall_push` grinds. Pushing the
    lever home against the end of a gear's own slot is not pushing into a
    wall, however hard.
  - "Within 0.2 units of a gear position" is measured along the slot: a lever
    anywhere across the 0.5-unit channel, within `gate_engage_radius` of the
    slot's end, is in that gear. The engaged gear becomes neutral as soon as
    the held lever leaves that zone; a gear engages only on release.
  - A release at 0.3 to 0.8 units along a vertical channel grinds and springs
    back to neutral; nearer the neutral channel it springs back silently;
    from 0.8 it engages.
  - With the assist setting, FLICK up and FLICK down on the lever shift one
    gear at a time and never grind (`GearGate.shift_sequential`).
  - A click on the lever that was released before the hand arrived does not
    take the lever (it would hold it for one tick with no button down).
- **Why.** GDD 4.9 asks for the generous reading of the fiddly dials, and
  GDD 4.5 words the gate as channels with a width. The first build put the
  lever on rails (centre lines) and moved it along one axis per tick. The
  review's probes showed what that did to real strokes: a drag from 2nd
  steeper than 45 degrees went to 1st, a slow slightly crooked pull never
  arrived, and a push at a wall grinded only when held within 1.4 degrees of
  the axis. With channels, any stroke from 2nd between about 27 and 63
  degrees ends in 3rd, slow crooked pulls arrive within a few pixels of the
  ideal travel, and a push at a wall grinds after one unit as 4.5 says.
  Fifth gear's "nothing but temptation" is now literal: with the fifth slot
  open, a flat sloppy stroke from 2nd runs on into 5th.

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

## D-026 (M4, 2026-11-17) How a leg is generated

- **Context.** GDD 9.2 names the beats and five rules, 5.5 says vehicles hold
  a lane and a speed and appear 300 m ahead, and 9.1 gives a density. It does
  not say how these fit together.
- **The par frame.** A leg is planned for a player who holds third gear. A
  vehicle of the plan is stored as "appears `ahead` metres in front when the
  player passes `trigger_s`"; at par he is level with it at `meet_s`. In a
  beat template `s_offset` is where the vehicle is, ahead of the beat's
  start, when the player enters the beat (the GDD 14 example reads that way).
  A vehicle that would have to appear before the leg starts is on the road
  from the start. Driven slower or faster, the same vehicles are met later
  or sooner; rule 3 is promised for third gear only, as the GDD words it.
- **Traffic that holds its speed.** Two vehicles in one lane are never
  planned to come within `gen_spawn_clearance` (more than the follow gap) of
  each other before the player has passed both, so nothing in a plan has to
  brake and the plan is exact when driven (T-GEN-01 drives a sample of legs
  with the real traffic and compares). Where two would close up, the faster
  is planned at the slower one's speed: it is "held up". So a pickup may be
  planned at 60 km/h behind a tanker; the speed range of GDD 5.5 is what a
  vehicle does on a free road.
- **Rule 3, never a wall.** Each vehicle closes its lane for the stretch of
  the player's progress in which it is level with him, plus
  `gen_block_margin` at each end; a merging vehicle closes the lane it
  leaves until it has left and the lane it enters from the moment it
  signals. The generator keeps a line through the leg that is never in a
  closed lane, changing lane only where both lanes are free for
  `gen_lane_change` metres; the plan carries it as `path` (inside a chicane
  the line is the corridor). A beat whose content would close the last way
  through is drawn again.
- **CALM** means no block of any vehicle or hazard overlaps the beat.
  Oncoming traffic on the Two-lane keeps its own side and is not "in reach".
  No vehicle is still beside him when the beats end at 2,200 m: the last
  300 m stay clear for the Exit and the Fork.
- **Beats that do not fit** where they are drawn (the lanes they need are
  still taken) are tried a little later in the beat (`gen_beat_shifts`), then
  drawn again as another template or type. A CALM beat that is owed
  (`gen_calm_deadlines`) is waited for with quiet beats only. A whole leg is
  redrawn only if nothing fits; after `gen_max_attempts` the generator would
  fall back to a sparse leg, which T-GEN-01 shows never happens.
- **Density (GDD 9.1, 12.3)** is the number of vehicles a leg puts on the
  road ahead of him per km of beats: 6, 10 or 16, plus 2 per act after the
  first, times 2.2 km. Beats come first; single vehicles top the count up:
  queued behind a slow one, slow on their own, or faster than third gear
  (`gen_filler_shares`). Those faster ones appear 300 m ahead and pull away;
  in fourth gear he catches them. 44 vehicles that he must all pass in third
  gear do not fit on three lanes with one always open, so on a heavy leg a
  good share are of that kind.
- **Two-lane and Motorcade** take their traffic from their encounter
  (GDD 9.3): trucks at 60 and oncoming vehicles every 6 to 10 s at par; the
  motorcade and nothing else. The density rule does not apply to them
  (T-GEN-03 says so and T-LEG-08 and T-LEG-09 hold them to 9.3). On the
  Two-lane each truck is met in the middle of a gap in the oncoming traffic
  long enough to pass it in third gear, which is more than the fourth-gear
  pass the GDD asks for.
- **Lengths.** Beat lengths are whole metres and beats tile 0 to 2,200 m
  exactly. The table of GDD 9.2 is `beat_lengths` in tuning; the validator
  holds every template to it.
- **Forks (GDD 9.5, 12.3).** The two branches of a fork are different leg
  types drawn evenly from the act's pool; each carries a modifier with the
  act's chance, drawn evenly from those the leg allows.
- **Why.** GDD 1.5: the simplest model that makes rules 3 and 4 checkable
  and keeps "the same seed gives the same leg" literal.

## D-027 (M4, 2026-11-17) Hazards, zones and weather the GDD leaves open

- **Cones, melons, sheep and potholes** light no lamp (GDD 5.6). Each cone,
  melon or sheep adds 3 Nerves once, cones and melons also 10 Suspicion
  during a Patrol; a pothole adds 3 Nerves and takes 30% of his speed, at
  most once per `pothole_cooldown`. They are not passed for close-call
  money: a chicane alone would pay some fifty close calls against the 16
  cash a leg of GDD 12.1. A hulk on the shoulder is a parked vehicle and
  does count.
- **Chicanes (Roadworks).** Three zones of 150 m, each a corridor with 2.16 m
  of clear road between the cones (inner edges), straight for 50 m, shifting
  one lane over 50 m, straight for 50 m. The car does not turn in lane
  space, so where the corridor shifts the cones stand back by what the car's
  length sweeps sideways: the room each side is 0.18 m everywhere.
- **Sheep.** A row across the road with one gap of `gap_m`, walking toward
  the right at `speed_ms` from the moment he is `approach_s` short of it at
  par; the gap is at a lane's centre when he arrives at par. Sheep that have
  not come through the median yet are not on the road.
- **Melon truck.** It sheds one melon every `melon_every_s` for `shed_s`
  once he is `shed_gap_m` behind it. Melons roll toward the right shoulder
  (the crown), so the lanes to the truck's left stay clear.
- **Wedding.** Four decorated cars, two abreast in two lanes, at 60 km/h.
- **Crosswind.** A gust every `gust_every_s` of driving at par.
- **Potholes.** The HAZARD weight is doubled and HAZARD beats are potholes.
- **Curves** come on and go off over `curve_ramp` metres; the sign stands
  `curve_sign_lead` seconds before the bend at par.
- **Gusts** are announced when he is `gust_tell` seconds short of them at par
  and blow exactly `gust_tell` seconds after the tell, whatever his speed.
- **Rain.** The view blurs only while it rains; `rain_response_mult` scales
  the car's sideways response time (30% slower).
- **Leg income (GDD 12.1).** At the end of a leg: `clean_leg_bonus` if no
  lamp was lit in it, and one cash per whole 2 s under par.

## D-028 (M2 review, 2026-11-17) The car at rest, on the shoulder and in a gust

- **Context.** The M2 review found that a car braked to rest slid down the
  crown into the guardrail and was a Wreck at 0 km/h (GDD 5.4 says the crown
  pushes "always"; 5.3 gives no steering at rest), that the shoulder's speed
  cap was skipped in neutral, and that a gust lasted 121 ticks.
- **Drift fades with speed.** Every sideways drift (crown, curve, gust,
  pulling steering, later sway) is scaled by `speed / drift_fade_speed`, up
  to 1, with `drift_fade_speed` = 20 km/h. At rest the car does not move
  sideways; from 20 km/h up nothing changes, so 3.4 s to the lane line and
  5.0 m/s at full lock stay exact; below it full lock always beats the
  crown. The share is read from the speed the tick ends with. `CarSim.drift`
  and the snapshot's `drift` are the drift as it reached the car. A gust's
  ticks run out whether or not the car moves.
- **The shoulder's cap** belongs to the surface: above
  `shoulder_speed_cap` the car slows at `engine_brake` at least, whatever
  the lever or the foot does, neutral included, and the tick that reaches
  the cap ends on it. The rumble strip slows nothing and frays nothing; it
  still ends a Nod.
- **A gust** lasts a whole number of ticks: round(`gust_duration` x 120).
- **Pinned by the T-CAR tests since the review** (behaviour that existed):
  within a tick the speed changes first and the car then moves at the new
  speed; a rail or barrier also stops the car's sideways speed; the brake
  sheds `brake_decel` in every lever state, never more; the sideways speed
  follows its command as an exact first-order response; the rail left of
  the oncoming lane scrapes like the guardrail.
- **Why.** GDD 4.8, 4.6, 10.2 and 10.3 all need a car that can stand still.

## D-029 (M2 review, 2026-11-17) One contact is one hit; "clear" is clear of everything

- **Context.** The M2 review found that one oncoming truck or tanker hit the
  stopped car twice (the immunity ran out while it was still driving through
  him): a single head-on was a Wreck. A push "clear" could throw the car
  through the median barrier or into another vehicle, and during the
  immunity the car could drive through a truck.
- **One contact, one hit.** A vehicle that has hit the car cannot hit it
  again until the two no longer overlap along the road and the immunity has
  run out. A second vehicle can hit him once the immunity is over.
- **The car never stays inside a vehicle.** An overlap that cannot be a hit
  (he is immune, or that vehicle has already hit him in this contact) is
  undone every tick: the car is moved out on the side it came from, with no
  lamp, no Nerves and no speed loss, so pressing on a vehicle is a slide
  along it.
- **Clear is clear of everything.** A push sideways must end outside every
  other vehicle and inside the rails; where it cannot, the car is put along
  the road instead: `hit_pushback` behind the vehicle's rear bumper, or in
  front of it when the vehicle hit him from behind. Behind a vehicle going
  his way he is no faster than it is.
- **The taxi's honk** (GDD 5.5) is judged when the pass is judged: the taxi
  is behind him, the smallest sideways gap was under `close_call_gap`, there
  was no contact; the closing speed does not matter (in third gear he closes
  on no taxi fast enough for a close call). It adds the honk's Nerves once
  per pass and is announced as an `sfx_requested` with the vehicle's id.
- **Traffic.** Oncoming vehicles follow each other as traffic going his way
  does; they do not react to him. Signal and lane-change times are counted
  in whole ticks.
- **Why.** GDD 5.6 ("pushed 0.5 m clear and cannot be hit again for 0.8 s")
  and GDD 6 (five lamps are a Wreck; a head-on is three).

## D-030 (M1 review, 2026-11-17) Gestures: what the review of the pipeline changed

- **FLICK.** The swipe must go more in an allowed direction than across it;
  with several directions allowed it reports the way it mostly went.
- **CRANK.** A change of heading of more than `crank_max_turn` (120 degrees)
  between two samples is a change of direction, not turning: it counts for
  nothing either way. Before, a reversal was booked as half a turn, forward
  about as often as back.
- **BEAD.** A tap counts unless `bead_max_rate` beads were counted within
  the last second. Tapping faster than the limit gives the limit, not half.
- **DRAG_TO.** A DRAG_TO ritual names the anchor the object goes to (`to`).
  While it is carried the hand cannot take the wheel (GDD 4.2), the
  destination can be pointed at even if nothing else is done there, and the
  ritual completes when the button is released with the hand resting on it.
- **After a gesture** the hand stays on the control until the button comes
  up, so the rest of a long flick does not drag the pointer off it: two
  flicks in a row both work the wipers, and three assisted shifts are three.

## D-031 (M4, 2026-11-17) Suspicion, the pull-over and the Patrol: what the GDD leaves open

- **Gears.** "Any gear but 2 or 3" means first, fourth and fifth. The lever
  out of gear (neutral, or held between slots during a shift) is no gear
  and counts as driving clean.
- **Driving clean** is any tick with no offence that counts by the second
  (illegal gear, dead headlight at night). One-off offences do not stop the
  decay.
- **Indicating** means the indicator shows the way he crosses at the moment
  the car's middle crosses the lane line. The wrong way counts as none.
- **Contraband and the phone** count when a ritual of an item marked
  `contraband`, or tagged `phone`, completes. A Snap counts on the tick
  after it happens (Nerves step after Suspicion).
- **The pull-over.** At the top of Suspicion the car stands on the shoulder
  and the police car behind it; a gesture in progress is cancelled. Nothing
  moves on while the officer waits: the leg's clock and the encounter stop,
  the car does not move, nothing can hit him. Two rituals are offered,
  before any item at the same anchor: his licence, clipped at `dash_1`, and
  the banknotes at the new anchor `cash`; each is a DRAG_TO to
  `driver_window`.
- **The fine** is `fine_share` of his cash, rounded, `fine_min` at least and
  never more than he has; it costs `fine_minutes`. The officer takes every
  item marked contraband that is not in a glovebox cell.
- **The bribe** is `bribe_base` plus `bribe_per_act` for each act (50, 60,
  70) and costs `bribe_minutes`. Banknotes he does not have are refused and
  he stays pulled over.
- **Game minutes** are added to `DriveSim.clock_minutes_owed` until the
  Clock exists (M5).
- **Afterwards** the Patrol is over: Suspicion is gone, the lights are out,
  and he drives off from the shoulder in whatever gear the lever is in.
- **The police car** appears `patrol_spawn_behind` metres behind him when
  its lights come on, closes up to `gap_m` behind his bumper during the
  three seconds of the tell, and from then on drives in his tracks: at his
  speed, where he was when he was at that point of the road. So it gets
  through whatever he got through and never touches him. When the Patrol is
  over it falls back like any other vehicle.
- **Why.** GDD 6.5 gives the amounts; GDD 1.5 for the rest.

## D-032 (M4, 2026-11-17) The Tailgater: what the GDD leaves open

- **Arrival.** He appears `spawn_behind_m` behind `tell_s` before he is on
  the bumper (headlights in the mirror), and is on it `at_s` into the leg,
  `gap_m` behind the rear bumper, driving in the player's tracks.
- **Nerves.** +`nerves_per_s` while he is behind in the player's lane, on
  top of what any vehicle that near adds (GDD 6.1).
- **Ramming.** Each time the brake is pressed while he is on the bumper he
  rams: an ordinary scrape from behind through Collision (one lamp, +10
  Nerves, 20% off the speed). Slowing down with the gears is not braking.
  He cannot ram again until the hit's immunity and a second more have
  passed.
- **Leaving.** When the car's middle is in another lane he keeps his own,
  level with where he was, and adds nothing. Back within `lane_hold_s`: he
  is on the bumper again. Held for `lane_hold_s`: he passes at
  `pass_speed_kmh` over the player's speed, cuts in `brake_gap_m` ahead,
  sheds `brake_drop_kmh` in `brake_s` once (being cut off is +5 Nerves,
  GDD 6.1) and drives away. A driver who simply holds third gear is not hit
  by it. `gear_hold_s` unbroken seconds in fourth or fifth, or `duration_s`
  on the bumper, and he falls back instead: no pass, no brake.

## D-033 (M4, 2026-11-17) The Motorcade and its side road

- **The convoy.** Five `motorcade_car`s in a fixed formation: rows of two in
  the outer lanes `row_gap_m` apart, the last car alone in the middle lane.
  It starts `start_ahead_m` (180) in front of him, so the sign on the last
  car can be read for about nine seconds in third gear before the spotlight
  reaches him. It holds `speed_kmh` whatever happens.
- **The wall.** "The motorcade never touches him" is a rule of the road, not
  of his steering: across the whole width of the road, shoulder and slip
  lane included, the car cannot come nearer than `hold_gap_m` to the last
  car's rear bumper, and its speed is held to the motorcade's there.
- **The spotlight** is on while the gap from his front bumper to the last
  car's rear bumper is under `keep_back_m`: `glare` in the snapshot and
  +`nerves_per_s`, on top of what any vehicle within traffic_radius adds
  (GDD 6.1), as with the Tailgater. Outside it the motorcade does nothing.
- **129 s** is the leg's 2,500 m at 70 km/h (128.6 s): a driver who stays
  behind at the motorcade's speed. Following as closely as the wall allows
  gains at most the 170 m he starts behind it: 120 s, still over par.
- **The side road** is signed `slip_sign_lead` seconds ahead, like an Exit
  (GDD 9.5). A slip lane opens on the right at `detour_at_m` (the road is
  one lane wider beside it) and ends `detour_slip_m` further on. A car whose
  middle is in the slip lane there is on the side road: one lane each way,
  no median, the Two-lane leg's trucks and oncoming traffic from the plan's
  detour, no bends, gusts or hazards of the main road. `detour_length_m`
  later it is back in the right lane of the main road. Any other car stays
  on the main road and the slip lane is gone.
- **Rejoins ahead.** The motorcade goes on along the main road while he is
  away. If the side road took him so long that it would be past the place
  where he rejoins, it is put `rejoin_behind_m` behind him instead: the side
  road rejoins ahead of the motorcade, as the GDD says, however he drove it.
- **Behind him** it is traffic that does not push: it comes no nearer than
  `hold_gap_m` to his rear bumper and takes his speed there (the one case in
  which it is slower than 70 km/h). No spotlight from in front of it. Its
  cars are taken off the road and put back at `despawn_behind` like any
  others.
- **The encounter** counts as on (no empty-road calm, GDD 6.1) while the
  motorcade is ahead of him on the main road; not on the side road and not
  once he is ahead of it.
- **Vehicles ahead are never removed.** T-CC-01 says so; a despawn rule for
  vehicles far ahead was tried here and taken out again.
- **Why.** GDD 9.3 gives the numbers; GDD 1.5 for the rest.

## D-034 (M4, 2026-11-17) The wedding's happy honk; one list of bus signals

- **Happy honk.** A car of the wedding motorcade carries the modifier's
  `honk_nerves` (-5). Passed closely it honks like a taxi does, and a honk
  that calms takes the place of the close call's +2 Nerves instead of
  adding to it (GDD 9.4: "-5 Nerves instead of +2"). The close call still
  counts and pays.
- **Bus signals.** `EventNames.ALL` (core) is the list of GDD 13.6. The
  `Events` autoload takes its names from it, and `DriveSim` refuses to
  announce anything else (an engine error, which fails any test that causes
  it). The item simulation's two private notices, the falling ash and the
  craving, are not on that list: they are in the snapshot's item entries
  now (`ash_fell`, `craving`).
- **Sandbox traffic** draws only from vehicle types that are ordinary
  traffic (not the police, a motorcade car, a wedding car, a hulk).
- **Why.** GDD 9.4, 13.6; GDD 1.5 rule 4 (no signal the document does not
  name).

## D-035 (M4, 2026-11-17) What a leg looks like; the world shader's globals

- **Globals.** The bend of the road and the haze are global shader
  parameters (`shader_globals` in project.godot: `world_bend`,
  `world_bend_origin_z`, `world_fog_color`, `world_fog_near`,
  `world_fog_far`). Any material that uses `world_bend.gdshader` follows
  them, an artist's scene included. The bend is set exactly (the old guard
  dropped small changes, so a straight road stayed bent).
- **Seeing.** What he cannot see fades into the sky's colour between
  `fog_near_share` of the snapshot's `visibility` and all of it: the dark
  beyond the headlights on a Night leg, the haze of a dust haze. Lamps
  (head, tail, indicator, beacon) are drawn through it. Until the Clock is
  built the sky is the day's colour on other legs.
- **Slip lane.** The snapshot gives `slip` (from where to where along the
  leg) and `slip_open` (the car's road is one lane wider now). The road is
  drawn as before and after, the slip lane with its own line, strip,
  shoulder and rail on top, and the main rail's pieces are left out beside
  it. The guardrail is drawn in `rail_period` pieces for that reason.
  Taking the side road rebuilds the road in one frame: the main road is
  gone at once. Drawing the two roads parting is left for M10.
- **Signs** are a post inside the rail with a Label3D text in square
  brackets from the line table; a text does not bend with the world shader,
  so it is moved by hand. The last car of the motorcade carries its sign.
- **Indicators** blink on each vehicle's own clock, lit from the first frame
  of a signal. A police car's beacon blinks at `signal_blink_hz`, under the
  three flashes a second GDD 16.4 allows.
- **Command line.** `--leg=<id>[,act[,modifier]]` starts that leg in third
  gear, and the next seed of it when it ends. `--bot=<anything>` holds the
  car on the plan's line (lane middles; cones in a chicane get hit) until
  the DriverBot of GDD 13.8 exists (M11).
- **Review findings applied here** (M2 views, M1 rules): indicators' clock;
  vehicle views checked against the vehicle's type; lane dashes centred on
  the lane boundaries; the purity lint asks the engine whether a core
  class is a Node and knows frame counters, machine facts and generators
  made outside rng.gd (`Rng.seeded` is the one way to make one);
  countdowns (grind lock, hit immunity, Snap, hot glass) end on their last
  tick instead of one later; the test runner fails a test that awaits;
  whole-number settings load back; the hand's anchor accessors refuse an
  index that is not an anchor; the validator knows the M1 constants,
  refuses zero where the code divides, and requires the controls of GDD 4.6.

## D-036 (M5, 2026-11-17) The road of a Telling

- **Stretches.** A Telling is driven as stretches of road, each with its own
  `s` from 0: the approach to a fork, a leg, a boss, the street of the
  Arrival. `RunState` knows which comes next; `DriveSim` drives it. The car
  rolls from one into the next with its speed and its place across its lane.
- **Start.** A Telling begins `leg_tail - exit_slip_length` (170 m) short of
  its first fork, in the middle lane, rolling in first gear with nobody at
  the wheel (GDD 10.1). Left alone, the car drifts onto the right-hand
  branch: not choosing is a choice.
- **Fork.** The gore is the end of the stretch (2,500 m of a leg). A car
  whose middle is left of the middle of the road takes the left branch,
  any other the right. Branches come from `RunGenerator.fork`, which now
  also draws the stop at each branch's end by `stop_weights`. The sign
  stands `fork_sign_lead` seconds short of the gore at par.
- **Exit.** Every leg of a Telling ends in one. The slip lane opens at
  `leg_length - leg_tail` (2,200 m) and the stall is `exit_slip_length`
  (130 m) on. A car in the slip lane (or beyond it) at the stall, at
  `exit_max_speed` or less after that tick's driving, is at the stop. Every
  other car has missed it, whatever lane it was in: +`missed_exit_nerves`.
  Not stopping is therefore never free (GDD 9.5 says "too fast or in the
  wrong lane", which is every way of not stopping).
- **At a stop** the night waits: the car, traffic, the leg's clock, the
  Clock, effect timers, items and Nerves do not step; the hand, gestures
  and rituals do. The stop's minutes are charged on entry. Gripping the
  wheel for `stop_leave_grip` leaves, but only a grip taken at the stop:
  the hand must have been off the wheel since he arrived. He pulls away
  from rest in first gear, in the right lane beside the stall, and the
  leg's last 170 m lead to the next fork or the boss.
- **Bosses** are records in `legs.json` (`bosses`: id, act, length, par).
  Until M7 builds them a boss is an empty road of its length. Its end is a
  boss stop in every act, the third included (T-RUN-01's text), and after
  the third comes the Arrival: until M7, `arrival_length` of street whose
  end is the bay, where the Clock is read.
- **Stops as data.** `stops.json` follows GDD 14; `clock_min` and `weight`
  must equal `stop_minutes` and `stop_weights` of GDD 15 (the validator
  checks), so the two tables cannot drift apart.
- **A clean slate.** `DriveSim._build()` makes every part of the simulation
  anew. A Telling begins with it, so nothing of an earlier drive can leak in.
- **Traffic's follow rule** looks only at what stood just ahead along the
  road when the tick began (vehicles are kept in order by a pass over a
  nearly sorted list). The result is the same as looking at every vehicle,
  to the bit, at a quarter of the cost.
- **Why.** GDD 9.5, 9.6, 11.1; GDD 1.5 for what they leave open.

## D-037 (M5, 2026-11-17) Stops and the shop

- **`StopSim`** (core) is the stop: the vendor's tray and what the hand does
  with it. It is not in the file list of GDD 13.2; it is the part of the
  simulation that `stop_view.gd` shows.
- **The tray** lies at the passenger window: five anchors, `offer_1` to
  `offer_5` (anchors.json; travel times by T-HAND-01). One offer at each;
  what does not fit waits and moves up as room is made.
- **Rituals of the tray** exist only while an offer lies at an anchor and
  are not in rituals.json: a TAP buys, and a DRAG_TO carries what was
  bought to the anchor of any slot the item can go in (a DRAG_TO may now
  have several destinations).
- **Buying.** A TAP buys when his cash covers the price; otherwise nothing
  happens. An item that goes in a slot the hand can reach is then his to
  place; an Adaptation goes into the first free bay at once (none free: it
  cannot be bought); what the hand cannot carry anywhere (the taxi sign on
  the roof, a Deal that changes the car) is his at once. What sat in a slot
  he drops an item into stays with the vendor. What he has paid for and not
  placed when he leaves is paid back.
- **Catalogue.** items.json holds the 32 items with kind, slots, rarity,
  price and supply; what they do is M6. Ids are those of the tests
  (`beads`, `seeds`, `charm`, `sunglasses`, `window_switch`, `good_stuff`).
  Rarity follows the price bands of GDD 12.2. The arak flask has kind
  `deal`: only the shady guy sells it. The Thermos has no restock price and
  is not restocked at a fuel station.
- **Stock.** For each item a rarity is drawn by the act's shares, then any
  item of it from the stop's pools that he does not own and that is not on
  the tray already. A rarity the pools lack gives the nearest one they
  have (a commoner one first): a fuel station has nothing rare, a fitter
  nothing common. Restocks are offered for what he has used up of things
  with a restock price.
- **Fitter.** Two Adaptations, and a repair for each lit fault at
  `repair_price`; each repair is `repair_minutes` on the Clock.
- **Tea stall.** On entry his Nerves are set to the stop's `nerves_to` and
  every tea glass is filled, hot. (The boss modifier on the next fork sign
  comes with the bosses, M7.)
- **Roadside find, boss stop.** Free picks: he may take as many as the
  stock's `free` says (one); when none is left the rest are taken away.
- **Shady guy.** He is at the stop that ends a leg which lit no lamp so far
  (the stop is at 2,330 m of the leg it belongs to), with two Deals. The
  first thing bought from him adds `stop_minutes.shady`, once.
- **Boss stop.** No minutes on entry; three items of which one is free; when
  that pick is off the tray, the five stops that can end a leg are held out
  as services and a TAP on one makes the boss stop that stop. Nothing at a
  boss stop costs Clock minutes, a repair there included.
- **Hitcher.** Two minutes and nothing to buy until the passengers of M8.
- **Why.** GDD 9.6, 12.2, 14; GDD 1.5 for the rest.

## D-038 (M5, 2026-11-17) Wreck and restart, the save, the input log

- **Wreck.** In a Telling, the fifth lamp starts a cut of `wreck_to_wheel`
  seconds in which nothing moves; then the same Table is told again from
  Baghdad with another seed (derived from the old one and the count of
  retellings), the starting cabin, 22:00. The pointer follows the player
  through the cut, and a pointer that is on the rim puts the hand there:
  with the button down he has the wheel on the very tick the Telling
  restarts. Outside a Telling a Wreck simply stays one.
- **A stop is a save point, and goes on from the save.** On entering a stop
  (the leg's, or a boss stop) `DriveSim` takes what a save holds
  (`capture()`), keeps it as `checkpoint`, and at once rebuilds itself from
  it (`restore()`). The uninterrupted Telling and the one loaded from the
  file are therefore the same code path, and T-SAVE-01 holds them to the
  same state hash. Consequences, all intended: at a stop every timed
  effect ends, the haze is gone, the hand is off the wheel at its rest, the
  leg's encounter is over; items keep their supply and a drink its heat;
  the radio keeps its station and the switches their state.
- **The save file** follows GDD 13.7 and adds what standing at a stop needs:
  `stage` (stop or boss_stop), `side` (the branch he is on), `retellings`,
  `leg_lamps`, `shady`, `radio`, `switches`, and `exact`. Its readable
  numbers (`clock_min`, `cash`, `nerves`) are rounded to a thousandth and
  are for people; `exact` holds the same numbers and the leg's clock as the
  sixteen hexadecimal digits of their bits, because this engine's JSON
  reader can lose the last bit of a float. A save without `exact` (written
  by hand) loads from the readable numbers. Whole numbers are written as
  whole numbers, so a file read and written again is the same file. Seeds
  too large for a JSON number are written as their digits.
- **Who writes.** `Save` (core) only turns the profile and the Telling into
  text and back; the Game autoload writes `user://save.json` when a stop is
  entered. Nothing else changes `checkpoint`, so nothing is written during
  a leg.
- **Input log.** `InputLog` (core, not in the file list of GDD 13.2) holds
  each tick's `DriveInput`. `DriveSim.state_hash()` is a SHA-256 over the
  snapshot, the save's view of the Telling, effect timers, every vehicle
  and the main numbers of each part. T-REPLAY-01 drives 75 s by real input
  (horn, two gear changes on the gate, the wheel held and steered, brake)
  and replays the log to the same hash.
- **Leaving a stop** needs a grip taken there: the hand off the wheel and
  the button up at some moment since he arrived.
- **Why.** GDD 11.1, 11.4, 13.3, 13.7; GDD 1.5.

## D-039 (M5, 2026-11-17) What a Telling looks like; the game's part of saving

- **Command line.** `--table=<id>` (with `--seed=`) starts a Telling in the
  drive scene. `--continue` (not in GDD 13.9; it stands in for the title
  screen's button until M9) goes on from the save file. `--bot=` in a
  Telling keeps third gear, pulls in at every Exit, waits two seconds at a
  stop and leaves, and takes the left and the right branch in turn: enough
  to watch a Telling pass, and what the smoke test runs for 9,000 frames.
- **Saving.** The drive controller writes the save when a `stop_entered`
  event passes through it (`Game.write_save(sim.checkpoint)`), and clears
  the Telling from it on `arrived`. Until the wedding room exists (M9) an
  Arrival is followed by a new Telling with the next seed.
- **The sky** follows the Clock in a Telling: night until `sky_dawn_from`
  of the night is gone, then lighter until the deadline. Outside a Telling
  it is as before (day, or the leg's night, rain or dust).
- **Fork sign.** Over the road at `fork_sign_lead` before the gore, one
  text over each half: the branch's leg, modifier, stop and par, one to a
  line in large letters (`road_fork_text`). The gore itself is a yellow
  block in the middle of the road. The road beyond it is not drawn as two:
  the next stretch replaces the road in one frame (left for M10).
- **Exit.** Signed with the stop's name; its slip lane is drawn like the
  side road's.
- **Stop.** `StopView` (cabin frame): the vendor (a green capsule) and, when
  he is there, the shady guy (a darker one) at the passenger window; a
  tray; on it a small box for each offer with a text that always faces the
  eye: name and price, "free", "yours" once bought, "Repair ..." and
  "Restock ...". A stall stands beside the road.
- **Dashboard clock**: a Label3D on the dash showing the Clock.
- **M2 view findings closed here:** the horn's and the glovebox's markers are
  drawn on the surface of the prop they lie in (`marker_offset`); the left
  sleeve hangs where the resting eye sees it; the Cabin has the nodes
  Mirror, Visor, Seat and Glovebox of GDD 13.5.


## D-040 (M6, 2026-11-17) How items say what they do; beads, seeds, tissues, the tape

- **Gives and takes are entries of five shapes** (items.json, read by
  `ItemSim` and checked by the validator): a timed status on use
  (`effect` + `duration`); a resource on use (`resource` + `amount`,
  optionally `over` a time); a status held on while the item is in the
  cabin (`effect` alone); Nerves by the second (`resource` + `per_s`); haze
  by the second (`effect: haze_rate` + `amount`, as GDD 14 writes it). Each
  may have a `while` condition. A resource entry may name a `synergy` rule
  of the same item: when that synergy's partner is there, the synergy's
  amount is used instead (beads: -2, with music -4).
- **Statuses carry numbers and immunities** in the effects registry
  (`immune: [honk, tailgater, doubt]` on `chewing`). Nerves from such a
  source go through `DriveSim.fray(source, amount)`; a gain is dropped
  while he is immune to its source. Only gains: a wedding car's happy honk
  still calms a man who chews. Being cut off is not a honk and still
  frays him. Doubts do not exist until M9; their Nerves will come through
  `fray(&"doubt", ...)`, and T-ITEM-SEEDS checks that path now.
- **Perform times** in GDD 7.4 ("TAP 0.3 s", "DRAG ... 0.8 s") are what a
  practised player takes, not rules: they are stored as `perform_s` on the
  ritual for the bot. Rules are `hold_s`, `out_m`, `across_m`.
- **Carrying.** A DRAG_TO may now end where it began (`"to": "@slot"`) once
  the object has been `out_m` away from there (the tape: out of the deck and
  in again), or anywhere at all once it has been carried `across_m`
  sideways (a tissue across the glass; no `to`). While the hand carries
  something it cannot take the wheel, as before.
- **The tape deck is the radio.** GDD 16.2 gives `radio` and `tape` one
  position. With a tape in the slot the `tape` anchor takes the radio's
  place (`"over": "radio"` in anchors.json): the dial is not offered, the
  radio falls silent, and the deck plays the tape. The tape is the `music`
  status while it plays (so the beads answer to it) and stops being music
  when it warbles. An open window halves what the tape does to his Nerves,
  as it does the radio's. A flip at any time starts the side's 60 s again.
  At a stop the side starts again too (every timer ends there, D-038).
- **Tea.** A fuel station also offers the 2-cash refill for a full glass
  that has gone cold: hot tea is what he is paying for.
- **Timed statuses are counted in whole ticks** like every other countdown
  (the review's rule): a 25 s status is on for exactly 3,000 ticks.
- **`DriveSim.give_item`** puts an item in the cabin outside a stop (debug
  key F5 will use it; the tests do).

## D-041 (M6, 2026-11-17) Focus, the pills, Courage, the mints; a tray of ten

- **Focus** ("the road runs at 85% speed while the hand runs at full
  speed"). The tick is shorter (`road_speed` of the `focus` status) for the
  car (its speed and its sideways motion), traffic, hazards, collisions'
  timers and the leg's encounter. It is whole for the gesture, the hand, the
  wheel, the gear gate, every status and item timer, Nerves, the Clock and
  the leg's own clock. So Focus buys time to think and pays for it in Clock
  minutes and par seconds. "Then Tremor +50% for 20 s": the 20 s begin with
  the sip.
- **Painkillers are taken at his face**, as GDD 7.4 says: the ritual belongs
  to the item but is offered at `face`; the bottle on the dash is the slot
  it costs. Where a HOLD and a control's TAP are offered at one anchor, a
  press let go within `tap_max_time` is the TAP (a slap) and a press held
  for `hold_s` is the HOLD (a pill); anything between is neither.
  `blocks_view` of the ritual being performed is in the snapshot
  (`view_block`).
- **"For the leg"** means until the next stretch of road begins (the gore).
  Such statuses are held by the leg and pass through the leg's stop: the
  save holds them (`leg_state`), together with whether the photo has been
  looked at this leg, which until now a stop forgot. A second pill in one
  leg does not raise the Heavy floor again.
- **Courage** stacks add up: n stacks pay close calls x(1 + 0.5 n) and scale
  every gain of Nerves by (1 - 0.3 n), never below nothing. Each stack has
  its own 45 s; a sip at the cap renews the stack that would end first.
  Like every timer, Courage ends at a stop.
- **Sway** swings from the moment Courage begins (to the right first) at
  `sway_frequency`, `sway_per_stack` per stack, and ends with Courage.
- **Lag.** The car is steered by the angle the wheel had `lag` seconds ago
  (between ticks, in proportion): `lag_per_source` per Courage stack, never
  more than `lag_cap`. The wheel itself is not delayed.
- **Refilling the flask** is the shady guy's business (20), not the fuel
  station's: contraband is restocked only where it is sold.
- **Breath mints.** `DriveSim.courage_noticed()` is the Courage a policeman
  notices: none while he is minty. The Checkpoint (M7) will read it; a
  check with the real Checkpoint is owed to T-ITEM-BREATH-MINTS then.
- **The tray has ten places**, two rows of five (`offer_6` to `offer_10`
  above and behind the first row). A fuel station late in a Telling can hold
  out three items, five restocks and two Deals; with five places most of
  that waited unseen until something was bought.

## D-042 (M6, 2026-11-17) The phone, the Keepsakes, seven synergies

- **Calls.** The wait for the next call (25 to 40 s, from the road stream)
  is counted from the end of the last one, or from when the phone first
  rides along. "One call in four is Um Noor" is every fourth call of the
  Telling, not a one-in-four chance: he can learn it. Her call pays no cash
  (also with the taxi sign). Each of the three TAPs is a ritual; from the
  first one his eyes are down for as long as his hand stays on the phone
  and the call is open. One call is one use of the phone to whoever watches
  (+30 once, not per TAP). A call still ringing when he stops is dropped
  without penalty. The count of calls and of calls answered in a row pass
  through a stop.
- **Standing changes.** A Keepsake, Adaptation or Deal that works by being
  there says so with `{"passive": key, "amount": n}` entries; `ItemSim`
  keeps the combined value per key (multipliers multiply, amounts add) and
  the other systems read it. The keys are `ItemSim.PASSIVES`.
- **Charm.** It turns aside scrapes only (rail, barrier, a slow vehicle, the
  tailgater's ram), the first of each leg. The scrape still frays him and
  costs speed. No lamp lit means the leg can still be a clean one. Spent,
  it stays spent through the leg's stop.
- **Thermos.** Offered while there is tea in the cabin to refill; a pour
  fills the glass and makes it hot, whatever was in it. It has no restock:
  four refills are what it holds.
- **Duct tape.** It takes hold of the first fault lit in the act (of
  several lit by one hit, the first drawn) and that fault mends itself 10 s
  later, or the moment he stands at a stop. The lamp did light: the leg is
  not clean. A new act begins when the road of that act does.
- **Lucky note.** 1 cash per close call, flat: not multiplied by gear,
  chain or Courage.
- **Cracked sunglasses.** "Darker" is distance: at night he sees that share
  less far (the headlight cone times 1 - 0.15), and the snapshot carries the
  share for the picture. Glare is multiplied by 0.3 on its way to the view;
  Glare does nothing else.
- **Synergies** live on one item of the pair (`synergies`: `with`, `rule`,
  numbers) and work by rule name (`ItemSim.SYNERGY_RULES`), only while the
  partner is in the cabin (or, for the tokens, music is playing / always
  for the photo).
  - Tea + Cigarettes: every sip while one is lit adds 10 s to that burn
    (no Tremor, Awake, Haze for 10 s more). The -10 Nerves of a cigarette
    stay -10.
  - Flask + Photo: a look with Courage ends all Courage, every time. The
    -40 takes the place of the photo's -20 and is, like it, once per leg.
  - Flask + Painkillers: while Courage and a pill's 60 s overlap, Lag is
    doubled (and then capped) and close-call cash doubled. Owning both
    does nothing by itself.
  - Phone + Taxi sign: every third call answered in a row pays 20 more; a
    missed call starts the row again; Um Noor's call counts as answered.
  - Seeds + Tea: the tea does not cool while he chews.
- **Tags.** items.json lists the tags there are (`tags`). An item's tags,
  a `tag:<tag>` condition and a `refill:<tag>` op must name one of them: a
  misspelt tag is an error whether or not any item carries the right one.
- **Fixed on the way.** A save made at a stop in Act 2 or 3 would have
  looked like the start of a new act when loaded; what belongs to the
  Telling is now put back after the road is.

## D-043 (M6, 2026-11-17) The Adaptations and their two synergies

- **Fitting.** Whatever in the cabin works by being there is read into the
  other systems whenever the cabin changes (`DriveSim._fit_cabin`, on
  `ItemSim.cabin_serial`): wheel rates, sideways speed, the fifth gear, lamp
  capacity, and where each anchor is.
- **Crossover stalk.** It moves the `indicator_stalk` anchor to (0.20, 0.14,
  -0.12): right of the column, 0.09 s from the wheel, clear of the other
  controls on screen. The item's params say so (`moves_anchor`,
  `moves_to`); the snapshot carries `anchor_moves`.
- **Console window switch.** A new anchor `window_switch` at (0.20, -0.13,
  0.12), a Near reach (0.20 s), with a HOLD of 0.6 s. The crank stays where
  it is and still works.
- **Wheel ring.** Read literally ("setting it locks the wheel at its current
  angle") the hook would be useless: the hand must leave the wheel to tap
  it, and a wheel let go is back at centre before any TAP can land (200
  degrees a second). So: a TAP at the `hook` anchor (inside the rim, 0.16 s
  from the grip) hangs the hook in its ring, and there it waits. The next
  time his hand lets go of the wheel, the hook holds the wheel at the angle
  it has, for `hook_lock_s` (4 s) at most; taking the wheel again ends it
  at once. Then the hook is out of its ring for `hook_cooldown_s` (6 s)
  and must be set again. It holds the angle, not the lane: the crown and
  every other drift still carry the car. A stop takes the hook out of its
  ring (every status ends there).
- **Ring + Spinner knob.** While the hook holds and the road is straight
  (no bend under the car), it turns the wheel to bring the car to the
  middle of the lane it is in within `hook_settle_time` (0.5 s) and keep it
  there against the drift. In a bend it holds a fixed angle like the ring
  alone.
- **Thumb keypad.** `pad_horn` (middle click) and `pad_wiper` (scroll, either
  way) work only while he grips the wheel and only with the keypad fitted;
  each press is one honk or one sweep, with all the horn's and the wipers'
  own rules.
- **Stalk + Keypad.** He indicates by himself when a lane change begins:
  when the side of the car is over a lane line with a lane beyond it and
  the car is moving that way. The indicator is then on by the time the car
  crosses, so the patrol has nothing against him. Drifting onto the
  shoulder is no lane change.
- **Loud horn.** Every vehicle ahead in his lane within the horn's range
  moves over if the next lane is free, whatever its type (the motorcade
  holds every lane, so it has nowhere to go). The honk's calm is -5 in
  place of -3, still once per cooldown; a honk in view of a patrol is the
  honk's +15 and 15 more.
- **Fog lamps.** +40% of whatever limits his view: the headlight cone at
  night, the dust's visibility, and in rain the time a sweep keeps the
  glass clear (6 s becomes 8.4 s). Each oncoming vehicle met flashes back:
  +2 Nerves. A vehicle is met when it passes the car on an undivided road.
  The rule of GDD 4.6 that each oncoming vehicle met on high beam adds 2
  Nerves was missing and is now there too; the two add up.
- **Wide mirror.** What the mirror tells him comes 5 s earlier: the patrol's
  blue lights, and the tailgater's car behind. A cracked mirror's 2 s of
  delay, until now only a number in the snapshot, works the same way with
  the other sign; both together are 3 s early. `mirror_scale` (1.5) in the
  snapshot is for the view.

## D-044 (M6, 2026-11-17) The Deals and the Phantom

- **Forged papers.** A small thing for the dash or a glovebox cell,
  contraband while he has it. `DriveSim.use_forged_papers()` is what the
  Checkpoint's Papers phase (M7) will call: true once, and the papers are
  gone. Until M7 the test checks that call; a check at the real Checkpoint
  is owed to T-ITEM-FORGED-PAPERS then.
- **Tinted glass, turbo, the good stuff** take no slot: they are the car's
  own, and his the moment he buys them (D-037). Tinted glass and the turbo
  cost no cash: their price is the lamp. Suspicion "gains" are everything
  that raises it, at once or by the second; what wears it off is not
  slowed. Lamp capacity changes add up (tinted and turbo: 3 lamps; a bull
  bar gives one back). "Braking 30% weaker" is `brake_decel` times 0.7.
  "20% darker" is, like the sunglasses' 15%, distance at night, and the
  two add (35%).
- **The good stuff.** Courage stacks to 5 instead of 3, and it is one
  permanent source of Lag (40 ms sober; five stacks and it are 240 ms,
  held at `lag_cap`). At four stacks and more nothing frays him at all
  (1 - 0.3 n, never below nothing).
- **The flinch.** A cross-reach begins when the hand, on his side of the
  hub, is sent to a control on the far side (an anchor with x below 0). If
  his Nerves are `phantom_flinch_from` (60) or more, or his lids are
  closing, the hand stays where it is for `phantom_flinch_delay` (0.25 s)
  before it leaves, while the snapshot shows the ghost going for that
  control (`ghost_at`, `ghost_progress`). A hand already across does not
  flinch on its way to the next control there; the next cross-reach does.
  Gripping the left of the rim is not a reach for a control. An Adaptation
  that puts the control on his side (the crossover stalk) or gives him
  another on his side (the window switch) takes the cross-reach away, and
  the flinch with it, by geometry alone.
- **The cramp.** In a leg with rain or night, when the car passes
  `phantom_cramp_at` (half) of the leg's length, a hum begins
  (`phantom_hum`; `cramp` in the snapshot is "hum"); `phantom_cramp_hum`
  (1.5 s) later the cramp: +10 Nerves, and for `phantom_cramp_length`
  (0.5 s) a hand on the wheel cannot let go (it still steers), a hand off
  it cannot take the wheel or begin anything at an anchor, and a lever in
  the hand is not let go. The point is of the road, so a leg has one; a
  stop does not bring it back. Painkillers taken before the point (or
  during the hum) mean no cramp in that leg. The Storm's cramp is M7.
- **The setting.** `DriveSim.phantom_enabled` (GDD 17.1, "The Phantom: on or
  off"); the settings screen that sets it, like those for steering
  sensitivity, grip mode and shifting, is M10.
- **Numbers of 7.9** are in tuning.json (`phantom_*`).

## D-045 (M6, 2026-11-17) What the items look like

- **An item in a reachable slot** is drawn at its slot from its own
  placeholder (`item_<id>`); contraband wears a small magenta tag over it
  (GDD 16.1). A ringing phone rises and falls on its mount twice a second
  (under the three flashes a second of GDD 16.4).
- **Fittings** (anchors.json `fittings`): what an Adaptation adds to the car
  is drawn while its item is in a bay: the spinner knob and the thumb
  keypad on the wheel (they turn with it), the ring at the hook's anchor,
  the crossover stalk's lever, the console switch, the bull bar and the fog
  lamps at the front of the hood, where they take a little of the road
  from his view. The taxi sign is on the roof and cannot be seen from the
  driver's seat; the fifth gear, the loud horn, the turbo, the tinted glass
  and the good stuff have nothing to draw yet (the tint is for the post
  effect of M10).
- **A moved anchor** is drawn where the snapshot's `anchor_moves` says, and
  so is an item whose slot it is. The wide mirror widens the mirror.
- **The hand** carries what it carries (the item's own placeholder, or a
  plain box for his licence and banknotes). Under Lag it is drawn where the
  wheel was when the car last answered: it trails the wheel. The ghost of
  the Phantom is a faint arm and hand from the pinned sleeve to the control
  and a little through it.
- **Sway** rolls the camera (`sway_view_roll` degrees per m/s of push).
- **Command line.** `--give=<item>[,<item>...]` puts items in the cabin and
  `--hud` starts with the numeric HUD showing (both for looking at things;
  the debug keys of GDD 13.9 are M10). The smoke test now also drives a
  Rain leg with a cabin full of items.
- **Three bays** hold at most three Adaptations: `--give` with a fourth
  takes the place of the first.

## D-046 (M7, 2026-11-17) Bosses as roads with a plan; the Storm

- **A boss is a stretch with a plan.** `BossSim.plan(data, boss, modifier,
  seed)` makes a plan like a leg's (LegSim runs its vehicles and gusts) with
  the boss's id and what else the road brings: its gusts' push, what a wiper
  sweep smears, what an open window lets in. `BossSim` keeps what goes by
  the clock and reports it tick by tick, as `EncounterSim` does. Whatever
  road `DriveSim._set_stretch` begins, the boss of its plan begins with it,
  and any other road ends it. `DriveSim.begin_boss(id, modifier, seed)`
  starts one by itself (tests, `--boss=`).
- **Numbers.** Each boss's record in legs.json carries its numbers in an
  object of its own name (`storm`), checked by the validator. GDD 15: "all
  ... boss numbers in Part II are also tuning values. Store them in their
  own data files."
- **Boss modifiers** (GDD 10.2 to 10.4) are the record set `boss_modifiers`
  in legs.json: `long_queue`, `thorough`, `crosswind`, `night_storm`,
  `market_day`, `early_sun`, each naming its boss and the one number it
  changes. The Storm's Crosswind is not the leg modifier of that name (a
  GUST beat every 15 s): it makes the Storm's own gusts 50% stronger.
- **Which Telling has which.** The GDD gives every boss two modifiers and no
  rule for when. `boss_modifier_chance` (new, per act: 1/3, 1/2, 2/3) of
  Tellings give the act's boss one of its two, each as likely as the other,
  by the Telling seed (`RunGenerator.boss_modifier`). The shares rise by act
  like every lever of GDD 12.3, but start above the legs' "none" in Act 1:
  with that the Checkpoint's two modifiers could never be met.
- **The tea stall's sign** (GDD 9.6): after tea (a tea stall, or a boss stop
  that became one) the next fork's sign carries `boss` and `boss_modifier`
  ("" for none) of the boss ahead of that fork. It is one sign: taking the
  fork clears it. The save keeps it (`boss_sign`), since the next fork may
  lie behind a boss stop.
- **The Storm's dust** goes by the clock of the road: `thin_s` (8 s) of thin
  dust, then `thick_s` (12 s) of thick, over and over, from the moment he
  drives in. It opens thin: the first wall of dust has 8 s of tell (pillar
  4), and the rhythm is the tell of every one after it. Each change falls
  on the tick nearest its time. Focus slows it with the rest of the road.
  Standing still does not wait it out and brings the end no nearer.
- **Gusts** come every `gust_every_s` (9 s) at par, 250 m apart, from either
  side by the seed, at `gust_push` (2 m/s; 3 with Crosswind), announced
  `gust_tell` (1 s) ahead with their direction, like a leg's. A leg's tell
  now lasts a whole number of ticks (it ran one tick over).
- **Tail lights.** One vehicle at a time, 140 to 220 m apart, at 60 to
  70 km/h, never two in a row in one lane: there is always something to
  follow and always a way past.
- **Haze.** In the Storm each sweep of the wipers (from the stalk or the
  thumb keypad) adds `wipe_haze` (10%) up to `haze_cap`; an open window adds
  `window_haze_per_s` (5% a second) and, as in a dust haze, nothing clears
  while it is open.
- **Standing.** "Stopped" is at `stopped_kmh` (1 km/h) or less. Safe is
  wholly off the lanes (the left side of the car right of the road's edge)
  with the hazard lights on. Otherwise, every `rear_end_every_s` (10 s) of
  standing, something may come out of the dust behind him: the draw (from
  the road stream, `rear_end_chance` 0.5) is made `rear_end_tell_s` (1 s)
  before, and only what will hit him shows itself, by its horn
  (`sfx_requested` horn, `behind`) and its lights (`rear_end_in` in the
  snapshot). A car that has moved off or made itself safe within that
  second is missed. The hit is a crash (two lamps, +20 Nerves, first gear)
  with `rear_end` in its event. GDD 10.3 says "risks"; the tell is pillar 4.
- **Night storm** is the Storm's road with the leg condition `night`: the
  view is the headlight cone, so he sees the nearer of the cone and the
  dust (with both headlights the dust is always nearer).
- **The cramp** fires at `phantom_cramp_at` of the Storm's road, as in a
  Rain or a Night leg, once.
- **Heavy floor.** The Storm has Act 2's (GDD 6.1) because its plan is of
  Act 2; an empty road calms him there as on any road that is no encounter.

## D-047 (M7, 2026-11-17) Dawn, the Call, the Arrival

- **Dawn's road** is laid out by the leg generator (`LegGenerator.
  generate_road`): the Rush leg's beat weights, 3,333 m with the last 150 m
  left empty, heavy traffic (16 vehicles per km in all), under the rules of
  GDD 9.2, around a stretch reserved for the last checkpoint: no beat is
  laid there, no vehicle is beside him there at par, and the planned line
  runs through it in the middle lane. "Rush traffic builds": of what the
  generator puts before sunrise, `builds_from` (a quarter) is kept at the
  very start and all of it at sunrise, by a seeded draw per vehicle.
  Market day multiplies the density by 1.3 before that. (At a base of 16
  per km plus the act's 4, a Market day's road took up to 39 draws and over
  a second to generate; at 12 plus 4 it takes two at most.)
- **Phases** go by where he is: the false dawn to `sunrise_at_m` (1,250 m),
  the sunrise from there, the Call from 833 m before the end. The glow of
  the false dawn is on the right all through Dawn (`glow`, `glow_side` in
  the snapshot); the sun is ahead and to the left (`sun_side`).
- **Heavy floor** in Dawn and on the street of the Arrival is the road's own
  (0, GDD 6.1), not Act 3's: a plan may carry `heavy_floor`.
- **Glare.** The sun comes up over `glare_ramp_m` (60 m, about 2 s at par):
  it is seen before it blinds (GDD 5.8). Then Glare 60% to the end of Dawn.
  With Early sun it begins at the start of the road. The visor blocks it
  while it is down (`visor_time`, 3 s) and not a spotlight: GDD 4.6 says
  "blocks sun glare". What he wears against Glare works on the sun as well.
- **The last checkpoint** stands at 1,900 m: over a taper of 60 m barriers
  close in from every lane's own lines to 2.34 m apart about the lane's
  middle, and stay so for 150 m. Every lane has its corridor, so traffic
  keeps its lanes. Its sign ([CHECKPOINT / 70]) stands 5 s short of the
  taper at par. Touching a barrier is a scrape; the car is put back at most
  to the middle of the corridor, never into the other barrier
  (`CarSim.wall_left`, `wall_right`).
- **"Waves him through at 70 km/h"** has teeth: his speed is judged once, as
  the car reaches the barriers at their narrowest. Above `max_kmh` he is
  stopped and searched as GDD 10.2 has it for a checkpoint: 15 game minutes
  and the contraband in view taken (`pulled_over` with `paid: "search"`).
  The GDD names no consequence; without one the 70 would mean nothing, and
  the lever is what the hand must leave the wheel for under the low sun.
- **The Call** rings in his pocket for `ring_s` (8 s) of his own time (Focus
  does not slow it). While it rings the pocket offers a TAP (`call_answer`)
  and, with a passenger beside him, a DRAG_TO to their shoulder
  (`call_hand_over`); a DRAG_TO let go within a TAP's time with the hand
  still there is the TAP (the rule that makes a slap of a short press on
  his face now holds for DRAG_TO too).
  - Ignored: `call_resolved` unanswered, and no cost at all.
  - Alone: the hand goes to his ear (point `ear`) and stays there for
    `talk_s` (30 s). It can reach nothing and grip nothing. His wrist is on
    the wheel: the pointer steers at `wrist_steer` (40%) with no button
    held, and the wheel does not return to centre.
  - With a passenger: nothing is in his hand; he grips and steers as ever
    but can reach for nothing for 30 s.
  - Pulled over: answered in a car that is stopped (1 km/h or less), wholly
    off the lanes, with the hazard lights on (GDD 4.6: "needed to stop
    safely on the shoulder"), the car stands until he hangs up, whatever
    his foot does, and the Clock runs: 30 s are 10 game minutes. Stopped
    anywhere else, or dark, it is a call taken alone in a car that is free.
  - The end of Dawn's road hangs up. That he answered is in `arrived`
    (`call`) and in the save (`call_answered`). Until M8 "a passenger
    beside him" is the cabin switch `passenger`.
- **The Arrival** is a street (`arrival` in legs.json; `arrival_length` left
  tuning.json): 300 m, one lane each way, nothing on it. The bay is its
  last 12 m, across its whole width. He is in the bay when the car stands
  (1 km/h or less) with its tail past the bay's line. Then the key (a new
  anchor, `key`, under the wheel) can be turned with a TAP, and the Clock
  is read at that moment. The street's end is solid: met at more than
  5 km/h it is a hit of the class of that speed (first gear unbraked is a
  crash), and the car stands against it, which is in the bay. So there is
  no place on the street from which he cannot arrive.
- **The scripted driver of T-RUN-01** now drives the Storm (looking where
  he goes, braking behind what he cannot pass), Dawn (the planned line to
  the checkpoint, second gear between its closing barriers, then looking
  where he goes: after 150 m at 70 he is off the plan's pace) and the
  Arrival (brake into the bay, hand to the key).

## D-048 (M7, 2026-11-17, built 2026-11-20) The Checkpoint

Decided on 2026-11-17 and built as written on 2026-11-20 (T-BOSS-01), with
three additions made while building:
- **The car stands from the Stow to the verdict.** Once the soldier starts
  toward him the car is held where it stopped, whatever his foot does,
  until he is let through or turned back (as for the Call taken pulled
  over, D-047). Without that he would have to hold the brake through ten
  seconds of hand work, or roll into the bar in first gear and be scraped
  by it.
- **"At the bar"** for a queue vehicle is within `settle_m` (0.1 m) of it.
- **A search takes everything** at Dawn's last checkpoint too
  (`take_all_contraband`): T-BOSS-03's check of that was changed with it.

- **The road** (500 m, three lanes): a sign 5 s short of a 60 m taper; from
  200 m every lane is a corridor between barriers 2.34 m apart (the walls of
  D-047) for 150 m, to the bar at 350 m; then open road to the boss stop.
  Suspicion is watched from the start of the Checkpoint to the verdict and
  does not wear off there (`SuspicionSim` gets a switch for the decay); the
  Patrol's rows of GDD 6.5 do not apply, only the Checkpoint's own, and
  nobody is pulled over at 100. Touching a barrier (a registered scrape with
  `car.wall_touched`) is +25. The bar holds the car (as the street's end
  does) until he is let through; met at more than 5 km/h it is a barrier
  touch.
- **Queue.** Six vehicles stand in each lane's corridor, nose to tail 2.5 m
  apart, the first at the bar (types drawn into the plan by the boss seed).
  The one at the bar is served for 4 s and leaves at up to 40 km/h; the
  rest pull up behind it (speed = room x `pull_up_per_s`, at most 12 km/h):
  stop and go, about 7.4 s a vehicle, some 45 s in all. `BossSim` moves them
  itself after `TrafficSim.step` (their cruise is 0 for TrafficSim, whose
  12 m follow gap would spread the queue out). Long queue: nine vehicles.
- **Stow.** He is first in line when no queue vehicle of his lane is left
  ahead and he stands (1 km/h or less) within 8 m of the bar. The soldier
  then takes `stow_s` (10 s) to reach his window. At the end of them: +40
  for each contraband item not in a glovebox cell and +15 for each Courage
  stack the soldier notices (`courage_noticed()`: none with mints).
  Stowing is a DRAG_TO from the item to the glovebox, offered instead of the
  item's own rituals while the glovebox is open and a cell is free (`stow`,
  a ritual contraband items share; `ItemSim.ritual_at` hands it out with the
  item's id). What is in a cell is out of use: its rituals are not offered.
  Taking it out is a DRAG_TO from the open glovebox to a free slot it fits
  (`unstow`, `"to": "@home"`); a short press there is still the TAP that
  shuts the glovebox (the TAP beside a DRAG_TO of D-047).
- **Papers.** The soldier's sign names one of three documents (two, one
  after the other, when Thorough), drawn into the plan by the seed. The
  status `at_window` is held while he waits. Licence: DRAG_TO from `dash_1`
  (before whatever sits there); ID: DRAG_TO from `pocket`; registration: in
  the open glovebox, after the letter has been moved aside (a HOLD of 0.4 s
  there, cabin switch `letter_aside`), DRAG_TO from `glovebox`. All go to
  `driver_window` and are offered only with the window open (CRANK(3) at
  the crank, or the window switch); with it shut the soldier taps on the
  glass (`soldier.window`). The wrong document is refused and costs only
  its time. Every full 5 s since a sign went up: +10. Forged papers pass
  the phase the moment it begins and are gone (after the Stow count, where
  out of the glovebox they are contraband like any other).
- **Verdict**, when the last document is handed over: under 50 he passes;
  from 50 he is searched (15 game minutes, every piece of contraband taken,
  stowed or not: `take_all_contraband`), then let through; at 100 he is
  turned back: 30 game minutes, the car at the start of the Checkpoint's
  road again in first gear, a new queue, Suspicion from 0. 60 cash
  (`checkpoint_bribe`, DRAG_TO from `cash` to the window while the soldier
  waits) passes at any level; without 60 he is refused. Each is announced
  as `pulled_over` with `paid`: pass, search, turned_back or bribe.
  Dawn's last checkpoint (D-047) should then also take everything on a
  search, as here.
- **Records.** In legs.json, in the checkpoint's record:

      "checkpoint": {
        "corridor": {"at_m": 200, "length_m": 150, "taper_m": 60, "gap_m": 2.34, "sign_lead_s": 5},
        "barrier_suspicion": 25,
        "queue": {"cars": 6, "gap_m": 2.5, "creep_kmh": 12, "pull_up_per_s": 2.0, "serve_s": 4,
                  "leave_kmh": 40, "clear_m": 4, "vehicles": ["car", "taxi", "pickup", "minibus"]},
        "stop_zone_m": 8, "stopped_kmh": 1, "bump_kmh": 5,
        "stow_s": 10, "contraband_suspicion": 40, "courage_suspicion": 15,
        "documents": ["licence", "id", "registration"],
        "delay_every_s": 5, "delay_suspicion": 10,
        "pass_under": 50, "turned_back_at": 100,
        "search_minutes": 15, "turned_back_minutes": 30 }

  In rituals.json (ops `hand:<what>`, `stow`, `unstow`; conditions
  `glovebox_room`, `stowed`; switch `letter_aside`; status `at_window`):

      { "id": "papers_licence", "anchor": "dash_1", "gesture": "DRAG_TO", "to": "driver_window", "eyes_down": true,
        "over_items": true, "requires": ["at_window", "flag:window_open"], "on_complete": ["hand:licence"] },
      { "id": "papers_id", "anchor": "pocket", "gesture": "DRAG_TO", "to": "driver_window", "eyes_down": true,
        "over_items": true, "requires": ["at_window", "flag:window_open"], "on_complete": ["hand:id"] },
      { "id": "letter_aside", "anchor": "glovebox", "gesture": "HOLD", "hold_s": 0.4, "eyes_down": true, "over_items": true,
        "requires": ["at_window", "flag:glovebox_open", "!flag:letter_aside"], "on_complete": ["toggle:letter_aside"] },
      { "id": "papers_registration", "anchor": "glovebox", "gesture": "DRAG_TO", "to": "driver_window", "eyes_down": true,
        "over_items": true, "requires": ["at_window", "flag:glovebox_open", "flag:letter_aside", "flag:window_open"],
        "on_complete": ["hand:registration"] },
      { "id": "checkpoint_bribe", "anchor": "cash", "gesture": "DRAG_TO", "to": "driver_window", "eyes_down": false,
        "over_items": true, "requires": ["at_window", "flag:window_open"], "on_complete": ["hand:banknotes"] },
      { "id": "stow", "anchor": "@slot", "shared": true, "gesture": "DRAG_TO", "to": "glovebox", "eyes_down": true,
        "requires": ["flag:glovebox_open", "glovebox_room"], "on_complete": ["stow"] },
      { "id": "unstow", "anchor": "glovebox", "gesture": "DRAG_TO", "to": "@home", "eyes_down": true, "over_items": true,
        "requires": ["flag:glovebox_open", "stowed"], "on_complete": ["unstow"] }

  `stow` goes first in the rituals of `arak_flask` and `forged_papers`.
  Lines: `sign.document.licence`, `.id`, `.registration`, `soldier.window`,
  `soldier.wrong`.
- **Tests.** T-BOSS-01 on `CabinSuite` (`_crank`, `_drag`, `_tap_at`,
  `_begin_quiet_boss`); the owed checks of T-ITEM-BREATH-MINTS and
  T-ITEM-FORGED-PAPERS at the real Checkpoint; the scripted driver of
  T-RUN-01 through the queue, the window and the papers. A car set down
  beyond the bar by a test is not held by it (only crossing it is), so the
  suites that jump a Telling forward keep working.

## D-049 (M6 review, 2026-11-20) Rulings on the findings of the items review

The review `m6-items-review` (four lenses, 49 findings with overlaps, in
`wip/m6_review_findings.json`) asked for these decisions. They are being
built by the workflow `m6-fixes`; this entry is what that work is held to.

- **At a stop and while pulled over the hand does only what the stop or the
  officer is there for:** the vendor's tray, placing what he bought, and
  gripping the wheel to leave; his licence or banknotes for the officer.
  The cabin's own rituals are not offered there. (The review's "owner's
  call": beads gave unlimited calm at a two-minute stop, and a cigarette,
  three sips and a pill could be loaded at the stall to start whole on the
  road. GDD 2.2 pillars 1 and 3, 12.4 rule 3; 9.6: "the hand does the
  shopping".)
- **Pulled over, the night waits as at a stop:** no timer runs, no call
  rings, Nerves keep still. A Snap's two seconds are the hand's time and
  are counted down at a stop and with the officer.
- **"Once per leg"** (the photo, the charm's first scrape, statuses held for
  the leg) renews when a leg begins and when a boss begins, nowhere else;
  every save keeps it.
- **A stop cancels nothing that is owed:** the craving and the wait for the
  next call keep their seconds through it.
- **Firsts are firsts** whether or not the keepsake is aboard yet (the
  charm's scrape of the leg, the tape's fault of the act).
- **What a stop ends is announced** before the simulation is rebuilt there.
- **A ritual's requirements are checked again when its gesture completes.**
- **A carried thing's destination comes before another anchor at the same
  place** (the tape deck before the radio's dial).
- **A gust lasts its second of road time** (Focus stretches it with the road).
- **The cigarette's calm ends on a whole tick.** The order in which a status
  is counted down and read within a tick stays (on for exactly its ticks
  from the tick it is added; what reads it late in that last tick misses
  it: 0.03% of a 25 s status).
- **After a Wreck there is no saved Telling** to continue.

## D-050 (M7, 2026-11-20) The views of the set pieces; `--boss=`; the stand-in at the wheel

- **Context.** GDD 10.2 to 10.5 say what happens at a set piece and 16.1 how
  things look; nothing says where anything stands. The pictures taken while
  building the views also showed two things the rules had left open.
- **On the road** (`SetPieceView`, a child of `RoadView`):
  - *Barriers* are drawn where the simulation has them: from each lane's own
    lines two faces close in to the corridor's mouth, and from there one
    block of concrete fills what the corridors leave of a lane. Each has a
    lighter cap, so that in flat colours its top can be told from its face.
  - *The bar* is one per lane, hinged on its left. His own goes up when he
    is let through; another lane's is up while a vehicle that was waved on
    drives under it.
  - *The soldier* is a khaki capsule. He waits beyond the bar on the
    driver's side, walks to the car during the Stow, and stands beside the
    front wing for the Papers: there his sign (`sign.document.<id>`, a text
    that always faces the driver) is in the windscreen and not behind the
    pillar. At Dawn's last checkpoint one stands at the barriers' mouth.
  - *Signs.* "[CHECKPOINT / 70]" before Dawn's barriers, "[CHECKPOINT /
    STOP]" before the Checkpoint's. After tea the fork's sign carries the
    boss ahead over its two branches: "[CHECKPOINT / LONG QUEUE]", or
    "[CHECKPOINT]" when it has no modifier. The lines
    `sign.boss_modifier.*` are names without brackets now, parts of that
    sign like `modifier.*.name`.
  - *The Arrival.* The bay is paint and four lines on the lane's last 12 m.
    The street ends at a house, "[THE HOUSE]" (`sign.arrival`, a
    placeholder for the writer).
  - *A gust's tell* (`GustView`): streaks of dust that blow across the road
    the way the car will be pushed, for the second before it is. GDD 5.4
    asks for it on every leg; until now it was only a number on the HUD.
- **In the sky:** Dawn's glow is a flat orange band on the right of the
  horizon, the sun a disc ahead and to the left that climbs as its Glare
  comes on (the flare on his view is the post effects'). Dawn driven by
  itself lightens along its road; in a Telling the sky follows the Clock.
- **In the cabin:**
  - A prop may show a cabin switch: `flags` (drawn only while each is as
    written, "!" for off), `blink`, `alpha`. With that the window has
    glass, the hazard button a lamp, the glovebox a door; in the open
    glovebox lie the letter, the registration under it (the letter leans
    aside once it has been moved), and what is stowed, each thing in its
    cell. Shut, none of it is seen. His licence stands clipped on the dash.
  - The mirror has a glass. In it: the two lights of what comes up behind
    him in the dust, nearer and wider apart through the second of tell
    (GDD 10.3), and the blue of a Patrol, brighter with his Suspicion (GDD
    16.3). At the Checkpoint nobody is behind him and the mirror stays
    dark. A wide mirror now widens in place (the group it hung in was
    scaled about the wheel hub, which slid it 21 cm to the right).
  - During the Call the phone is in the hand at his ear; while it rings,
    his own phone is lit at his pocket.
- **Two rules the pictures asked for.**
  - *With the phone at his ear his eyes are on the road.* The Glance of GDD
    4.7 follows a reach ("far reaches cost road view"); a phone held to
    his ear is none. Read to the letter it turned the view 35 degrees to
    the right for all 30 s of the Call, in rush traffic, steering at 40%.
    The cost of answering alone is the wrist and the hand (GDD 10.4).
    T-CALL-01 checks it.
  - *The ring is written out.* His pocket is below what he can see, so the
    phone's shaking is no tell. When the Call begins the simulation asks
    for the line `call.noor.rings` beside the sound (GDD 17.2: every tell
    has both a sound and a visual). T-BOSS-03 checks it.
- **`--boss=<id>[,modifier]`** drives a boss of legs.json by itself, and
  `--boss=arrival` the last street; each begins again with the next seed
  when it ends. `--shot-frame=a,b,c` saves several pictures in one run.
- **The stand-in at the wheel** (`StandInBot`, behind `--bot=`) is a class
  of its own now and gets through every set piece: the brake behind the
  queue and at the bar, the window and whatever the soldier's sign asks
  for, second gear between Dawn's barriers, the lane with the most room in
  the dust, the brake into the bay and the key. It works the hand through
  the input as a player does and puts the car where it wants it; it lets
  the Call ring out. The DriverBot of GDD 13.8 (M11) replaces it.
- **Smoke runs:** the four set pieces, each to its end and into its next
  round.
- **Tests.** The mutation run of the Checkpoint (54 changes, 46 caught)
  left eight alive, and Dawn's two: T-BOSS-01 now also checks that
  Thorough never asks twice for one document, that nobody in a queue
  drives into the vehicle leaving it, that a honk moves nobody out of a
  queue even with free road beside it, that he does not tap on an open
  window, that scraping a vehicle is no touch of a barrier, that a car
  inside a queue vehicle is never put through a barrier, that a stowed
  flask cannot be drunk from behind the shut door, and that a full
  glovebox takes nothing more; T-BOSS-03 that most of the traffic is there
  by the second half of the false dawn and that he meets no vehicle between
  the last checkpoint's barriers.
- **Pictures:** `artifacts/m7_*.png`.

## D-051 (M8, 2026-11-20) The five passengers

- **Context.** GDD 8 gives the rules of passengers and a table of five; GDD
  14 gives one record as an example. How a passenger is met, how a ride is
  counted, and what several cells of the table mean in the simulation's
  terms is not said.
- **`PassengerSim`** (GDD 13.2) keeps who rides and what they are doing; a
  passenger is a record of passengers.json. Besides GDD 14's fields (`hand`,
  `weights`, `on_leave`, `rides_legs` or `rides_until`, `fare`,
  `line_prefix`) a record may have `always` (`suspicion_gain_mult`,
  `fork_sign_lead_s`, `answers_calls`, `effects`), `sleeps`, `drums`,
  `repairs`, `retunes` and `view_block_right`. A Weight is `when` (a tag of
  what he uses, a gear, a gear in rain, asleep, a scrape, drumming under a
  Patrol), a `resource` and an `amount` or a rate. The validator knows all
  of it and asks for the five of GDD 8.2.
- **Where hitchers stand.** A stop's record says `"hitcher": "always"` (the
  Hitcher stop) or `"sometimes"` (fuel stations and tea stalls: at
  `hitcher_chance`, 0.25, of them; GDD 8.1 says "sometimes"). Who stands
  there is drawn from the Telling seed and the stop's place in the night,
  each of the five as likely as another, without drawing from the streams
  the stops' stock uses (so no stop sells anything else than it did). Never
  the one he already carries: the next of the five stands there instead.
- **Getting in.** A new anchor, `passenger_door` (0.96, -0.04, 0.10), 0.57 s
  from the wheel like the glovebox (GDD 8.1: a "glovebox-class Far reach").
  A TAP there is the stop's ritual `stop_board`, offered while a hitcher
  stands there and the seat is free. Leaving the stop is declining.
- **The seat.** What lies on it (the Thermos) goes to a slot `back_seat`
  that no anchor reaches, and comes back when the seat is free. What is
  bought for the seat while somebody sits there goes behind it as well.
- **How far they ride.** A leg is ridden when its stall is behind the car,
  stopped at or not. Nobody gets out of a moving car: a passenger whose legs
  are ridden gets out at the first stop he makes after that, and one who
  rides to the end of the act at the stop after its boss. A boss is no leg.
  One who rides to Basra gets out at no stop, and the `arrived` event names
  them as `guest` (the game adds them to the profile's guests, GDD 11.5).
  The fare is paid on getting out.
- **The Hajjiya.** *"Holds the wheel dead straight"* is read as: the car
  goes dead straight where the road is straight. She holds the wheel
  against what is always there (the crown, a steering that pulls); a bend
  or a gust carries the car off all the same, as their tells say they will.
  With the wheel merely at its centre the crown would have the car out of
  its lane in 3.4 s, exactly as with nobody holding it: her Hand would be
  nothing. Held through bends she would be an autopilot. It ends after 6 s
  or when he takes the wheel. Her food (-20 Nerves) and her blessing come
  as she gets out (GDD 14: `on_leave`); the blessing is kept through stops
  and is spent by the first scrape that nothing else turned aside (the
  charm's first scrape of a leg comes before it).
- **The Conscript.** The uniform halves every gain of Suspicion, asleep or
  awake, the Checkpoint's included. He gets in asleep. A tap or the horn
  wakes him for 20 s; the tap that wakes him is not yet a cigarette. Awake,
  a tap lights one: it burns in the driver's ashtray as his own would, with
  nothing taken from his pack and no ritual, and he hands over no second
  while it burns. He snores (-0.5 Nerves a second) only asleep.
- **The Drummer.** One tap, two things (GDD 8.2 gives the tap both to the
  tea and to the drum): a tap stops the drum and he holds out the tea beside
  the wheel (the tea's anchor moves to `hand.at`, an at-wheel reach); the
  next tap puts it back and he drums again. "The music effect" is the
  status `music` and the radio's own rate (`radio_music_rate`); with the
  radio on music too it is still one music. The drum blocks the right 10%
  of the view whether he plays or not (a drum on the right end of the dash;
  the snapshot says `view_block_right`). Under a Patrol's ears the drumming
  is +10 Suspicion a second; a checkpoint is no Patrol.
- **The Student.** Every call of the phone is answered in the tick it rings:
  the fare or the calm without his hand, and nothing for a Patrol to see.
  Noor's call is his own to take (GDD 10.4); she holds the phone if he
  hands it to her, as any passenger does. A fork's sign stands 5 s of road
  further ahead of the fork. Her talk keeps him Awake all the time she rides.
- **The Apprentice.** With a lamp lit and no repair yet on this leg he says
  so, 2 s later he leans across the gear lever for 3 s (the lever cannot be
  taken, and is taken out of the hand that holds it), and then the oldest
  fault is mended. "Per leg" renews when a leg or a boss begins. "At its
  current angle" locks the wheel where it is, as the hook does, for 3 s or
  until he takes it. The radio goes to static every 30 s from when he got in.
- **At a stop the night waits** for passengers too: no Hand, no Weight, no
  timers.
- **Views.** A purple capsule in the seat (leaning while asleep), an arm to
  the wheel, the lever or the tea, the drum; a hitcher beside the front wing
  with their name over their head; HUD rows. `--ride=<id>` puts a passenger
  in the seat.
- **Tests.** T-PASS-HAJJIYA (which also carries GDD 8.1: the roadside, the
  door, the seat, where hitchers stand), -CONSCRIPT, -DRUMMER, -STUDENT,
  -APPRENTICE; T-DATA-01 gains the failure cases of the new rules; the
  mutation list is `tools/mutants/passengers.py`.

## D-052 (M10, 2026-11-20) The sound of the game

- **Context.** GDD 16.5 names 31 sounds and says how each is made; it does
  not say how they are played, mixed or kept apart. Built ahead of its
  milestone by a workflow under the rule "nothing under `src/core`" (see
  D-055), then taken in over the set pieces of M7.
- **How a sound is described.** Each entry of `data/sfx.json` says what the
  sound is in a small vocabulary (wave; pitch as `freq`, `freq_to`, `trill`,
  `freqs` or `notes`; partials; a filter; an envelope; `rate`, `duration`,
  `peak`, `seed`) and how it is played (`gain_db`, `loop`, fades, `hold`,
  `functional` with `duck_*`, `every`, `per_minute`, `speed_*`, `per_gear`,
  `warble`). A key nothing reads is an error at boot. Buffers are 16-bit
  mono, normalised to a peak of 0.9; loudness is `gain_db` at playback.
  `SfxSynth` (src/game) makes them; `Audio` plays them from the snapshot
  and from `sfx_requested`. All 33 are made in about 75 ms.
- **The engine** is one saw loop whose pitch follows the speed (60 Hz at 40
  km/h to 180 Hz at 160, held at 30 Hz below). "A different added harmonic
  per gear" is a second entry, `engine_harmonic`: a sine at a harmonic of
  the engine's pitch that drops as he shifts up, silent in neutral.
- **Functional cues** (the rumble strip, the indicator's tick, both yawns)
  play on a bus of their own, and while one sounds everything else is turned
  down by that cue's `duck_db`, so that each stands at least 6 dB above all
  else at once: the check's reading of "audible over everything else".
  There is no limiter (the engine's leaves its bus quieter afterwards).
- **What repeats keeps the simulation's time.** `Audio` steps by the
  snapshot's `time`. The indicator ticks every 0.4 s while it signals; a
  phone rings every 1.4 s while the snapshot names a caller, Noor's too (six
  rings in her 8 s); the siren chirps every 3.0 s at no Suspicion down to
  every 0.8 s at full, wherever he is watched; the heartbeat is heard only
  during Pound, 60 a minute rising to 120 at the Snap. Hazard lights tick
  only when toggled (a steady tick would hold everything else down).
- **A 33rd sound, `horn_behind`**: what comes up behind his standing car in
  the Storm is two square waves lower than his own horn, for the whole
  second of its tell, because the tell of a crash must not be taken for the
  honk he makes himself. It is not a functional cue (GDD 16.5 names four).
- **Not invented:** sounds for a gust's tell, the dust thickening, the low
  sun, a checkpoint's sign, the key of the Arrival, the passengers. The
  table of GDD 16.5 has none, GDD 1.5 forbids resources the document does
  not name, and the mix has about 0.1 dB of room left under the 6 dB rule.
  GDD 17.2 ("every tell has both a sound and a visual") is therefore not
  met for those: NEEDS OWNER. (Superseded by D-058: the tells have their
  sounds.)
- **Tools.** `tools/audio_check.gd` (a step of `tools/check.sh` after the
  data validator; with `-- --wav=<folder>` it writes every buffer for
  listening) and `tools/audio_drive_check.gd`, which holds what needs the
  autoloads. `I99_AUDIO_LOG` in the environment prints every sound that
  starts or ends.
- **Nobody has heard it.** There are no speakers here: levels and character
  come from measurements and an offline recording. NEEDS OWNER.
- **After its review** (merged as `m10/audio-in-fix`):
  - Every `gain_db` is 5 dB lower, cues and the rest alike: the three cues
    that can sound at once came to 1.7 of full scale. The check now adds
    up the cues' peaks and fails above full scale.
  - The added harmonic is the 12th, 11th, 10th, 9th and 8th of the engine's
    pitch in gears 1 to 5: at low harmonics the two loops, each at its own
    phase, could cancel instead of add.
  - A Wreck silences everything the snapshot drives (the horn of a Snap,
    the horn behind him, the hum, the heartbeat, the phone, the siren, the
    indicator), as it did the engine. What had been asked for by itself
    plays out into the cut. The radio plays on over it: NEEDS OWNER.
  - A sound that repeats follows a gap that has grown shorter at once (a
    jump in Suspicion or Nerves is heard within one new gap).
  - Keys that say how a sound is played and mean nothing for that sound
    are errors at boot, like the generator's.
  - **A 34th sound, `rattle`**: GDD 16.3 asks for "each fault's visible or
    audible effect" and the Rattle had neither. Quiet bursts of noise, a
    higher band and slower than the rumble strip, no functional cue; heard
    while the fault is lit and the engine runs. It is one commit
    (4078d17) so that it can be taken back by itself. NEEDS OWNER.

## D-053 (M10, 2026-11-20) The post effects

- **Context.** GDD 16.4 lists the effects and their strengths; a canvas
  shader cannot read depth, so "on the glass" had to be given a meaning.
- **Files.** `shaders/post_fx.gdshader` and `src/view/post_fx_view.gd`
  (`PostFxView`, the CanvasLayer `PostFX` between `Sky` and the pointer's
  layer), rather than the `postfx.*` of GDD 13.2. `setup(data, camera,
  cabin)`, `apply(snapshot, delta)`. With nothing to show the rectangle is
  hidden: no screen copy, no shader.
- **Where the glass is.** Each pixel's ray is met with three panes given in
  tuning (`postfx_windscreen`, `postfx_window_left`, `_right`); what is
  drawn under the cabin's Mirror and Visor nodes is taken out again.
  Haze, rain blur and cracks are on the windscreen only; the night, the
  glare and the falling rain are outside every window. The cabin takes 40%
  of the darkness and 15% of the glare. The lowest 5 cm of windscreen stay
  clear, so the clock and the nearest 12 m of road stay readable.
- **Each effect.** Haze is a drifting veil never thicker than the
  snapshot's, dust-coloured in the Storm and by day where the view ends,
  smoke-coloured otherwise. "Cracks cover 20% of the view" is that share of
  the windscreen: a web round a point of impact, fixed to the glass. Glare
  is a wash at the light with a small blaze; the light is where the
  snapshot's `glare_position` says (degrees right of dead ahead, degrees
  up), else straight ahead (the motorcade's spotlight). The simulation
  gives that key while Dawn's sun is up: `sun_side` times `sun_position`
  to the side, climbing from `sun_rise_from` to 14 degrees as its Glare
  comes on, which is inside what the lowered visor covers. The sky draws
  its disc at the same place (at the merge the sky of D-050 and the post
  effects each had a sun of their own, 10 degrees apart).
  The view never reads `visor_down`: a blocked sun is a Glare of 0. At
  night what the headlights do not reach loses 80% of its light; the pool
  is as wide as the headlights let him see. Tunnel is an ellipse that
  shrinks to `tunnel_min_view`; Lids are soft bars; a Blink sweeps them
  shut and open in 0.06 s.
- **No more than three flashes a second** is kept in the view: every amount
  is eased and one that has turned may not turn again for 0.17 s.
- **Left to others.** The dust in the air, the false dawn's glow and the
  streaks of a gust are the world's (sky and road views, D-050); the
  Wreck's cut to black and the prologue's white-out are M9's.
- **Tools.** `tools/post_fx_check.gd` (the last step of `tools/check.sh`)
  and `tools/post_fx_shots.gd` (pictures of states over the drive scene;
  fifteen are in `artifacts/m10_postfx_*.png`).
- **Not run:** Forward+ and Mobile (no Vulkan here), and no frame time on a
  GPU. NEEDS OWNER.

## D-054 (M10, 2026-11-20) Subtitles

- **Context.** GDD 16.6 gives the place, the size of a subtitle and how
  long it stays. It does not say what happens to a longer text, to two
  lines asked for at once, or where the speaker's name comes from.
- **Files.** `src/view/subtitles_view.gd` (`SubtitlesView`, the CanvasLayer
  `Subtitles`: over the post effects, under the pointer) and the pure class
  `SubtitleQueue` (wrapping, timing, the queue).
- **Wrapping.** A character is one code point of the text, the speaker tag
  not counted. A text is cut only at spaces; two lines are balanced. A text
  that needs more than two lines is shown in parts of two lines, each held
  for the larger of 1.5 s and 0.06 s a character of its own.
- **The queue.** Lines asked for while one is showing wait in order;
  nothing is dropped or cut short except by a clear. A `wreck` clears what
  is showing and waiting (the Wreck cuts off what was being said), so the
  Table's objection must be asked for after it. A subtitle's time is the
  view's own frame time.
- **Speakers.** The tag is a row of its own above the text. A speaker's
  name is a line: `speaker.` and the name in lower case with underscores
  (`speaker.old_woman`); a speaker with no such line is shown as the column
  has it. A row that holds an exchange ("X, then Y", "a / b") is one
  subtitle per speaker.
- **Settings** (GDD 17.1, Subtitles): `subtitle_size` is "small", "medium"
  or "large" (28, 36, 48 px at 1080p; default medium) and
  `subtitle_background` a boolean (default on: a dark box at 60%; off, the
  letters keep their outline). The keys, the defaults and their live effect
  exist; the screen that changes them is the menus' (D-055).
- **Noor's line** on the Call is asked for by data: the two rituals that
  take the Call carry the op `line:noor.call.1`. A Call left to ring says
  nothing.
- **`--say=<line id>[,...]`** asks for lines when the drive scene starts
  (not in GDD 13.9). `subtitle.test.long` is a test line of 143 characters.
- **Tools.** `tools/subtitles_check.gd` with `subtitles_check_body.gd` (a
  step of `tools/check.sh` between the tests and the smoke runs);
  `tools/subtitles_shots.sh`; pictures in `artifacts/m10_subtitles_*.png`.
  Right-to-left was tried with an Arabic table built in memory.
- **At the merge with M8** the four speakers the passengers brought got
  their lines (`speaker.soldier`, `.drummer`, `.student`, `.boy`).
- **Open.** Bottom-centre subtitles lie over the wheel hub and the key of
  the Arrival (NEEDS OWNER: `subtitle_bottom_margin`). No font slot per
  language yet (GDD 17.3; with the settings). For M9: a heckle's subtitle
  is its 2 s tell, and a line that waits behind another shortens it.

## D-055 (M6 review, 2026-11-20) How the rulings of D-049 were built

Built by the workflow `m6-fixes` on branches of their own and merged here
(`m6fix/seams`, `m6fix/rituals`; what `m6fix/misc` and the tests after it
add is entered below when it is merged). This amends D-031, D-036, D-038,
D-040, D-041 and D-042 where they describe stops and pull-overs.

- **Where the night waits** (`DriveSim._standing()`: at a stop, with the
  officer) step 9 does not run: no effect timer, no item, no Nerves; only
  a Snap's seconds are counted down. The hand is offered what
  `_ritual_at` gives there: at a stop the stop's rituals (the tray,
  placing what he bought, a hitcher's door), with the officer the controls
  whose `requires` name `pulled_over` (his licence, banknotes). An anchor
  is in use only where a ritual is offered, so the lever and the thumb
  keypad wait for the road too.
- **Pulled over** he is found with his eyes open (`NervesSim.rouse`): a
  blink or Nod in progress would otherwise leave them shut for as long as
  the officer waits. A call that was ringing is not dropped there; it
  cannot be answered, and rings on for its remaining seconds when he is
  let go. (At a stop a ringing call is dropped, as D-042 has it, and now
  announced: `call_resolved` with `answered: false`, `dropped: true`.)
- **A Snap that is running as he pulls into a stop is over there** (the
  simulation is made anew and the save does not hold it). The countdown at
  a stop is for a Snap that begins there.
- **Once per leg at the edges.** `_set_stretch(plan, renews)`: a leg and a
  boss renew, the road to a fork, the street of the Arrival and the road
  beside a stop do not. On the road from Baghdad to the first fork nothing
  has been done yet, so a look at the photo there counts and the first leg
  renews it. What lasts "for the leg" and is taken in a boss lasts through
  the boss stop and the road to the next fork and ends at the gore.
  Passengers renew what they do once per leg at the same places (D-051).
- **The save holds two more numbers**, each as the exact bits of a float:
  `lapse` on an item (the seconds until its Craving bites; only while one
  is owed) and `call_wait` in `item_state` (the seconds to the next ring;
  negative while the wait is not drawn). A save without them loads with no
  Craving owed and the wait still to be drawn. A cigarette that a stop
  puts out starts its Craving there.
- **Firsts.** `leg_state.spared` and `item_state.tape_spent` keep their
  names and now say that the leg's first scrape, and the act's first
  fault, is behind him, with or without the charm or the tape aboard.
- **What a stop ends is said before it is rebuilt** (`_save_point`,
  `_announce_what_ends`): `effect_expired` for every status that is on
  except those the leg holds to its end; what the tape or the radio holds
  on (`music`, `news`) ends there too and is announced again on the first
  tick after he leaves. Statuses are reported a second time each tick,
  after leg progress, so that what the gore ends is said in its tick; a
  Snap that a missed Exit brings is announced as well (it used to reset
  his Nerves and block his hand without a word).
- **Requirements at completion.** `ItemSim.complete()` asks them again and
  says whether the ritual ran; `ritual_completed` and the ritual's sound
  follow only if it did. The gesture is not cancelled when its ritual
  stops being possible: the hand's time is spent and nothing happens. (A
  TAP on his pocket that ends after the Call has rung out therefore takes
  nothing and Noor says nothing.)
- **The same place** is the same place under the pointer: an anchor whose
  pointer position equals that of an anchor the carried thing may be put
  down on is switched off while the carry lasts. Today only `radio` and
  `tape` coincide; with the rule above the dial is not in use at a stop
  anyway, so this matters only for a tape carried on the road.
- **A gust** is a countdown in the road's seconds: 120 ticks without
  Focus, 141 with it, the car carried `gust_push` times `gust_duration`
  either way.
- **Drips** (a resource entry with `over`) are kept as 64-bit seconds: a
  cigarette's calm falls on exactly its 3,000 ticks, the tick it is lit
  included. The order of statuses within a tick is unchanged: what reads a
  timed status in step 9 sees it for one tick less than its number.
- **Left as it is, seen on the way:** a stop reorders the cabin's list
  (items before Adaptations), which only tests that compare the order
  see; the weather cramp's hum runs on while he is pulled over (it is the
  hand's, like a Snap); the indicator's, the craving's and the horn's
  countdowns are bare countdowns that land on their tick with today's
  numbers.

## D-056 (M10, 2026-11-20) What of M10 is built now, and what waits for the frame

- **Context.** While M8 was being built the owner said: "Finish m6, m7, m8,
  and m10 then pause for now". M9 is not on that list, and GDD 18 says not
  to start a milestone before the tests of the one before it pass. Three
  pieces of M10 had been built ahead of their milestone by workflows,
  while the main line was on M6 to M8, under the rule that they touch
  nothing in `src/core`; they lay parked in `wip/`.
- **Reading.** "Finish" means the work that was in flight on those four:
  the review fixes of M6, the review of M7 and its fixes, M8 with its
  review, and of M10 the three presentation pieces, taken in, reviewed and
  merged (D-052 to D-054). M9 is not started.
- **What of M10 waits for M9.** The eleven settings of GDD 17.1 and their
  effects, the mouse-only menus, and the three tests. T-SMOKE-ALL starts
  the title, the wedding room and the drive scene in each of its kinds;
  T-ONEHAND-01 walks every menu; T-SETTINGS-01 changes a setting
  mid-Telling through them. None of these scenes exists before M9. Only
  the settings store and the two Subtitles keys exist. Building the
  settings without the menus that change them would be a second milestone
  begun ahead of its turn, and the owner asked for a pause.
- **The three tests of M10 stay registered as failing** until then.

## D-057 (M7 review, 2026-11-20) Rulings on the findings of the bosses' review

The review `m7-review` read commit 2940233 through five lenses (the
Checkpoint, the Storm, Dawn, the tests, the views), each finding with a
probe. This entry is what was decided and built for the first four; where
it changes D-046 to D-050, this is the later word. Every fix came with a
check that failed before it.

**The Checkpoint (amends D-048)**
- *Which rows of Suspicion are its own.* Crossing a lane line without
  indicating is the Patrol's row: before the barriers he may choose his
  queue for nothing. A Snap is charged wherever the law watches (GDD 6.1
  says "Suspicion +30" of the Snap itself): +30 at the Checkpoint too.
- *Using contraband* (GDD 6.5, +40 in a Patrol's view) is a ritual that
  gives the item's effect. Putting it away in the glovebox, or taking it
  out, is none.
- *A car that stands touches nothing.* Held at the bar (or for the Call) the
  car is not stepped, so what it brushed in its last moving tick stayed
  "touched" and was counted again every 0.8 s, to a Wreck.
- *Forged papers* pass the Papers of the visit that gets him through. At
  the top of Suspicion as the soldier arrives he is turned back as he
  comes and they stay in the cabin. The shady guy holds them out only
  while the Checkpoint is ahead: an item may name the boss it is for
  (`until_boss`).
- *The soldier is of the road.* Focus (GDD 7.4) slows his walk and his
  patience with the queue: 11.8 s to stow, 5.9 s a delay, of the hand's
  time. (Noor's ring stays on the cabin's time, D-047.)
- *Under its eyes no empty road calms him* (GDD 6.1: "and no encounter"),
  until he is let through.
- *The queue is served once he has come to the barriers.* Standing short
  of them there is nothing to wait out; phase 1 is his to drive.
- *Stop and go needs the brake.* On the open road one contact is one hit
  and he is held behind what he touched (D-023, D-029); in the queue that
  carried him to the bar for one lamp. A queue vehicle he keeps pushing is
  touched anew each time the last touch has worn off.
- *The sign* stands 2 s short of the taper (it stood 1 m into the road).
- *Whoever is waved on* drives to the road's end (each lane kept one, and
  took the one before off the road in front of him).
- *What a search takes is taken out of his hand*: a gesture on a thing that
  has left the cabin is over.
- *Concrete between the lanes*: `TrafficSim.walled` is the stretch where
  nobody changes lane, whatever honks (the Loud horn at the Checkpoint,
  any horn between Dawn's barriers).
- *Suspicion's light* (GDD 16.3) shows in the mirror wherever he is
  watched; D-050 kept it dark at the Checkpoint, where nothing else told
  him where he stood between 0 and 100. The siren's chirps were already
  heard there (D-052).
- *Each verdict is said*: `soldier.pass`, `.search`, `.turned_back`,
  `.bribe`, at the Checkpoint and at Dawn's barriers.

**The Storm (amends D-046)**
- *Standing* begins a wait when he stands (`stopped_kmh`) and it ends when
  he has driven off (`moved_off_kmh`, 15) or made himself safe. A twitch
  of the pedal neither begins the 10 s anew nor makes a hit miss. The horn
  behind him sounds 2 s ahead (it was 1): time to reach 15 km/h from rest;
  the validator holds the record to that.
- *The safe place is safe for his Nerves too.* The shoulder frays him only
  while the car moves (GDD 5.1: "drivable, +1 Nerves per second").
- *Its lights in his mirror are a mirror tell* (GDD 7.6, 6.3): shown
  `rear_end_tell_s` before the hit, 5 s earlier in the Wide mirror and not
  before the hit in a cracked one (`rear_end_lights_in`). The horn keeps
  its time.
- *Tail lights leave a way past at any pace.* Each is put on the road only
  where no other is nearer than the least gap (`apart_m`), and none is
  faster than one ahead of it. A driver who followed them at their own
  speed, as GDD 10.3 tells him to, used to get three abreast.
- *A Telling told again* has a seed of its own: `RETELLING_SALT` was the
  bosses' salt.
- *Night storm* still changes nothing a driver with two headlights can
  measure (the dust is always nearer than the cone, as D-046 has it):
  NEEDS OWNER.

**Dawn, the Call, the Arrival (amends D-047)**
- *The 70 holds between the barriers*, not only at their mouth: searched,
  once, on the first tick above it from the mouth to the corridors' end.
- *Nothing wider than the barriers is on Dawn's road.* A road may say the
  widest vehicle it lets through; the generator leaves wider types out
  and gives a beat that names one the widest that fits.
- *The end of the talk has a tell*, 1.5 s ahead: her last words
  (`noor.call.bye`) and the phone's two notes. When the phone is put away
  the pointer is on the wheel again, so his hand comes back to it. A car
  that stood for the call stands until his hand has the wheel.
- *The phone on its mount* keeps its own picture while Noor's rings
  (`mount_caller`, `mount_ring_left`).
- *The key parks the car*: the engine is off (`engine_on` in the snapshot),
  the car and the Clock stand.
- **Not built, known debt:** after the last checkpoint Dawn's traffic is
  laid out for a driver at par, and the checkpoint makes every driver
  slower than par: in about one Dawn in five a driver who took the
  barriers in second gear meets vehicles across all three lanes during
  the Call, and must brake behind them. The cure is in the generator
  (nothing met after the barriers is on the road before he leaves them,
  or a par frame that includes the slow passage) and belongs with
  T-WALL-01 in M11. Without trucks on that road it is rarer than the
  review measured. Also not built: a car across a lane line at the
  taper's mouth is pushed up to 1.4 m sideways in one tick (it should
  meet the barrier's head).

**The tests**
- The lens's 34 appended checks are in T-BOSS-01 to 03 and T-CALL-01 as
  it wrote them. Four loops got guards. T-DATA-01 has the failure cases of
  every boss rule. Where a rule changed, a step of an existing check was
  corrected and its assertion kept: the queue's watcher stands at the
  mouth of the barriers; the hazard-lights remedy keeps his foot on the
  brake; after the Call the car moves off once he has the wheel.
- Literals that stand beside a check pinning the data to the GDD's number
  stay: changing such a number is a recorded decision anyway.

## D-058 (M7 and M8 reviews, 2026-11-20) A sound for every tell; a tell is read at once

GDD 17.2: "Every tell has both a sound and a visual." D-052 left six kinds
of tell without a sound, because the table of GDD 16.5 has no row for them
and GDD 1.5 forbids "a system, resource or screen that this document does
not name". Two reviews (the views lens of M7, V-03; the tests-and-views
lens of M8, m8tv-04, verified) found the rule broken. They are right, and
this is the later word:

- **The reading.** "Resource" in GDD 1.5 is what section 6 is called: the
  meters and the money of the game. A placeholder sound is none. The table
  of GDD 16.5 lists the sounds the document names; GDD 17.2 binds every
  tell. Where a tell has no row, GDD 1.5 rule 3 decides: pillar 4 is the
  tell, and the simplest thing that serves it is one more record in
  `data/sfx.json`, which the generator already turns into a sound. `rattle`
  and `horn_behind` (D-052) were added by the same reasoning.
- **What counts as a tell here:** what announces, a moment ahead, something
  he must answer at the wheel or with the hand (pillar 4), and what the GDD
  itself says is heard ("prays aloud", "his snoring").

| Tell | Seen | Heard |
|---|---|---|
| A gust (GDD 5.4, 10.3), on any road | Streaks, 1 s ahead | `gust`: wind that swells for as long as the streaks blow |
| The Storm's thick dust | The dust closes in over the last `dust_tell_s` (1 s) of thin dust | `dust`: a low roar from the closing until it thins |
| The soldier sets off (the Stow) | His walk | `soldier_whistle`, once |
| A sign goes up (each document) | The sign; his line if the window is shut | `soldier_knock`, once a sign |
| What comes up behind him | Its lights in the mirror (D-057) | `horn_behind` (D-052) |
| The Call | The lit phone, the ring written out (D-050) | `phone_ring` |
| The end of the talk | Her last words (D-057) | The phone's two notes |

- **The dust's tell.** D-046 called the dust's fixed rhythm its own tell;
  nothing on screen or in the ear said that a change was a second away.
  The rule does not move: he sees 40 m to the last tick of thin dust and
  15 m from the next (T-BOSS-02 holds that to the tick). What the views
  fade the road at is a number of its own, `sight_shown`, which falls from
  the one to the other through the tell (`dust_closing`, 0 to 1); the sky's
  fog and the gust's streaks follow it. When it thins he is shown the
  whole 40 m at once: relief needs no tell. The validator holds
  `dust_tell_s` to no longer than the dust is thin.
- **Not given a sound**, and why: the low sun (the GDD's own tell is "the
  light source is visible first"; nothing a sun does is heard), the bar (a
  verdict, which is said in a line and seen), the bay and the key (nothing
  is announced ahead), a hitcher at the roadside.
- **The mix.** One soldier does one thing at a time: `soldier_` is a
  family in the check, like the radio's loops. With the new sounds the
  ducks are 1 dB deeper (rumble strip -16, indicator -14.5, the yawns -14)
  and each cue stands 6.9 to 7.3 dB clear of everything else at once.
- **A tell is read at once.** A line that announces something a moment
  ahead must not wait its turn behind what is being said (the queue of
  D-054 holds a line 1.5 s at least). `line_requested` may carry
  `"tell": true`: the subtitle takes the screen in that frame, and what it
  took the screen from is shown again after it, with its whole time. The
  simulation marks the ring written out and Noor's last words. The
  heckles of M9 ("the subtitle appears 2 s before anything changes. That
  lead is the tell", GDD 11.3) are to be asked for the same way.
- **Whose turn the rest is.** The tells of the earlier milestones were not
  gone through for GDD 17.2 (a curve's sign has no sound; the yawns and
  the Phantom's hum have no picture): that belongs to the rest of M10
  (settings and accessibility, D-056).
- **NEEDS OWNER:** nobody has heard these sounds either (D-052).
