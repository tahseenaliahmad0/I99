# Part I. Orientation

## 1. Builder brief (read this first)

You are the sole engineer on Single-Handed. Your job is to build the whole game described in Parts I to III, with placeholder art and audio, so that a human can play it from first launch to the final scene.

### 1.1 Definition of done

- A player can launch the game, play the prologue, play a Telling at each of the seven Tables to any of its endings, and play the finale.
- Every system in Part II works as specified, and every content row in Part II exists as data.
- The whole game, menus included, is playable with a mouse alone: motion, left button, right button.
- `tools/check.sh` passes: scripts parse, data validates, all tests in `tests/tests.json` pass, every scene loads headless.
- An artist can replace any placeholder by editing a registry file, with no code change.

### 1.2 Out of scope

Do not build these. If a task seems to need one, stop and re-read the spec.

- Final art, final audio, voice-over, licensed music.
- Arabic dialogue. Write short English placeholder lines only, each with an id and `needs_writer: true`. An Iraqi writer replaces them later.
- Store integration, analytics, achievements, multiplayer.
- Any currency, item or stat that carries between runs.
- Third-party addons, C#, GDExtension.
- Engine physics for gameplay. Cars, hands and collisions are plain arithmetic (section 5).

### 1.3 Hard constraints

| Area | Constraint |
|---|---|
| Engine | Godot 4.7.x stable, GDScript with static typing everywhere |
| Simulation | All gameplay lives in pure classes (no Node) stepped at a fixed 120 Hz. Views read snapshots and never change state. |
| Randomness | Only from seeded streams owned by the simulation. Same seed and same inputs give the same run. |
| Data | Every number and every content record lives in `res://data/*.json`. No tuning literals in code. |
| Text | Every player-facing string goes through the line database by id. |
| Interface | No conventional HUD. State is shown by cabin objects, post effects and sound. A numeric HUD exists as a setting. |
| Placeholders | Primitives, flat colours, generated tones (section 16). |
| Performance | 60 fps at 1080p on an integrated GPU |

### 1.4 How to work

This build will span many context windows, so keep state in files, not in memory.

1. **Start of every session.** Run `pwd`. Read `docs/PROGRESS.md`, `docs/DECISIONS.md`, `tests/tests.json` and `git log --oneline -20`. Run `tools/check.sh`. Then take the first unfinished step of the current milestone (section 18).
2. **First session is M0 only.** Create the project, the test runner, the data validator, `tools/check.sh` and the three docs files. Register every test id from section 18 in `tests/tests.json` as `failing`. Commit.
3. **Work in vertical slices.** Implement one behaviour, write or enable its test, run the checks, commit with a descriptive message, add two lines to `PROGRESS.md`.
4. **Tests are append-only.** Never delete, skip or loosen a test to make it pass. If a test encodes a number you believe is wrong, change the value in `tuning.json`, keep the test reading from tuning, and record why in `DECISIONS.md`.
5. **Done means run.** A feature is done when a headless simulation test covers it and the scene that shows it loads without errors. If a display is available, also save a screenshot to `artifacts/`.
6. **Check the engine, not your memory.** Run `godot --version`, then `godot --doctool docs_api` once and search that XML before using any class or method you are unsure of. Prefer APIs that have existed since 4.3.
7. **Do not wait for answers.** When the spec is silent, apply section 1.5, write the decision in `DECISIONS.md`, and continue. Mark anything a human must judge as `NEEDS OWNER` in `PROGRESS.md`.
8. **Leave the repository clean.** End each session with passing checks and no uncommitted work.

### 1.5 When the spec is silent or contradicts itself

1. Section 15 (tuning values) overrides numbers quoted elsewhere.
2. Part III overrides Part II on how something is built. Part II overrides Part I on what the rules are.
3. If still unclear, choose the option that best serves the pillars in section 2.2, and among those the simplest to build.
4. Never add a system, resource or screen that this document does not name.

### 1.6 Vocabulary

These terms are used exactly. Use the same words in code identifiers.

| Term | Meaning |
|---|---|
| Telling | One run: one attempt at the night, told to one Table |
| Table | An audience at the wedding. Each Table is a ruleset. |
| Heckle | A guest's interjection that changes the road or sets a challenge |
| Act, Leg, Boss | A Telling is 3 acts. An act is 3 legs and a boss. A leg is 2.5 km. |
| Beat | A 4 to 8 second unit of road inside a leg |
| Fork, Exit, Stop | A road split chosen by steering; a slip lane; the stall it leads to |
| Anchor | A named 3D point in the cabin the hand can travel to |
| Reach | The hand's travel to an anchor. Grip and let go refer to the wheel. |
| Ritual, Gesture | What the hand does at an anchor; the input pattern that performs it |
| Nerves | One meter, 0 to 100. High is Frayed, low is Heavy. |
| Awake | A timed status that suppresses Heavy effects |
| Lamp, Fault | A dashboard warning lamp; the specific breakage it stands for |
| Suspicion | A 0 to 100 meter that exists only during police encounters |
| Passenger, Hand, Weight | A person in the seat; what they do for him; what they cost |

## 2. The game in one page

### 2.1 Premise and targets

Abu Noor drives a taxi in Baghdad and has one arm. His daughter marries in Basra tomorrow, and he told everyone he would not come. At ten at night he gets in the car. He steers, shifts, smokes, drinks tea and answers the phone with the same hand, so the wheel is unheld whenever he does anything else.

The night is told afterwards. At the wedding party he goes from table to table telling how he got there, and each run is one telling.

| Item | Target |
|---|---|
| Genre | Real-time roguelike, first-person driving |
| Telling length | 18 to 22 minutes: 9 legs of 60 to 110 s, 3 bosses of 90 to 120 s |
| Retry time | 3 s from wreck to wheel |
| Platform | PC with a mouse first; touch second |
| Tone | Dry comedy; slapstick violence; nothing explained |
| Win condition | Park at the house in Basra before 06:00 |
| Carried between Tellings | Tables, modes and wedding guests. Never power. |

### 2.2 Pillars

1. **One hand, everything.** Every action competes for the same hand. No action is free.
2. **Skill first, build second.** An expert can win the Drivers' Table with the starting cabin. Items change how he drives, not whether he can.
3. **Everything that helps also costs.** Habits take the hand. Calm makes him sleepy. A passenger takes the seat.
4. **Never random at the wheel.** Chance lives in the road and the stalls. Every hazard, impairment and heckle has a tell at least 1 s ahead.
5. **The car should fit him, and mostly does not.** Everything on his left costs more. Adaptations change the car, never the man.
6. **One hand doesn't clap.** The strongest help in the game is another person. Accepting it costs space, quiet and pride.
7. **Subtext over speech.** Meaning sits in objects, controls and repetition. Nobody explains.

### 2.3 Core loop

Steer until the road lets you let go, then let go for something worth it. Two pressures pull against each other: traffic and the law fray his Nerves, and empty road at night makes his eyes heavy. Almost every tool that fixes one side feeds the other, and all of them cost time with the hand off the wheel.

### 2.4 One minute of play

It is 01:40 on a Rain leg in Act 2. The road has been empty for a while and his eyes are heavy: dark bars creep in from the top and bottom of the screen. He hears himself yawn, which means a blink is one second away, so he straightens the car first.

He lets go, slaps his own face and takes the wheel again. The slap woke him and frayed him, and the wheel starts to shake. The wipers need a flick every six seconds, the cigarette is nearly out, and an uncle at the table says: "All night? At your age? I don't believe it."

A doubt costs Nerves unless he answers it with driving. A truck is merging ahead. He drops to third through the gate, threads the gap with half a metre to spare, and the table goes quiet. Blue lights fill the mirror.

### 2.5 The loop at each timescale

| Timescale | Lasts | The player does | The player decides |
|---|---|---|---|
| Moment | 1 to 5 s | Steers, lets go, reaches, grips again | Is this stretch safe enough to let go? |
| Leg | 60 to 110 s | Drives one road type with one rule | Which gear, which habits, whether to pull over |
| Stop | Untimed | Takes one service with the hand | Calm, repair, power or a passenger, at a price in minutes |
| Act | About 6 min | 3 legs and a boss | Which road at each fork |
| Telling | 18 to 22 min | 3 acts and an arrival | What kind of driver this cabin has made |
| Between Tellings | Seconds | Walks to a Table | Which audience, so which rules |

## 3. Story, frame and meaning

The story is never told to the player. Implement the facts below as objects and behaviour, not as text.

### 3.1 Canon

| Detail | Value |
|---|---|
| Name | Abu Noor, "father of Noor". No other name is ever used. |
| Age, home, work | Mid-forties. Baghdad. A taxi by day, anything by night. |
| Injury | He lost his left arm above the elbow in a US air strike about 22 years ago. Never dated, shown or discussed. |
| Car | A boxy 1980s four-speed saloon, older than his daughter, unbranded. Left-hand drive. |
| Noor | His daughter, 22. She was a newborn when it happened. |
| The wedding | In Basra, tomorrow. The women of the family went down three days ago. The groom's family comes for her in the morning. |
| Why he is driving | He said he would not attend. By an old custom a bride's father stays away. At 22:00 he changes his mind. Nobody knows he is coming. |
| The deadline | He drove nights all her childhood and was always home when she woke. 06:00 is before she wakes. |
| Tonight's cabin | A photo on the visor, a prosthetic hook he does not wear on the passenger seat, a folded letter in the glovebox |
| Character | Funny, stubborn, proud, very good at driving |

### 3.2 The frame

- The wedding party is the menu. It is a room of Tables. Walking the pointer to a Table and sitting starts a Telling under that Table's rules (section 11).
- During a Telling, guests heckle in subtitles. A heckle is always followed by a change on the road or a challenge.
- On a Wreck the screen cuts to black one frame before impact. A guest objects, he answers "No. That is not how it went", and the Telling restarts from Baghdad within 3 s.
- Variety between Tellings is his embellishment. The last Table is Noor's. For her the road is fixed, the cabin holds only what was really there, and nobody heckles.
- A proverb runs under everything: "one hand doesn't clap". His answer, heard once at the very end, is "No. But it drives."

### 3.3 Two bookends

| Bookend | When | What the player does | What it means |
|---|---|---|---|
| Prologue, "Two Hands" | First launch, 75 s | Drives home at dawn 22 years ago. A left hand holds the wheel by itself, so reaching for things costs nothing. | The player learns the cabin, then loses the second hand without a word |
| Finale, "One Hand" | After the true ending at Noor's Table | Claps against Noor's raised palm, takes her hand, and ends the game by letting go | The verb that was dangerous all night is the gift |

Section 10 specifies both.

### 3.4 Tone rules

1. The joke is never the arm, his faith or his nationality. The jokes are the car, the queue, the paperwork, prices, sheep and his own stubbornness.
2. Violence is slapstick: bumpers, cones, watermelons. Never bodies. A wreck cuts away before impact.
3. He is competent. Nothing presents him as helpless, cured or inspiring.
4. Nobody explains. No cutscene of the strike, no speech, no text about the war.
5. The war is furniture: rusted hulks used as landmarks, blast walls carrying adverts.
6. The narrator is dry and warm, never goading.

### 3.5 Subtext the build must preserve

Each row is a rule of play. Do not simplify any of them away.

| Rule in the build | What it says without saying it |
|---|---|
| Hand speed is 70% left of the wheel hub; the indicator, lights and window are all there | Following the rules costs him more than it costs anyone else |
| Vendors come to the passenger window, his good side. Police and soldiers come to the driver's window. | Commerce meets him where he is. Authority does not. |
| The checkpoint needs the window wound down: a cross-reach and three turns | Compliance was designed for two hands |
| The hook sits on the seat and does nothing until a mechanic fits a ring to the wheel | The help he was given fits the car better than it fits him |
| Adaptations are cheap, and nobody offers them. He has to find a fitter. | The fix existed all along |
| The letter in the glovebox lies on top of the car registration and must be moved aside every time | An arm has a price, and somebody else set it |
| The visor photo shows a man with two arms holding a newborn. Flipping the visor against the sun shows it. | The before, never mentioned |
| The news station frays his Nerves and is the only source of warnings | Knowing what is coming costs him |
| A black motorcade may not be passed and answers only with a spotlight | Some things on this road are waited out |
| The orange glow on the horizon in Act 3 is burning gas, not the sun | A false dawn before the real one |
| He cannot hold the phone and the wheel. A passenger can hold the phone. | One hand doesn't clap |

### 3.6 Placeholder lines

Write about 250 placeholder lines in this voice. Keep them under 60 characters where possible.

| Line id | Speaker | Text |
|---|---|---|
| `narrator.start` | Abu Noor | So. Ten at night, and I was still in Baghdad. |
| `wreck.drivers.1` | Guest, then Abu Noor | And then you died? / No. That is not how it went. |
| `wreck.children.1` | Child, then Abu Noor | Then how are you HERE? / ...Good question. Again. |
| `heckle.children.twist.sheep` | Child | And then there were SHEEP! |
| `heckle.drivers.dare.gear4` | Driver | Fourth gear! Tell them about fourth gear! |
| `heckle.uncles.doubt.1` | Uncle | All night? At your age? In that car? |
| `heckle.aunts.order.tea` | Aunt | Drink your tea before it goes cold. |
| `passenger.hajjiya.board` | Old woman | God keep you, my son. Not so fast. |
| `radio.news.patrol` | Newsreader | Traffic police are out on the southern road tonight. |
| `noor.call.1` | Noor | Baba? Are you awake? |
| `finale.proverb` | Noor, then Abu Noor | They say one hand doesn't clap. / No. But it drives. |

---

# Part II. Rules of play

## 4. Controls and the Hand

The player controls one hand and one foot. The hand is a physical object that takes time to move. The foot is a single brake input.

### 4.1 Inputs

| Action | Mouse | Touch |
|---|---|---|
| Move the hand | Move the mouse. A virtual pointer moves; the hand follows it. | Tap or drag with the right thumb |
| Grip the wheel | Hold the left button with the pointer on the wheel | Hold the thumb on the wheel |
| Steer | Move left and right while gripping | Drag left and right |
| Let go | Release the left button | Lift the thumb |
| Use an object | Point at it, then press, hold or drag as its gesture defines | Tap, hold or drag on it |
| Brake | Hold the right button, or Space | Hold a second thumb on the pedal zone, bottom left |
| Pause | Esc, or click the hotspot in the top-left corner | Tap the hotspot |

The mouse is captured. The game keeps its own pointer position from relative motion.

### 4.2 The pointer and the hand

- The pointer is a 2D position on screen. It snaps to the nearest anchor within 60 px. With no anchor in range, the hand's target is the point under the pointer on a plane 0.45 m in front of the eye.
- The hand moves toward its target at 1.5 m/s with no easing. Travel time is distance divided by speed.
- **Left-side rule.** Left of the wheel hub (cabin x below 0) the hand moves at 70% speed and must route through waypoint W above the wheel. This makes every left-side control a slow cross-reach.
- At Nerves 80 or more, hand speed is multiplied by 0.85.
- **Buffering.** A press made up to 0.30 s before the hand arrives is applied on arrival. Holding the left button with the pointer on the wheel makes the hand fly there and grip.
- Only one thing fits in the hand. Holding beads or a phone means not holding the wheel.

### 4.3 The wheel

- The wheel angle runs from -135 to +135 degrees.
- The grip zone is the rim: radius 0.19 m, plus or minus 0.045 m. The hand grips the nearest rim point and then turns with the wheel.
- While gripped, horizontal mouse motion turns the wheel at 0.35 degrees per pixel at 1080p, scaled by window height and the sensitivity setting. The pointer is hidden and pinned to the hand.
- The wheel follows the commanded angle with 60 ms of smoothing.
- On release the wheel returns to centre at 200 degrees per second, and the car moves sideways only by drift.
- Gripping never snaps the wheel. The player takes it at whatever angle it has.

### 4.4 Gestures

Each ritual is built from these primitives. Perform times in later tables are what a practised player achieves.

| Gesture | Input | Notes |
|---|---|---|
| TAP | Press and release within 0.25 s | Completes on release |
| HOLD(t) | Keep the button down for t seconds | Releasing early cancels with no effect |
| FLICK(dir) | Press, then move at least 40 px in the direction within 0.25 s | Up, down, left or right |
| DRAG_TO(anchor) | Press on the object, carry it to another anchor, release | The carried object moves at hand speed |
| CRANK(n) | Press, then circle the pointer for n full turns in one direction | Counts cumulative angle |
| BEAD | Repeated TAPs | Each tap is one bead, at most 3 per second |
| GATE | Gear lever only | Section 4.5 |

### 4.5 The gear gate

The gearbox is a four-speed H pattern, shifted by dragging the lever through its gate. It replaces v1's flick shifting.

```
 1     3     5
 |     |     |
 +--N--+-----+
 |     |
 2     4
```

- Lever coordinates: neutral is (0, 0). Gear 1 is (-1, +1), 2 is (-1, -1), 3 is (0, +1), 4 is (0, -1), 5 is (+1, +1). One unit is 40 px of pointer travel. Gear 5 is walled off unless the Fifth gear adaptation is fitted.
- The lever moves only along the channels: the horizontal neutral channel and the vertical channels. Channel half-width is 0.25 units.
- Press on the knob to hold the lever, drag, release. If the lever is within 0.2 units of a gear position on release, that gear engages. Otherwise it springs back to neutral.
- A grind happens when the player releases between 0.3 and 0.8 units along a vertical channel, or pushes more than 1 unit into a wall. A grind makes a noise, adds 2 Nerves and locks the lever for 0.2 s.
- There is no clutch input and no throttle. In neutral the car coasts down at 6 km/h per second.
- An assist setting replaces the gate with FLICK up and FLICK down.

### 4.6 Controls always in the car

| Control | Anchor | Reach from the wheel | Gesture | Effect |
|---|---|---|---|---|
| Horn | `horn` | 0.13 s | TAP | Cars and taxis within 40 m ahead in his lane move over within 1 s if the next lane is free. Trucks and buses ignore it. -3 Nerves, at most once per 10 s. |
| Wipers | `wiper_stalk` | 0.10 s | FLICK up | One sweep. Rain stays clear for 6 s. |
| Hazard lights | `hazard_button` | 0.16 s | TAP | Toggle. Needed to stop safely on the shoulder. |
| Radio | `radio` | 0.21 s | DRAG the dial | Section 6.2 lists station effects. The signal drifts to static every 40 s and must be retuned. |
| Gear lever | `gear_lever` | 0.23 s | GATE | Section 4.5 |
| Visor photo | `visor` | 0.32 s | FLICK down | -20 Nerves, once per leg. The visor stays down 3 s and blocks sun glare and the top 15% of the view. |
| His own face | `face` | 0.26 s | TAP | A slap. +12 Nerves, Awake for 20 s. |
| Passenger | `passenger_shoulder` | 0.53 s | TAP | Asks the passenger for their Hand (section 8) |
| Glovebox | `glovebox` | 0.57 s | TAP | Opens or closes. Holds 2 stowed items and the papers. |
| Indicator | `indicator_stalk` | 0.41 s, cross | FLICK up for right, down for left | Signals for 5 s or until a lane line is crossed |
| Headlights | `headlight_knob` | 0.53 s, cross | TAP | Toggles high beam: night view cone 100 m instead of 60 m. Each oncoming vehicle met on high beam adds 2 Nerves. |
| Window | `window_crank` | 0.70 s, cross | CRANK(3) | Opens or closes. Opening gives Awake for 30 s. While open: Haze clears 3 times faster, radio effects are halved, dust comes in. |

Time off the wheel for any action is reach, plus perform, plus reach back. A gear shift is about 0.65 s. Lighting a cigarette is about 1.6 s.

### 4.7 The eyes

- The camera sits at the driver's eye and looks forward.
- **Glance.** The eyes partly follow the hand. When the hand is more than 25 degrees off the forward axis, the camera turns toward it by 60% of the excess, up to 35 degrees of yaw and 25 degrees of downward pitch, smoothed over 150 ms. Far reaches cost road view.
- **Eyes-down rituals** (phone, papers, glovebox contents) force the pitch to -35 degrees while performed. The road shrinks to the top 35% of the screen.
- The rear-view mirror is always visible. Police and tailgaters appear there first.

### 4.8 The foot

- Holding the brake sheds 30 km/h per second, down to a stop.
- Releasing it lets the car climb back to the current gear's cruise speed at 12 km/h per second.
- After a downshift, the car slows to the new cruise speed at 20 km/h per second.

### 4.9 The finickiness dials

Five values set how fiddly the game feels: wheel smoothing, grip zone width, hand speed, gate channel width and anchor snap radius. Ship the generous values in section 15. Expose all five in the debug tuning panel.

## 5. Driving model

The road is simulated in lane space. The car has a position across the road (x, metres) and a distance along the leg (s, metres). Nothing else is simulated.

### 5.1 Road

- Lanes are 3.5 m wide. The car is 1.8 m wide and 4.4 m long. Centred in a lane it has 0.85 m of margin each side.
- Our carriageway occupies x from 0 to 3.5 times the lane count. Lane i (0 is the leftmost) is centred at 3.5 i + 1.75.
- **Right side.** A rumble strip 0.5 m wide (sound only; it also ends a Nod), then a rough shoulder 2.5 m wide (drivable, +1 Nerves per second, speed capped at 70), then a guardrail.
- **Left side.** On divided roads, a median barrier at x = -0.5. On undivided roads, the oncoming lane from x = -3.5 to 0.
- Touching a guardrail or barrier is a scrape, and the car is pushed 0.5 m back.
- A leg is 2,500 m with 1 to 3 lanes.

### 5.2 Speed

| Gear | Cruise (km/h) | Max sideways speed at full lock (m/s) | Close-call cash | Time for 2.5 km (s) |
|---|---|---|---|---|
| 1 | 40 | 2.0 | x0 | 225 |
| 2 | 70 | 3.5 | x0.5 | 129 |
| 3 | 100, the legal limit | 5.0 | x1 | 90 |
| 4 | 130 | 6.5 | x2 | 69 |
| 5, needs Fifth gear | 160 | 8.0 | x3 | 56 |

Third gear is par. Fourth saves 21 s a leg and doubles close-call cash, and it cuts reaction time by about a quarter.

### 5.3 Sideways motion

```
steer         = wheel_angle / 135                     # -1 to 1
v_lat_command = steer * 0.05 * speed_kmh              # m/s
v_lat         = follow(v_lat_command, tau = 0.12 s)   # car inertia
x            += (v_lat + sum_of_drifts) * dt
```

The wheel angle that feeds this formula includes Tremor and is delayed by Lag (section 5.8).

### 5.4 Drift

Drift moves the car when nobody is steering. All drift is constant or announced.

| Source | Sideways push | Tell |
|---|---|---|
| Road crown | 0.25 m/s toward the right shoulder, always | None needed |
| Curve | k times (speed / 100) squared, outward, capped at 2.0 m/s; k is 0.5, 1.0 or 1.5 | A sign 3 s ahead, then the visible bend |
| Gust | 1.5 m/s for 1 s | Dust or a flag moving 1 s ahead |
| Pulling steering (fault) | 0.4 m/s to the left | Constant once it happens |
| Sway (arak) | 0.3 m/s per Courage stack, swinging at 0.4 Hz | The horizon rocks |

From the centre of a lane on a straight in third gear, the car edge reaches the lane line after 3.4 s hands-off. This number sets the feel of the game and has its own test.

### 5.5 Traffic

- Vehicles hold a lane at a set speed. Every lane change is scheduled by the beat that spawned the vehicle, or caused by the horn.
- A lane change is signalled for 1 s and takes 2 s. From Act 2, late signallers signal for 0.4 s.
- Vehicles spawn 300 m ahead (oncoming: 400 m) and are removed 100 m behind.

| Type | Size (m, width by length) | Speed (km/h) | Notes |
|---|---|---|---|
| Car | 1.8 by 4.4 | 90 to 110 | Yields to the horn |
| Taxi | 1.8 by 4.4 | 100 to 120 | Yields; honks when passed closely (+5 Nerves) |
| Pickup | 1.9 by 5.0 | 80 to 100 | |
| Minibus | 2.1 by 6.0 | 80 to 90 | Ignores the base horn |
| Truck | 2.5 by 12 | 60 to 70 | Ignores the base horn |
| Tanker | 2.5 by 14 | 60 | Ignores the base horn |
| Tuk-tuk | 1.3 by 2.6 | 40 | Act 1 only |

### 5.6 Collisions

Collision is overlap of two rectangles in (s, x). The class depends on closing speed.

| Hit | Trigger | Lamps lit | Nerves | Also |
|---|---|---|---|---|
| Scrape | Guardrail, barrier, or a vehicle at 30 km/h closing speed or less | 1 | +10 | Speed drops 20% |
| Crash | A vehicle at over 30 and up to 80 km/h | 2 | +20 | Forced into first gear |
| Head-on | Any oncoming vehicle, or over 80 km/h | 3 | +30 | Forced into first gear |

After a hit the car is pushed 0.5 m clear and cannot be hit again for 0.8 s. Cones and melons light no lamp: each adds 3 Nerves, plus 10 Suspicion during a Patrol.

### 5.7 Close calls

- A close call is passing a vehicle or hazard with under 0.6 m of sideways gap and at least 30 km/h of closing speed, without contact. It is judged when the two stop overlapping along the road.
- It pays 2 cash, times the gear multiplier, times the chain. Each close call within 4 s of the last adds 25% to the chain, up to x3. Oncoming close calls pay double.
- Each close call adds 2 Nerves. Skill earns money and frays him.

### 5.8 Impairments

Every impairment is a fixed, learnable change. None adds random noise.

| Impairment | Cause | Effect | Tell |
|---|---|---|---|
| Tremor | Nerves 45 or more | The gripped wheel oscillates at 3 Hz. Amplitude grows from 0 to 12 degrees at Nerves 100. | The hand shakes |
| Tunnel | Nerves 60 or more | The view narrows to 70% at Nerves 100 | Dark edges |
| Pound | Nerves 80 or more | Hand speed x0.85 | Heartbeat audio |
| Lids | Nerves below the Heavy floor, not Awake | Dark bars close from top and bottom to 25% each over 3 s | The bars |
| Blink | Same | Eyes shut for 0.3 s every 6 s | A yawn 1 s before |
| Nod | Nerves 15 or more below the floor, not Awake | Eyes shut for 1.5 s every 10 s. The rumble strip or any hit ends it and adds 15 Nerves. | A long yawn 1.5 s before |
| Haze | Cigarette smoke, dust | The windscreen clouds, up to 60% | Visible smoke |
| Sway | Courage stacks | Section 5.4 | The horizon rocks |
| Lag | Arak, the good stuff | Steering delayed 40 ms per source, capped at 200 ms | The hand trails the wheel |
| Glare | Low sun, high beams, the spotlight | A bright wash over part of the view | The light source is visible first |
| Cracks | Cracked windscreen fault | Cracks cover 20% of the view | Constant |

## 6. Resources

Four resources run the game: Nerves is pressure in two directions, the Car is health, Cash is build power and the Clock is the price of stopping.

| Resource | Range and start | At the limit |
|---|---|---|
| Nerves | 0 to 100, starts at 30 | 100 is a Snap. Below the Heavy floor his eyes close. |
| The Car | 5 lamps, all dark | All lamps lit is a Wreck and ends the Telling |
| Cash | Starts at 40, in thousands of dinars | Cannot go below 0 |
| Clock | 22:00 to 06:00 | After 06:00 he arrives late |

### 6.1 Nerves, the two-sided meter

High Nerves is Frayed: he shakes. Low Nerves is Heavy: he falls asleep. The comfortable band narrows as the night goes on.

| Level | Effect |
|---|---|
| 100 | Snap: he leans on the horn for 2 s. He can steer and cannot reach. Suspicion +30. Nerves reset to 70. |
| 80 and up | Pound |
| 60 and up | Tunnel |
| 45 and up | Tremor |
| Between the floor and 45 | Steady. No effects. |
| Below the Heavy floor | Lids and Blink, unless Awake |
| 15 or more below the floor | Nod, unless Awake |

| Where | Heavy floor |
|---|---|
| Act 1 and the Checkpoint | 0 (never Heavy) |
| Act 2 and the Storm | 15 |
| Act 3 | 25 |
| Dawn | 0 |

**What raises Nerves**

| Source | Amount |
|---|---|
| Vehicles within 25 m | +0.15 per second each, capped at +0.6 |
| Close call | +2 |
| Grind | +2 |
| Cone or melon | +3 |
| Missed call | +4 |
| Honked at or cut off; a missed Exit | +5 |
| Ash dropped | +5 |
| Craving | +8 |
| Unanswered Doubt; phantom cramp; energy drink | +10 |
| Slap | +12 |
| Scrape, crash, head-on | +10, +20, +30 |
| Tailgater behind; rough shoulder | +1 per second |
| News on the radio | +0.5 per second |
| Rattle fault | +0.2 per second |

**What lowers Nerves**

| Source | Amount |
|---|---|
| Empty road: no vehicle within 60 m and no encounter | -0.5 per second |
| Radio music; a snoring passenger | -0.5 per second |
| Mixtape | -1 per second |
| Bead | -2 each |
| Horn | -3, once per 10 s |
| Cold tea | -3 |
| Arak sip; a happy honk from a wedding motorcade | -5 |
| Um Noor's call answered | -8 |
| Cigarette | -10 over its burn |
| Clean leg, no lamp lit | -10 at the leg's end |
| Hot tea | -12 |
| Visor photo | -20, once per leg |
| Tea stall | Sets Nerves to 30 |

**Awake** is a timed status that suppresses Lids, Blink and Nod. Sources: hot tea (40 s), a lit cigarette (while lit), sunflower seeds (20 s), a slap (20 s), opening the window (30 s), an energy drink (60 s), the news station (while tuned), a talking or drumming passenger (while they do).

### 6.2 Radio stations

| Station | Effect |
|---|---|
| Music | -0.5 Nerves per second |
| News | +0.5 Nerves per second; Awake; at 10 s into each leg it names the leg's encounter and the next boss modifier if any |
| Call-in show | No effect. Carries jokes and one song dedication to "Noor and her groom" per Telling. |
| Static | No effect. Every station drifts to static after 40 s. |

### 6.3 The Car

The car has no health bar. It has five warning lamps, and each lit lamp is a specific fault.

- Each hit lights 1, 2 or 3 lamps and draws that many faults from the Telling's fault deck, a seeded shuffle of the list below.
- When lit lamps reach capacity (5), the engine dies. That is a Wreck.
- A fitter removes one chosen fault and its lamp for 15 cash and 5 game minutes.

| Fault | Effect |
|---|---|
| Rattle | +0.2 Nerves per second |
| Cracked windscreen | Cracks cover 20% of the view |
| Dead headlight | Night view cone halved; +10 Suspicion per second during a night Patrol |
| Pulling steering | Constant 0.4 m/s drift to the left |
| Slipping clutch | The lever moves at half pointer speed |
| Stuck wiper | One sweep clears rain for 3 s instead of 6 |
| Cracked mirror | Mirror tells arrive 2 s later |

### 6.4 The Clock

- One real second of driving is 20 game seconds. A par leg of 90 s takes 30 game minutes.
- Par driving uses about 6 h 13 min of the 8 hours: 810 s of legs and 310 s of bosses. About 107 game minutes remain for stops.
- Stops are untimed in real time. Each charges a fixed number of game minutes on entry (section 9.6).
- Fourth gear banks about 7 game minutes per leg.
- The sky, the dashboard clock and the radio follow the Clock.

### 6.5 Suspicion

Suspicion exists only while a police car is behind (Patrol) or at a checkpoint.

| Behaviour during a Patrol | Suspicion |
|---|---|
| Any gear but 2 or 3 | +15 per second |
| Crossing a lane line without indicating | +20 |
| Using contraband in view | +40 |
| Using the phone; a Snap | +30 |
| Honking | +15 |
| Each cone | +10 |
| Dead headlight at night | +10 per second |
| Driving clean | -5 per second |

At 100 he is pulled over. An officer comes to the driver's window and he chooses by what he hands across.

| He hands over | Cost |
|---|---|
| His licence (a fine) | 25% of his cash, minimum 20; 20 game minutes; visible contraband is taken |
| Banknotes (a bribe) | 40 cash plus 10 per act; 5 game minutes; he keeps everything |

## 7. The cabin: slots, rituals and items

Items are objects in the cabin. Where an item sits sets its reach time, and the number of places limits the build.

### 7.1 Slots

| Slot | Count | Reach | Holds |
|---|---|---|---|
| `ashtray` | 1 | Near | Smoke habits |
| `cup_a`, `cup_b` | 2 | Near, Mid | Drinks |
| `phone_mount` | 1 | Mid | Phone |
| `mirror` | 1 | Mid | One hanging item |
| `dash_1`, `dash_2` | 2 | Mid | Small items |
| `tape` | 1 | Near | Mixtape |
| `seat` | 1 | Far | One large item or one passenger |
| `glovebox` | 2 cells | Far | Hides contraband |
| `roof` | 1 | None | Taxi sign |
| Adaptation bays | 3 | None | Adaptations |

### 7.2 Anatomy of an item

Every item answers the same questions. An item with nothing under "Takes" must cost a scarce slot or the hand.

| Field | Meaning |
|---|---|
| Gives | The benefit and how long it lasts |
| Takes | The impairment, risk or upkeep it adds |
| Ritual | Anchor, gesture, and whether it pulls the eyes down |
| Supply | Uses before restocking, and the restock price |
| Lapse | What happens when it is neglected |
| Contraband | Whether patrols and checkpoints punish it |

### 7.3 The starting cabin

Every Telling starts with these unless a Table says otherwise.

| Object | Where | Behaviour |
|---|---|---|
| Radio | `radio` | Section 6.2 |
| Photo | `visor` | Section 4.6 |
| Cigarettes, 5, and a lighter | `ashtray` | Section 7.4 |
| Tea glass, full and hot | `cup_a` | Section 7.4 |
| The hook | `seat` | Inert. Reaching it plays one narrator line per Telling. See the Wheel ring in section 7.6. |
| The letter | `glovebox`, on top of the registration | Inert. Must be dragged aside (0.4 s) to reach the registration. |
| Papers | Licence clipped at `dash_1`; ID in his `pocket`; registration in `glovebox` | Checkpoint and pull-over |
| His own phone | `pocket` | Rings only in Dawn (section 10.4) |
| Cash | 40 | Notes under a band on the dash |

### 7.4 Habits (need the hand)

| Habit | Slot | Gives | Takes | Ritual | Supply | Price |
|---|---|---|---|---|---|---|
| Cigarettes | `ashtray` | Lit for 25 s: no Tremor, Awake, -10 Nerves over the burn | Haze +2% per second while lit, clearing 3% per second after. Must be ashed once mid-burn or ash falls (+5 Nerves). Craving: +8 Nerves once if another is not lit within 30 s. | Light: HOLD 1.2 s. Ash: FLICK 0.4 s. | 10 a pack | 15 |
| Tea glass | cup | Hot sip: -12 Nerves, Awake 40 s. 3 sips. | Cold after 40 s: a cold sip is -3 Nerves and no Awake. Spills in a crash. | HOLD 0.6 s | Refill 2 cash at a fuel station, free at a tea stall | Start |
| Worry beads | `mirror` | -2 Nerves per bead | Only the hand. Calm leads to Heavy. | BEAD | None | 30 |
| Sunflower seeds | dash | Chewing for 20 s: Awake, and immune to Nerves from honks, tailgaters and Doubts | A reach every 20 s | TAP 0.3 s | 12 handfuls, restock 5 | 10 |
| Phone | `phone_mount` | A call every 25 to 40 s. Dispatcher: +10 cash. One call in four is Um Noor: -8 Nerves. | Eyes-down. A missed call is +4 Nerves. +30 Suspicion in a Patrol. | Three TAPs, 1.2 s, within 5 s of the first ring | None | 35 |
| Energy drink | cup | Focus for 30 s: the road runs at 85% speed while the hand runs at full speed. Awake 60 s. | +10 Nerves at once. Then Tremor amplitude +50% for 20 s. | HOLD 0.6 s | 3 cans, restock 10 | 30 |
| Painkillers | dash | Tremor halved for 60 s. Mutes the Phantom for the leg. | Heavy floor +15 for the rest of the leg. He opens the bottle with his teeth: the hand at his face blocks the lower-centre view. | HOLD 1.2 s at `face` | 6 pills, restock 15 | 40 |
| Mixtape | `tape` | Music that never drifts: -1 Nerves per second | Flip every 60 s or it warbles: +0.5 Nerves per second | DRAG out and in, 0.8 s | None | 25 |
| Tissue box | dash | One wipe clears all Haze | Only the hand | DRAG across the glass, 0.8 s | 6, restock 5 | 15 |
| Breath mints | dash | Police ignore Courage for 60 s | Nothing. It exists to enable the flask. | TAP 0.3 s | 5, restock 5 | 15 |
| Arak flask (contraband) | cup | Courage stack, up to 3, 45 s each: +50% close-call cash and -30% Nerves gains per stack. -5 Nerves per sip. | Sway and 40 ms Lag per stack | HOLD 0.7 s | 6 sips, restock 20 | Deal, 45 |

### 7.5 Keepsakes (work on their own)

| Keepsake | Slot | Effect | Price |
|---|---|---|---|
| Seven-eyed charm | `mirror` | The first scrape each leg lights no lamp. It swings into view on hard steering. | 40 |
| Air freshener | `mirror` | Haze clears twice as fast | 25 |
| Thermos | `seat` | Refills the tea, hot, on the road: Far reach, HOLD 1.0 s. 4 refills. | 30 |
| Duct tape | dash | The first fault each act repairs itself after 10 s | 35 |
| Lucky note | dash | +1 cash per close call | 35 |
| Cracked sunglasses | dash | Glare -70%; night legs 15% darker | 25 |
| Taxi sign | `roof` | Calls pay 5 more and come twice as often | 40 |

### 7.6 Adaptations (change the car to fit him)

Adaptations are real one-handed driving equipment, fitted by a roadside fitter. The car has 3 bays.

| Adaptation | Gives | Takes | Price |
|---|---|---|---|
| Crossover stalk | The indicator moves to the right of the column: reach 0.10 s instead of 0.41 s | A bay | 40 |
| Console window switch | The window opens with HOLD 0.6 s at a Near anchor instead of a cross-reach and three turns | A bay | 35 |
| Spinner knob | The wheel turns 40% faster per pixel | Self-centring is halved | 50 |
| Wheel ring | The hook hangs at the wheel. Setting it (TAP, 0.3 s) locks the wheel at its current angle for up to 4 s. 6 s cooldown. | A bay. It locks the angle, not the lane: drift still applies. | 60 |
| Thumb keypad | Horn and wipers work while gripping: middle click and scroll, or a second finger on touch | A bay | 55 |
| Fifth gear | Unlocks gear 5 | Nothing but temptation | 60 |
| Loud horn | Every vehicle yields; -5 Nerves | +15 extra Suspicion per honk | 45 |
| Bull bar | Lamp capacity +1 | Sideways speed -15% | 55 |
| Fog lamps | Visibility +40% in rain, dust and night | Oncoming drivers flash back: +2 Nerves each | 40 |
| Wide mirror | Mirror tells arrive 5 s earlier | The mirror covers more windscreen | 35 |

### 7.7 Deals (the shady guy)

The shady guy appears only after a leg with no lamp lit (section 9.6). Some Deals cost what the fitter cannot give back.

| Deal | Gives | Costs |
|---|---|---|
| Arak flask | Section 7.4 | 45 cash |
| Forged papers | Passes the next checkpoint's Papers phase automatically | 60 cash; contraband until used |
| Tinted glass | Suspicion gains halved | Lamp capacity -1; night legs 20% darker |
| Turbo | Gears 4 and 5 gain 15 km/h; close-call cash x1.5 | Lamp capacity -1; braking 30% weaker |
| The good stuff | Courage cap rises to 5 | 30 cash; 40 ms of permanent Lag |

### 7.8 Synergies

| Pair | Effect |
|---|---|
| Tea + Cigarettes | A sip while lit makes that cigarette burn 10 s longer |
| Cigarettes + Air freshener | No Haze from smoke |
| Beads + music (radio or tape) | Each bead is -4 Nerves |
| Flask + Photo | Looking at the photo with Courage: -40 Nerves, and all stacks are lost |
| Flask + Painkillers | Lag doubles and close-call cash doubles |
| Wheel ring + Spinner knob | On straights the hook holds the lane centre instead of a fixed angle |
| Phone + Taxi sign | Three calls answered in a row pay a 20 cash bonus |
| Seeds + Tea | The tea does not go cold while he chews |
| Crossover stalk + Thumb keypad | He indicates automatically when a lane change begins |

### 7.9 The Phantom

The missing arm is present in two small, fixed ways. Both can be turned off in settings, and both have counters in play.

| Behaviour | Trigger | Effect | Tell | Counter |
|---|---|---|---|---|
| Wrong-hand flinch | A cross-reach begun while Nerves are 60 or more, or while Lids are active | A faint left hand moves toward the control and passes through it. The real hand leaves 0.25 s late. | The ghost hand itself | Painkillers; any adaptation that removes that cross-reach |
| Weather cramp | Once per Rain leg, Night leg and Storm, at a fixed point | For 0.5 s the hand can neither let go nor take hold. +10 Nerves. | A low hum 1.5 s before | Painkillers mute it for the leg |

## 8. Passengers

A passenger is the strongest tool in the game and the only one that talks. This is pillar 6 in play.

### 8.1 Rules

- At most one passenger. They take the `seat`. A seat item moves to the back seat and is unusable while they ride. The hook stays usable if it hangs on a Wheel ring.
- Hitchers stand at Hitcher stops and sometimes at fuel stations and tea stalls. He accepts by reaching across and unlocking the passenger door (`glovebox`-class Far reach, TAP), or declines by leaving.
- Each passenger has a **Hand** (what they do when asked with a TAP on the shoulder, or all the time), a **Weight** (what they cost), a ride length and a fare.
- A passenger who is carried to Basra becomes a wedding guest (section 11.5).
- Any passenger can hold the phone during the Call (section 10.4).

### 8.2 The five passengers

| Passenger | Hand | Weight | Rides | Fare |
|---|---|---|---|---|
| The Hajjiya, an old woman with a caged chicken | On a tap she holds the wheel dead straight for up to 6 s | Forbids smoking and the flask: using either adds 10 Nerves. In gear 4 or above she prays aloud: +3 Nerves per second. | 3 legs | Food once: -20 Nerves. The first scrape after she leaves lights no lamp. |
| The Conscript, a soldier going home on leave | His uniform halves all Suspicion gains. On a tap he lights a cigarette and hands it over (no ritual time for the player). | He sleeps. His snoring lowers Nerves by 0.5 per second. A tap or the horn wakes him for 20 s, and only then does his Hand work. | To the end of the act | 10 |
| The Drummer, on his way to play a wedding | While he drums: music effect without the radio, and Awake. On a tap he passes the tea: sipping becomes an at-wheel reach. | His drum blocks the right 10% of the view. Drumming during a Patrol adds 10 Suspicion per second. A tap toggles the drumming. | To Basra | Nothing. He plays at the wedding. |
| The Student, an engineering student going home | She answers every call for him: the cash without the hand. Fork signs show 5 s earlier. She talks: Awake. | She watches the road: each scrape adds 5 Nerves. Gear 4 in rain adds 2 Nerves per second. | 3 legs | 20 |
| The Apprentice, a fitter's boy with a toolbox | He repairs one fault per leg. On a tap he holds the wheel at its current angle for 3 s. | While repairing he leans across the gear lever for 3 s, announced 2 s ahead: no shifting. He retunes the radio to static every 30 s. | To Basra | Nothing |

## 9. Roads: legs, beats, encounters, forks and stops

A leg is one 2.5 km stretch with one rule that changes how the hand may be used. There are nine leg types.

### 9.1 Leg types

| Leg | Acts | What changes | What it tests | Par (s) |
|---|---|---|---|---|
| Open road | 1 to 3 | 3 lanes, light traffic, long empty stretches | Staying awake; reaching on straights | 90 |
| Rush | 1 to 3 | Heavy traffic, frequent merges | Steering and close-call income | 90 |
| Rain | 1 to 3 | The view blurs over 6 s without a wiper sweep. Sideways response is 30% slower. | Hand rhythm | 95 |
| Night blackout | 2 to 3 | Unlit road. The view is the headlight cone. Hazards appear late. | The eyes | 90 |
| Roadworks | 2 to 3 | Three 150 m chicanes one lane wide (2.16 m) between cones | Precision under Tremor | 100 |
| Tailgater | 2 to 3 | A driver sits on the bumper for 40 s | Nerves and lane discipline | 90 |
| Patrol | 2 to 3 | A police car follows for 35 s | Clean driving and the cross-reach | 90 |
| Two-lane | 3 | Undivided road, slow trucks, overtakes into oncoming traffic | Timing and gear choice | 100 |
| Motorcade | 3 | Five black armoured cars fill the road at 70 km/h | Patience against the Clock | 110 |

Traffic density is 6 vehicles per km when light, 10 when medium, 16 when heavy. Each act adds 2.

### 9.2 The beat generator

A leg is a list of beats laid out by distance from 0 to 2,200 m. The last 300 m are the Exit and the Fork (section 9.5).

| Beat | Length (m) | Content |
|---|---|---|
| CALM | 150 | No vehicle or hazard in reach. A place to let go. |
| CLUSTER | 120 to 200 | 2 to 4 vehicles across lanes to weave through |
| SLOWPOKE | 120 to 200 | One slow vehicle in his lane with traffic beside it |
| MERGE | 120 | A vehicle signals and moves into his lane |
| CURVE | 120 to 170 | A signed bend with outward push |
| GUST | 60 | One crosswind push |
| HAZARD | 60 to 120 | A fixed obstacle: cones, a pothole, a hulk on the shoulder |
| SPECIAL | Varies | The leg type's encounter |

The generator must satisfy every rule below. Reject and redraw a leg that fails.

1. The first HAZARD, CLUSTER or SLOWPOKE begins within 5 s of the start at gear 3 (139 m).
2. At least two CALM beats per leg. No two CALM beats are adjacent, except on Open road.
3. At every point at least one lane is passable in gear 3 without a close call. The generator never builds a wall.
4. No vehicle spawns overlapping another.
5. The same seed gives the same leg.

### 9.3 Encounters

**Patrol.** Blue lights show in the mirror 3 s before Suspicion starts, about 20 s into the leg. Section 6.5 has the rules. Obeying the law means indicating, and indicating is a cross-reach.

**Tailgater.** He adds 1 Nerves per second and rams (a scrape from behind) if the player brakes. He leaves when the player changes lane and holds it for 3 s, after which he passes and brakes hard in front once. Fourth gear for 10 s also loses him.

**Motorcade.**
- Five unmarked black cars hold all lanes at 70 km/h. The last one carries a bilingual sign: "KEEP BACK 100 M".
- Within 100 m a spotlight turns on his windscreen: Glare 80% and +2 Nerves per second. Nothing else ever happens. The motorcade never touches him and never speaks.
- Staying behind for the whole leg takes 129 s.
- One side road appears mid-leg: a Two-lane detour that rejoins ahead of the motorcade.

**Two-lane.** Trucks ahead hold 60 km/h. Oncoming vehicles arrive every 6 to 10 s. Each gap is long enough to pass one truck in gear 4.

### 9.4 Modifiers

From Act 2 a leg may carry one modifier, shown on the fork sign.

| Modifier | Effect |
|---|---|
| Crosswind | A GUST beat every 15 s |
| Potholes | HAZARD beats doubled; each pothole hit is +3 Nerves and a 30% speed loss |
| Sheep | A flock crosses once: a slow-moving wall with one gap |
| Wedding motorcade | Slow decorated cars across two lanes. Passing one closely earns a happy honk: -5 Nerves instead of +2. |
| Melon truck | A truck sheds melons for 10 s: rolling cones |
| Dust haze | Haze +1% per second with the window open; visibility 120 m |

### 9.5 Forks and Exits

There are no menus during a Telling. Roads and stops are chosen with the wheel.

- **Fork.** Before each leg the road splits in two. An overhead sign shows, for each branch: the leg type, any modifier, the stop at its end, and par. The branch is decided by which side of the split the car is on at the gore point.
- **Exit.** At 2,200 m a slip lane opens on the right, signed 5 s ahead. To stop, he must be in the slip lane and at 70 km/h or less when he reaches the stall at 2,330 m. Too fast or in the wrong lane, and the stop is missed: +5 Nerves.
- After each act's third leg there is no fork. The road leads into the boss.

### 9.6 Stops

A stop offers one service. The car is parked, the vendor stands at the passenger window, and the hand does the shopping: TAP an offered item to buy it, then DRAG it to a slot. Gripping the wheel for 0.5 s leaves.

| Stop | Service | Clock cost (game min) |
|---|---|---|
| Fuel station | 3 items from Habits and Keepsakes, plus restocks | 10 |
| Fitter | Repairs at 15 cash each (+5 min each); 2 Adaptations for sale | 15 |
| Tea stall | Sets Nerves to 30; refills the tea; the next fork sign also shows the next boss modifier | 20 |
| Roadside find | One free Keepsake out of 2 shown | 5 |
| Hitcher | One passenger offered | 2 |

- **The shady guy** joins the next stop as a second vendor after any leg with no lamp lit. He offers 2 Deals. Using him adds 5 minutes. This is the main way skill buys build power.
- **After each boss** the player takes one free item out of 3 and one service of their choice, at no Clock cost.
- Shop rarity is 60% common, 30% uncommon, 10% rare in Act 1, moving to 45, 35 and 20 by Act 3.

## 10. Set pieces

### 10.1 Prologue: "Two Hands"

It plays once on first launch and can be replayed from the title. It lasts 75 s and cannot be failed.

- **Setting.** Dawn, 22 years ago. The same car, clean. A solid left arm holds the wheel and keeps the lane by itself. The pointer is the right hand, and nothing it does has a cost. A bundle in a second figure's lap on the passenger side makes small sounds.
- **Steps.** Each object pulses in turn and one short subtitle names the action.

| # | Prompt | Teaches |
|---|---|---|
| 1 | Tune the radio to music | Reaching, DRAG |
| 2 | Sip the tea | HOLD |
| 3 | Shift from 2nd to 3rd | The gate |
| 4 | Honk at a friend passing | TAP at the wheel |
| 5 | It rains: flick the wipers. The left hand indicates and changes lane by itself. | FLICK; shows the left side working for free |
| 6 | Tuck the new photo into the visor | DRAG_TO |
| 7 | None. The left hand lifts off the wheel toward the window crank. The screen whites out. Title card. | |

- **Cut to tonight.** 22:00. The same visor and photo, faded. The left sleeve is pinned. The car is rolling in first gear with the wheel unheld, drifting right. The narrator says `narrator.start`. Nothing tells the player to grab the wheel.

### 10.2 The Checkpoint (ends Act 1, about 90 s)

| Phase | What happens | Rules |
|---|---|---|
| 1. Queue | Stop-and-go in first gear between concrete barriers 2.34 m apart (1.3 car widths) | Touching a barrier is a scrape and +25 Suspicion |
| 2. Stow | 10 s before the soldier reaches the driver's window | Each contraband item must be dragged to a glovebox cell. Each item left out: +40 Suspicion. Each Courage stack: +15. |
| 3. Papers | A sign shows one of three documents | Find it (licence at `dash_1`; ID in `pocket`; registration in `glovebox` under the letter). Open the window: cross-reach, CRANK(3). Hand it out: DRAG_TO `driver_window`. Each 5 s of delay: +10 Suspicion. |

Under 50 Suspicion he passes. From 50 to 99 he is searched: 15 game minutes and contraband is taken. At 100 he is turned back: 30 game minutes and the queue again. Banknotes handed through the window (60 cash) pass at any level.

Modifiers: Long queue (phase 1 is 50% longer); Thorough (two documents).

### 10.3 The Storm (ends Act 2, par 100 s)

- The Storm is 2,000 m of dust. Progress is by distance, so stopping never shortens it.
- Visibility alternates on a fixed 20 s rhythm: 12 s thick (15 m) and 8 s thin (40 m). In thick dust the player follows tail lights.
- Gusts push at 2 m/s, each announced by dust streaks 1 s ahead.
- Wipers smear the dust: each sweep adds 10% Haze. An open window adds 5% Haze per second.
- Stopping on the shoulder with hazard lights on is always safe. Stopping without them risks a rear-end crash every 10 s.
- The weather cramp fires once (section 7.9).

Modifiers: Crosswind (gusts 50% stronger); Night storm (only the headlight cone).

### 10.4 Dawn and the Call (ends Act 3, about 120 s)

| Phase | What happens |
|---|---|
| 1. False dawn | An orange glow fills the right of the horizon. It is burning gas from the oil fields. Rush traffic builds. |
| 2. Sunrise | The real sun rises ahead and to the left: Glare 60%. Flipping the visor blocks it for 3 s and shows the photo. A last checkpoint waves him through at 70 km/h between barriers. |
| 3. The Call | 833 m from the end, the phone in his pocket rings. It is Noor. It rings for 8 s. |

| Response to the Call | Cost |
|---|---|
| Ignore it | None. The true ending is lost. |
| Answer alone: TAP the pocket | For 30 s the hand holds the phone to his ear. He steers with his wrist at 40% sensitivity and cannot reach anything. |
| Answer with a passenger: DRAG the phone to them | They hold it to his ear. Steering is normal. He cannot reach anything for 30 s. |
| Pull over, hazards on, then answer | The car is stopped for 30 s: 10 game minutes |

Modifiers: Market day (traffic +30%); Early sun (Glare from phase 1).

### 10.5 Arrival

The road ends in a street. He brakes to a stop in a marked bay and turns the key (TAP). The Clock is read at that moment. A short scene follows per ending (section 11.4), then the party.

### 10.6 Finale: "One Hand"

It plays after the true ending at Noor's Table. There is no driving and no failure.

1. The wedding room. Guests clap a steady rhythm. Noor stands in front of him and raises her palm.
2. The pointer is his hand. Each TAP on her palm is a clap, and the room's clapping doubles with it. After 8 claps she takes his hand.
3. Holding the left button holds her hand. The camera walks them to the groom over 10 s and stops.
4. Nothing happens until the player releases the button. There is no prompt and no timer. At 20 s she says "Baba." At 90 s the room starts clapping softly again.
5. On release her hand goes to the groom's. Cut to a title card with `finale.proverb`. Credits.

## 11. Run structure and progression

### 11.1 A Telling

```
Fork > Leg > Exit/Stop  (x3)  > Boss > Boss stop      = one act
Act 1: Checkpoint   Act 2: Storm   Act 3: Dawn > Arrival
```

The game saves at every stop and after every boss. Nothing is saved during a leg.

### 11.2 The seven Tables

Each Table is its own ruleset on top of the base game. Rules do not stack from Table to Table. A Table unlocks by winning the one before it on time.

| # | Table | Its rule | Heckles |
|---|---|---|---|
| 1 | The Children | One free rewind: the first Wreck returns to the start of that leg. Prices -25%. | Twists (sheep, melons); the Fib |
| 2 | The Drivers, his friends from the taxi rank | Base rules | Dares |
| 3 | The Uncles, who think a father should not be here | A Patrol leg in every act. Checkpoint Suspicion gains x1.25. | Doubts |
| 4 | The In-laws | No contraband, no Deals, no bribes. Each Snap costs 15 game minutes. | Questions |
| 5 | The Aunts, who raised Noor with him | Heavy floor +10 all night. Prices +25%. He starts with a Thermos and seeds. | Orders |
| 6 | The Groom | He leaves at 22:45. Any boss begun without a passenger starts with +20 Nerves. | Dares, Doubts, Orders |
| 7 | Noor | The true night. One fixed road with no forks. The starting cabin plus beads and a full pack. No shops but tea and repairs. No heckles. The Student waits at the second stop of Act 2. | None |

Noor's fixed order: Open road, Rush, Rain, Checkpoint; Night blackout, Patrol, Roadworks, Storm; Tailgater, Two-lane, Motorcade, Dawn. Chance belongs to the embellished Tellings; the true one is a fixed course to master.

### 11.3 Heckles

- One heckle per leg in Act 1, two per leg after. Never during an encounter or a boss.
- The subtitle appears 2 s before anything changes. That lead is the tell.

| Type | What it does |
|---|---|
| Twist | Injects a modifier beat: sheep, a melon truck, a wedding motorcade, a 20 s shower |
| Dare | An optional goal with a 15 s window. Hold fourth gear for 10 s (+15 cash). Chain three close calls (+20). Three seconds hands-off on a straight (+10). Pass three vehicles in 10 s (+15). |
| Doubt | +10 Nerves after 15 s, unless he answers with a close call or 5 s in fourth gear. Then it is -10 instead. |
| Question | Keep Nerves under 50 with no horn for 15 s: -10 Nerves and +10 cash |
| Order | Perform the named ritual within 10 s: -8 Nerves. Ignore it: +6. |
| The Fib | Children only. "Both hands!" A ghost left hand holds the lane for 5 s. |

### 11.4 Endings

| Ending | Condition | Result |
|---|---|---|
| Wreck | All lamps lit | The Table objects, he corrects himself, the Telling restarts in 3 s |
| Late | Parked after 06:00 | She is already up. A short rueful scene. Nothing unlocks. |
| On time | Parked by 06:00 | The next Table unlocks |
| The Call | Answered the Call and parked by 06:00 | The Table is marked "told true". At Noor's Table it starts the finale. |

### 11.5 What persists

| Persists | How it is earned |
|---|---|
| Tables | Winning the previous Table on time |
| Wedding guests | Each passenger carried to Basra sits at a Table from then on and adds two heckles to the pool |
| Commute mode | The first win. One seeded 5 km leg scored on cash, with a daily seed. |
| Endless Night mode | Any Call ending. Legs without end, scored on distance. |
| Settings and statistics | Always |

No gate counts runs, playtime or currency.

## 12. Economy and balance

A competent Telling earns 350 to 600 cash and buys five to seven items on top of three free picks.

### 12.1 Income per leg

| Source | Rule | Typical in gear 3 | Typical in gear 4 |
|---|---|---|---|
| Close calls | 2 cash, times gear, times chain | 16 | 50 |
| Clean leg | 15 for lighting no lamp | 15 | 15 |
| Beating par | 1 cash per 2 s under par | 0 | 10 |
| Phone, if owned | 10 per answered call | 25 | 25 |
| Dares | 10 to 20 each | 15 | 15 |
| Fares | 10 to 20 at drop-off | | |

### 12.2 Prices

| Thing | Cash |
|---|---|
| Common item | 10 to 30 |
| Uncommon item | 35 to 50 |
| Rare item | 55 to 60 |
| Restock | 2 to 20 |
| Repair one fault | 15 |
| Bribe on the road | 40 plus 10 per act |
| Bribe at the Checkpoint | 60 |
| Fine | 25% of cash, minimum 20 |

### 12.3 Difficulty across a Telling

| Lever | Act 1 | Act 2 | Act 3 |
|---|---|---|---|
| Heavy floor | 0 | 15 | 25 |
| Base traffic per km | 6 | 8 | 10 |
| Leg pool | Open road, Rush, Rain | Adds Night, Roadworks, Tailgater, Patrol | Adds Two-lane, Motorcade |
| Late signallers | None | 15% | 30% |
| Legs with a modifier | None | One in three | Two in three |
| Heckles per leg | 1 | 2 | 2 |

### 12.4 Balance rules

1. **Skill carries.** An expert must be able to win the Drivers' Table buying nothing. Test at every milestone.
2. **Every item has a job.** Aim for a clear role, not equal power.
3. **Nothing is a free stat.** If an item has no cost, give it one or cut it.
4. **Impairments are learnable.** Fixed rhythm, clear tell, no noise.
5. **Hazards change plans first.** Lamps are the last resort of an encounter.
6. **No ritual needs more than 1.5 s of perform time.**
7. **New things first appear on quiet road.**
8. **The generator never builds a wall.**

### 12.5 Targets and the bot

A human tunes by feel. The bot gives the builder numbers before a human plays. It drives through the same simulation at three skill levels (section 13.8).

| Measure | Target |
|---|---|
| Hands-off time from lane centre, straight, gear 3 | 3.4 s (exact) |
| Hand off the wheel with a mid-game cabin | 25% to 40% of leg time |
| Expert bot, Drivers' Table, no purchases | Wins 40% to 60% of seeds |
| Competent bot, Drivers' Table, buying sensibly | Wins 15% to 30% |
| Novice bot, Children's Table | Reaches the Checkpoint in 50% or more |
| Share of Wrecks from one unavoidable event | 0% |

---

# Part III. Build spec

## 13. Technical architecture

### 13.1 Project settings

| Setting | Value |
|---|---|
| Engine | Godot 4.7.x stable. Record the exact version in `DECISIONS.md`. |
| Renderer | Forward+. Use only depth fog, standard lights and screen-space shaders, so the Mobile renderer also works later. |
| Window | 1920 by 1080, stretch mode `canvas_items`, aspect `expand` |
| Physics ticks | 120 per second. Gameplay steps in `_physics_process`. |
| Mouse | Captured during play; a virtual pointer drawn by the game |
| Input actions | `grip` (mouse left), `brake` (mouse right, Space), `pad_horn` (mouse middle), `pad_wiper` (wheel up), `pause` (Esc), debug F1 to F8 |

### 13.2 Folder layout

```
res://
  data/      tuning.json items.json rituals.json legs.json beats.json modifiers.json
             stops.json passengers.json tables.json heckles.json faults.json
             anchors.json placeholders.json sfx.json lines_en.csv lines_ar.csv
  src/core/  pure simulation, no Node:
             rng.gd tuning.gd effect_system.gd gesture.gd gear_gate.gd hand_sim.gd
             wheel_sim.gd car_sim.gd traffic_sim.gd collision.gd nerves_sim.gd
             fault_sim.gd clock_sim.gd suspicion_sim.gd item_sim.gd passenger_sim.gd
             heckle_director.gd leg_generator.gd run_generator.gd drive_sim.gd
             run_state.gd save.gd
  src/game/  autoloads: game.gd events.gd settings.gd lines.gd audio.gd
  src/view/  cabin_view.gd hand_view.gd road_view.gd vehicle_view.gd sky_view.gd
             postfx.gd subtitle_view.gd stop_view.gd wedding_view.gd debug_hud.gd
  src/bot/   driver_bot.gd balance_runner.gd
  scenes/    boot.tscn title.tscn wedding.tscn drive.tscn
  shaders/   postfx.gdshader world_bend.gdshader
  tests/     run_tests.gd test_*.gd tests.json
  tools/     check.sh run_balance.sh
  docs/      GDD.md PROGRESS.md DECISIONS.md
```

### 13.3 The simulation

`DriveSim` owns every simulation object and exposes two things: `step(input: DriveInput)` and `snapshot() -> Dictionary`. Views read the snapshot each frame. Nothing outside `src/core` changes game state.

```
DriveInput { pointer: Vector2, pointer_delta: Vector2,
             lmb: bool, rmb: bool, pad_horn: bool, pad_wiper: bool }
```

Step order, every tick, with dt = 1/120:

1. Gesture recogniser.
2. Hand: target, travel, grip, held object.
3. Rituals in progress; completed rituals emit effects.
4. Wheel: commanded angle, smoothing, Tremor, Lag, return, hook lock.
5. Car: gear, speed, sideways motion, drift.
6. Traffic: spawns, movement, lane changes, horn yields.
7. Collisions and close calls.
8. Encounters and Suspicion.
9. Effect timers, Nerves, faults.
10. Clock.
11. Heckles and passengers.
12. Leg progress: Exit, Fork, boss and ending transitions.

**Determinism.** Use four seeded `RandomNumberGenerator` streams derived from the Telling seed: `road`, `shop`, `heckle`, `bot`. Never call global random functions. Record `DriveInput` per tick to a log; replaying a log must reproduce the final state hash.

**Effects.** `EffectSystem` holds timed statuses by id (`awake`, `courage`, `focus`, `chewing`, `tremor_mute` and so on) with stack counts and expiry. Items never change other systems directly. They add, remove or query statuses and emit resource changes.

### 13.4 Application states

```
BOOT > TITLE > PROLOGUE (first launch) > WEDDING
WEDDING > TELLING:  FORK > LEG > EXIT > STOP > ... > BOSS > BOSS_STOP > ... > ARRIVAL > ENDING > WEDDING
any LEG or BOSS > WRECK_CUT (3 s) > TELLING restarts
ENDING at Noor's Table with the Call > FINALE > CREDITS > WEDDING
```

`drive.tscn` is one scene used for the prologue, legs, bosses, stops and modes. It is configured by a `DriveContext` dictionary.

### 13.5 Scene tree for `drive.tscn`

```
Drive (Node3D, drive_controller.gd: builds DriveInput, steps DriveSim)
  Camera3D                    eye; glance and eyes-down offsets
  Cabin (cabin_view.gd)       placeholder meshes built from placeholders.json and anchors.json
    Wheel, GearLever, Dash, Mirror, Visor, Seat, Glovebox, ItemMounts
    Hand (hand_view.gd)       two-bone arm solved in code
  Road (road_view.gd)         recycled road chunks, lane lines, shoulder, rails, props
    Vehicles                  pooled vehicle_view instances
  Sky (sky_view.gd)           gradient by Clock; sun; flares; headlight SpotLight3D
  PostFX (CanvasLayer)        one full-screen shader
  Subtitles (CanvasLayer)
  DebugHUD (CanvasLayer)
```

**The arm.** Solve it analytically. The shoulder is fixed. Upper arm and forearm are 0.30 m each. For targets beyond reach, slide the shoulder up to 0.25 m toward the target. Draw two capsules and a box. Do not use a Skeleton3D or the engine's IK nodes.

**The road.** The car stays at the origin and the world scrolls. Curves are drawn by a vertex shader that bends the world sideways with distance. The simulation road is always straight.

### 13.6 Signals on the `Events` bus

`leg_started`, `leg_ended`, `fork_taken`, `stop_entered`, `stop_left`, `boss_started`, `boss_ended`, `ritual_completed`, `item_bought`, `effect_added`, `effect_expired`, `nerves_threshold_crossed`, `snap`, `blink`, `nod`, `lamp_lit`, `fault_repaired`, `hit`, `close_call`, `suspicion_changed`, `pulled_over`, `heckle_started`, `heckle_resolved`, `passenger_boarded`, `passenger_left`, `call_started`, `call_resolved`, `wreck`, `arrived`, `line_requested`, `sfx_requested`.

### 13.7 Save file

`user://save.json`, written at stops and after bosses.

```json
{
  "version": 1,
  "profile": { "tables_unlocked": ["children","drivers"], "told_true": [],
               "guests": ["drummer"], "modes": ["commute"], "prologue_seen": true },
  "telling": { "table": "drivers", "seed": 123456, "act": 2, "leg": 1,
               "clock_min": 212, "cash": 87, "nerves": 34,
               "faults": ["rattle"], "items": [{"id":"beads","slot":"mirror","supply":0}],
               "adaptations": ["crossover_stalk"], "passenger": null,
               "fault_deck": ["cracked_mirror","pulling_steering"], "rng_state": {} }
}
```

### 13.8 The bot

`DriverBot` plays through the simulation at the intent level: it sets the hand target, grip and gesture completion, with realistic durations. It does not synthesise mouse motion.

| Parameter | Novice | Competent | Expert |
|---|---|---|---|
| Reaction delay (s) | 0.40 | 0.25 | 0.15 |
| Lane-keeping error (m, standard deviation) | 0.25 | 0.12 | 0.05 |
| Safety margin before letting go (s) | 2.5 | 1.5 | 1.0 |
| Cruising gear | 3, braking often | 3 | 4 when Nerves allow |

Policy: keep the lane whose next obstacle is farthest; change lane when time to collision falls below 3 s; let go only inside a CALM beat with enough time for the most urgent pending ritual plus the margin. `tools/run_balance.sh` runs 100 seeds per skill per Table headless and writes `artifacts/balance.json`.

### 13.9 Debug tools

| Key | Tool |
|---|---|
| F1 | Numeric HUD: Nerves, lamps, cash, clock, gear, speed, Suspicion, active effects |
| F2 | Live tuning panel for every value in `tuning.json`, with export |
| F3 | Skip to the end of the leg |
| F4 | +50 cash |
| F5 | Give an item by id |
| F6 | Set Nerves |
| F7 | Toggle the bot at the wheel |
| F8 | Half speed |

Command-line arguments after `--`: `--table=`, `--seed=`, `--leg=`, `--boss=`, `--bot=`, `--skip-prologue`.

### 13.10 Commands

| Purpose | Command |
|---|---|
| Import assets | `godot --headless --path . --import` |
| Run tests | `godot --headless --path . --script res://tests/run_tests.gd` |
| Scene smoke test | `godot --headless --path . res://scenes/drive.tscn --quit-after 600` |
| Dump the engine API | `godot --doctool docs_api` |

`tools/check.sh` runs import, a parse check of every script, the data validator, the tests and the smoke tests, and exits non-zero on any failure.

## 14. Data schemas

All content is JSON. The validator checks required keys, types, and that every referenced id exists.

**Item**

```json
{ "id": "cigarettes", "kind": "habit", "slots": ["ashtray"], "tags": ["smoke"],
  "rarity": "common", "price": 15, "contraband": false,
  "supply": { "uses": 10, "restock": 15 },
  "rituals": ["cig_light", "cig_ash"],
  "gives": [ {"effect": "lit", "duration": 25},
             {"resource": "nerves", "amount": -10, "over": 25} ],
  "takes": [ {"effect": "haze_rate", "amount": 0.02, "while": "lit"} ],
  "lapse": { "after": 30, "resource": "nerves", "amount": 8, "once": true },
  "synergies": [ {"with": "tea_glass", "rule": "sip_extends_burn", "amount": 10} ],
  "line_ids": { "name": "item.cigarettes.name" } }
```

**Ritual**

```json
{ "id": "cig_light", "anchor": "ashtray", "gesture": "HOLD", "hold_s": 1.2,
  "eyes_down": false, "blocks_view": null, "requires": ["supply>0", "!lit"],
  "on_complete": ["consume_supply", "add_effect:lit"], "sfx": "lighter_click" }
```

**Leg**

```json
{ "id": "patrol", "acts": [2, 3], "lanes": 3, "divided": true, "density": 10,
  "condition": "clear", "par_s": 90,
  "beat_weights": { "CALM": 3, "CLUSTER": 3, "SLOWPOKE": 2, "MERGE": 2, "CURVE": 1, "HAZARD": 1 },
  "special": { "kind": "patrol", "at_s": 20, "duration_s": 35 },
  "modifiers_allowed": ["crosswind", "potholes"] }
```

**Beat**

```json
{ "id": "merge_right_truck", "type": "MERGE", "length_m": 120, "min_lanes": 2,
  "spawns": [ {"vehicle": "truck", "lane": "right_of_player", "s_offset": 60,
               "speed_kmh": 65, "lane_change": {"to": "player", "at_s_offset": 90}} ] }
```

**Stop**

```json
{ "id": "fuel_station", "service": "shop", "stock": {"count": 3, "pools": ["habit", "keepsake"]},
  "clock_min": 10, "weight": 30 }
```

**Passenger**

```json
{ "id": "hajjiya", "rides_legs": 3, "fare": 0,
  "hand": { "kind": "hold_wheel_straight", "duration_s": 6, "on": "tap" },
  "weights": [ {"when": "ritual_tag:smoke", "resource": "nerves", "amount": 10},
               {"when": "gear>=4", "resource": "nerves", "per_s": 3} ],
  "on_leave": ["nerves:-20", "add_effect:blessing"], "line_prefix": "passenger.hajjiya" }
```

**Table**

```json
{ "id": "uncles", "unlock": "win:drivers", "depart_min": 0,
  "rules": { "patrol_every_act": true, "checkpoint_suspicion_mult": 1.25 },
  "heckle_weights": { "DOUBT": 60, "TWIST": 20, "DARE": 20 }, "line_prefix": "table.uncles" }
```

**Heckle**

```json
{ "id": "doubt_all_night", "type": "DOUBT", "tables": ["uncles", "groom"],
  "line_id": "heckle.uncles.doubt.1", "window_s": 15,
  "answer": ["close_call", "gear4_5s"], "pass": {"nerves": -10}, "fail": {"nerves": 10} }
```

**Line** (CSV): `id, speaker, text, needs_writer`. `lines_ar.csv` has the same ids and empty text.

**Placeholder registry**

```json
{ "veh_truck": { "placeholder": {"shape": "box", "size": [2.5, 3.0, 12.0], "color": "#6C7A89"},
                 "scene": null } }
```

When `scene` is set, the view instantiates it instead of the primitive. `sfx.json` works the same way with `synth` and `stream`.

## 15. Tuning constants

These are the starting values. Implement them exactly, load them from `tuning.json`, and expose them in the F2 panel.

**Hand and wheel**

| Constant | Value | Unit |
|---|---|---|
| hand_speed | 1.5 | m/s |
| hand_left_side_mult | 0.7 | multiplier |
| hand_pound_mult | 0.85 | multiplier |
| anchor_snap_radius | 60 | px |
| input_buffer | 0.30 | s |
| grip_zone_half_width | 0.045 | m |
| wheel_max_angle | 135 | degrees |
| steer_deg_per_px | 0.35 | degrees at 1080p |
| wheel_smoothing | 60 | ms |
| wheel_return_rate | 200 | degrees per s |
| gate_unit | 40 | px |
| gate_channel_half_width | 0.25 | units |
| glance_start, glance_gain, glance_max_yaw, glance_max_pitch | 25, 0.6, 35, 25 | degrees, ratio |
| eyes_down_pitch | 35 | degrees |

**Car**

| Constant | Value | Unit |
|---|---|---|
| lane_width, car_width, car_length | 3.5, 1.8, 4.4 | m |
| leg_length, leg_tail | 2500, 300 | m |
| gear_speeds | 40, 70, 100, 130, 160 | km/h |
| lat_per_kmh | 0.05 | m/s per km/h at full lock |
| lat_follow_tau | 0.12 | s |
| gear_cash_mult | 0, 0.5, 1, 2, 3 | multiplier |
| accel, engine_brake, brake_decel, neutral_coast | 12, 20, 30, 6 | km/h per s |
| crown_drift | 0.25 | m/s |
| curve_k, curve_cap | 0.5 / 1.0 / 1.5, 2.0 | m/s |
| gust_push, gust_duration | 1.5, 1.0 | m/s, s |
| shoulder_speed_cap | 70 | km/h |
| exit_max_speed | 70 | km/h |

**Collisions and close calls**

| Constant | Value | Unit |
|---|---|---|
| scrape_max_closing, crash_max_closing | 30, 80 | km/h |
| hit_immunity | 0.8 | s |
| hit_pushback | 0.5 | m |
| close_call_gap, close_call_min_closing | 0.6, 30 | m, km/h |
| close_call_base_cash | 2 | cash |
| chain_window, chain_step, chain_cap | 4, 0.25, 3 | s, ratio, multiplier |

**Nerves**

| Constant | Value | Unit |
|---|---|---|
| nerves_start | 30 | points |
| tremor_from, tunnel_from, pound_from, snap_at, snap_reset | 45, 60, 80, 100, 70 | points |
| heavy_floor by act | 0, 15, 25 | points |
| nod_depth | 15 | points below the floor |
| tremor_frequency, tremor_max_amplitude | 3, 12 | Hz, degrees |
| blink_period, blink_length, blink_tell | 6, 0.3, 1.0 | s |
| nod_period, nod_length, nod_tell | 10, 1.5, 1.5 | s |
| lids_close_time, lids_max | 3, 0.25 | s, share of screen each |
| empty_road_radius, empty_road_rate | 60, -0.5 | m, per s |
| traffic_radius, traffic_rate, traffic_rate_cap | 25, 0.15, 0.6 | m, per s |
| sway_per_stack, sway_frequency | 0.3, 0.4 | m/s, Hz |
| lag_per_source, lag_cap | 40, 200 | ms |
| haze_cap | 0.6 | share |

**Car faults, cash, clock, law**

| Constant | Value | Unit |
|---|---|---|
| lamp_capacity | 5 | lamps |
| repair_price, repair_minutes | 15, 5 | cash, game min |
| cash_start | 40 | cash |
| clean_leg_bonus | 15 | cash |
| par_bonus_rate | 0.5 | cash per s under par |
| clock_start, clock_deadline | 22:00, 06:00 | game time |
| clock_scale | 20 | game s per real s |
| patrol_duration, suspicion_decay | 35, 5 | s, points per s |
| fine_share, fine_min, fine_minutes | 0.25, 20, 20 | ratio, cash, game min |
| bribe_base, bribe_per_act, bribe_minutes | 40, 10, 5 | cash, cash, game min |
| checkpoint_bribe | 60 | cash |

**Structure**

| Constant | Value | Unit |
|---|---|---|
| spawn_ahead, spawn_ahead_oncoming, despawn_behind | 300, 400, 100 | m |
| signal_time, late_signal_time, lane_change_time | 1.0, 0.4, 2.0 | s |
| calm_length | 150 | m |
| first_event_within | 139 | m |
| heckle_lead | 2 | s |
| stop_minutes: fuel, fitter, tea, find, hitcher, shady | 10, 15, 20, 5, 2, 5 | game min |
| stop_weights: fuel, fitter, tea, find, hitcher | 30, 20, 20, 15, 15 | weight |
| rarity by act (common, uncommon, rare) | 60/30/10, 52/33/15, 45/35/20 | % |
| wreck_to_wheel | 3 | s |

All item, passenger, encounter and boss numbers in Part II are also tuning values. Store them in their own data files.

## 16. Placeholder presentation

### 16.1 Visual language

Build everything from boxes, cylinders, capsules and flat unshaded colours. The colour says what a thing is.

| Thing | Placeholder |
|---|---|
| Interactable anchor | Yellow `#F2C230`. White outline when the pointer snaps to it. |
| Hand and right arm | Tan `#C68642` capsules and a box. The left sleeve is a short grey stub. |
| Wheel, dash, cabin shell | Dark greys |
| Contraband | A magenta tag on the object |
| Hazards and cones | Red `#D64541` |
| Car, taxi, truck, tanker | White, yellow, blue-grey, silver boxes with emissive head and tail quads |
| Police | White and blue box with a flashing light |
| Motorcade | Black boxes |
| Vendor, soldier, officer, passenger | Green, khaki, blue, purple capsules |
| Noor, guests | White capsule; assorted capsules |
| Signs and adverts | Label3D text in square brackets, such as `[AD]` or `[PATROL / FITTER / 90]` |

### 16.2 Cabin anchors

Cabin frame: origin at the wheel hub; +X toward the passenger; +Y up; +Z toward the driver. Units are metres. Times are one-way from the grip reference point G and are checked by a test.

| Anchor | Position (x, y, z) | One-way time (s) |
|---|---|---|
| G, grip reference | (0.13, 0.14, 0.00) | |
| W, cross waypoint | (0.00, 0.24, 0.05) | |
| eye | (0.00, 0.32, 0.50) | |
| shoulder | (0.22, 0.05, 0.55) | |
| `wiper_stalk` | (0.22, 0.02, 0.02) | 0.10 |
| `horn` | (0.00, 0.00, 0.00) | 0.13 |
| `hazard_button` | (0.30, 0.06, -0.14) | 0.16 |
| `radio` and `tape` | (0.38, 0.02, -0.14) | 0.21 |
| `ashtray` | (0.34, -0.08, -0.10) | 0.21 |
| `gear_lever` | (0.33, -0.12, 0.12) | 0.23 |
| `cup_a` | (0.38, -0.12, -0.02) | 0.24 |
| `face` | (0.05, 0.24, 0.36) | 0.26 |
| `pocket` | (0.08, 0.05, 0.42) | 0.29 |
| `dash_1` | (0.45, 0.20, -0.30) | 0.30 |
| `phone_mount` | (0.56, 0.12, -0.18) | 0.31 |
| `visor` | (0.05, 0.60, -0.10) | 0.32 |
| `cup_b` | (0.52, -0.16, 0.05) | 0.33 |
| `mirror` | (0.42, 0.50, -0.20) | 0.34 |
| `dash_2` | (0.62, 0.20, -0.30) | 0.39 |
| `passenger_shoulder` | (0.75, 0.15, 0.50) | 0.53 |
| `glovebox` | (0.92, -0.10, -0.22) | 0.57 |
| `seat` | (0.80, -0.25, 0.45) | 0.60 |
| `indicator_stalk` | (-0.22, 0.02, 0.02) | 0.41, via W |
| `headlight_knob` | (-0.30, -0.02, -0.12) | 0.53, via W |
| `driver_window` | (-0.50, 0.15, 0.20) | 0.62, via W |
| `window_crank` | (-0.48, -0.10, 0.25) | 0.70, via W |

The wheel has radius 0.19 m. The camera's vertical field of view is 75 degrees.

### 16.3 Reading the state without a HUD

| State | Shown by |
|---|---|
| Lamps and faults | Five dashboard lamps, plus each fault's visible or audible effect |
| Nerves, high | Hand tremor, dark edges, heartbeat |
| Nerves, low | Dark bars from top and bottom, yawns |
| Cash | A stack of notes on the dash that shrinks and grows |
| Clock | A dashboard clock and the colour of the sky |
| Gear and speed | Lever position and engine pitch |
| Supplies | Cigarettes left in the pack, tea level, beads counted |
| Suspicion | Blue light in the mirror growing brighter; siren chirps |
| Close-call chain | A rising run of tyre squeals |
| Heckles and lines | Subtitles with a speaker tag |

### 16.4 Post effects

One full-screen shader takes these uniforms from the snapshot: `tunnel`, `lids`, `blink`, `haze`, `rain_blur`, `cracks`, `glare_amount`, `glare_position`, `darkness`. No effect flashes faster than three times a second.

### 16.5 Audio

Generate every sound in code at boot as short looped or one-shot `AudioStreamWAV` buffers. Play them by event id through `Audio`.

| Event | Placeholder sound |
|---|---|
| `engine` | Saw wave loop, 60 Hz at 40 km/h to 180 Hz at 160; a different added harmonic per gear |
| `rumble_strip` | 30 Hz noise bursts |
| `indicator_tick`, `lighter_click`, `bead_click` | Short clicks at different pitches |
| `horn` | Two square waves, 400 and 500 Hz |
| `wiper` | Filtered noise sweep |
| `grind` | Ratchet noise |
| `scrape`, `crash` | Noise bursts, 0.3 s and 0.8 s |
| `squeal_1` to `squeal_8` | Rising tone per chain step |
| `heartbeat` | A thump from 60 to 120 per minute with Nerves |
| `yawn`, `yawn_long` | A sine falling from 400 to 200 Hz, 0.8 s and 1.3 s |
| `phantom_hum` | 55 Hz sine |
| `siren_chirp`, `phone_ring` | Two-note patterns |
| `radio_music`, `radio_news`, `radio_callin`, `radio_static` | A four-note loop; speech-like blips; a different blip rhythm; noise |
| `clap`, `ululation` | A noise click; a fast trill |
| `heckle` | A soft ding before each heckle subtitle |

The rumble strip, the indicator tick and both yawns are functional cues and must be audible over everything else.

### 16.6 Subtitles

Bottom centre, at most two lines of 42 characters, with a speaker tag. Duration is the larger of 1.5 s and 0.06 s per character. Set text direction to automatic so right-to-left text works when Arabic lines arrive.

### 16.7 Note for the artist who comes later

This is direction, not a build task. The look should come from Iraqi visual tradition: flat colour, strong outline, and above all expressive hands. The hand is the most animated thing in the game. The palette is sodium orange, nicotine yellow and dashboard green. Dawn is the only clean light.

## 17. Settings, accessibility, localization and touch

### 17.1 Settings

| Setting | Options | Default |
|---|---|---|
| Steering sensitivity | 50% to 200% | 100% |
| Grip mode | Hold, or toggle (click to grip, click to release) | Hold |
| Shifting | Gate, or sequential flicks | Gate |
| Game speed | 70% to 100% | 100% |
| Brake assist | Slows the car when a crash is certain | Off |
| Steady start | The wheel holds itself for the first 2 s after each stop | On |
| The Phantom | On or off | On |
| Tremor and shake visuals | 0% to 100%. The mechanical effect stays. | 100% |
| Numeric HUD | On or off | Off |
| Subtitles | Size; background | Medium; on |
| Mirrored cabin | Mirrors the screen for left-handed mouse users. It does not change the story. | Off |

### 17.2 Accessibility rules

- Every tell has both a sound and a visual.
- Every function works with pointer motion and two buttons. Keyboard keys only duplicate.
- No time limit at stops or in menus.
- Every setting can be changed mid-Telling.

### 17.3 Localization

- All text comes from `lines_*.csv` through `Lines.get(id)`.
- Ship English placeholders. Keep `lines_ar.csv` with empty text so writers can fill it.
- Use a font slot per language in settings; the owner will add an Arabic font.

### 17.4 Touch

- Landscape only. The right thumb is the hand: lifting it is letting go.
- TAP rituals perform automatically when the hand arrives. HOLD, DRAG and CRANK need the gesture.
- The brake is a pedal zone at the bottom left for the left thumb.
- Tap targets are at least 9 mm across, even where the drawn object is smaller.

## 18. Milestones, acceptance tests and definition of done

Build in this order. Do not start a milestone until every test of the previous one passes.

| # | Milestone | Delivers | Tests that must pass |
|---|---|---|---|
| M0 | Harness | Project, folders, test runner, data validator, `check.sh`, docs files, all test ids registered | T-DATA-01, T-SMOKE-BOOT |
| M1 | The Hand and the wheel | Pointer, anchors, hand travel, left-side rule, glance, grip, steering, gestures, gear gate; a static cabin sandbox | T-HAND-01, 02, 03; T-WHEEL-01, 02; T-GATE-01, 02; T-GEST-01 |
| M2 | Driving | Lane-space car, speed, drift, road view, traffic, collisions, close calls | T-CAR-01 to 05; T-COL-01 to 03; T-CC-01, 02 |
| M3 | Nerves and the base cabin | Two-sided Nerves, impairments, Awake, radio, cigarettes, tea, photo, slap, window, horn, wipers, lamps and faults | T-NERVES-01 to 04; T-FAULT-01, 02; T-ITEM-BASE |
| M4 | Legs and encounters | Beat generator, nine leg types, modifiers, Patrol, Tailgater, Motorcade, Suspicion | T-GEN-01 to 03; T-SUS-01; T-LEG-01 to 09 |
| M5 | A whole Telling | Forks, Exits, stops, shopping with the hand, Clock, Cash, save and load, Wreck and restart | T-RUN-01, 02; T-CLOCK-01; T-STOP-01; T-SAVE-01; T-REPLAY-01 |
| M6 | All items | Every Habit, Keepsake, Adaptation, Deal, synergy and the Phantom | T-ITEM-* (one per item), T-SYN-* (one per synergy), T-PHANTOM-01 |
| M7 | Bosses | Checkpoint, Storm, Dawn, the Call, Arrival | T-BOSS-01 to 03; T-CALL-01 |
| M8 | Passengers | Five passengers, boarding, Hands, Weights, fares | T-PASS-* (one per passenger) |
| M9 | The frame | Wedding room, seven Tables, heckles, lines, endings, persistence, prologue, finale, modes | T-TABLE-* (one per Table); T-HECKLE-01; T-END-01; T-PROLOGUE-01; T-FINALE-01 |
| M10 | Presentation and options | Post effects, generated audio, subtitles, settings, mouse-only menus | T-ONEHAND-01; T-SETTINGS-01; T-SMOKE-ALL |
| M11 | Balance | The bot, the balance runner, a tuning pass toward section 12.5 | T-BOT-01 (report), T-WALL-01 |
| M12 | Touch and export | Touch input, export presets for Windows, Linux, macOS | T-TOUCH-01 |

### 18.1 Key test definitions

| Test | Passes when |
|---|---|
| T-HAND-01 | Travel time from G to every anchor matches section 16.2 within 0.02 s |
| T-HAND-02 | Hand speed left of the hub is 70% of normal |
| T-WHEEL-01 | Released at 135 degrees, the wheel reaches centre in 0.675 s |
| T-GATE-01 | Scripted lever paths engage gears 1 to 4, and 5 only with Fifth gear |
| T-GATE-02 | A release mid-channel and a push into a wall each produce one grind |
| T-CAR-01 | From lane centre, straight, gear 3, hands off: the car edge reaches the lane line at 3.4 s, within 0.05 s |
| T-CAR-02 | Full lock at 100 km/h settles at 5.0 m/s sideways |
| T-CAR-03 | 2,500 m takes 90.0 s in gear 3 and 69.2 s in gear 4, within 0.5 s |
| T-CAR-04 | Braking from 100 km/h to rest takes 3.33 s |
| T-COL-01 to 03 | Closing speeds of 20, 50 and 90 km/h give scrape, crash and head-on |
| T-CC-02 | Chained close calls multiply by 1.25 steps and cap at 3 |
| T-NERVES-01 | Each threshold switches its impairment on and off; a Snap resets Nerves to 70 |
| T-NERVES-02 | Below the floor and not Awake: a blink of 0.3 s every 6 s with a tell 1 s before |
| T-NERVES-03 | Every Awake source suppresses Lids, Blink and Nod for its duration |
| T-FAULT-01 | The fifth lamp is a Wreck; capacity changes apply |
| T-GEN-01 | For 500 seeds and all nine leg types, every rule in section 9.2 holds |
| T-GEN-02 | The same seed gives a byte-identical leg |
| T-WALL-01 | A scripted ideal driver in gear 3 clears every generated leg with no contact |
| T-REPLAY-01 | A recorded input log replays to the same final state hash |
| T-CLOCK-01 | 90 real seconds of driving is 30 game minutes |
| T-SUS-01 | Each row of section 6.5 changes Suspicion by its amount |
| T-CALL-01 | All four responses to the Call resolve as section 10.4 states |
| T-FINALE-01 | The finale ends only when the grip input is released; it runs 5 simulated minutes without ending otherwise |
| T-ONEHAND-01 | Every menu and every in-game action is reachable with pointer motion and two buttons |
| T-DATA-01 | All JSON validates; every referenced id and line id exists |
| T-BOT-01 | The balance runner completes and writes its report. It reports against section 12.5 and does not fail on the numbers. |

### 18.2 Done

The build is done when M0 to M12 are complete, `tools/check.sh` passes, `PROGRESS.md` lists every `NEEDS OWNER` item, and `artifacts/balance.json` exists.

---

